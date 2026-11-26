import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { type ExtensionAPI, type ExtensionContext, VERSION } from "@earendil-works/pi-coding-agent";
import {
	type CostUsage,
	defaultUsageLogPath,
	emptyCostUsage,
	emptyTokenUsage,
	exportUsageEvent,
	type ModelUsageEntry,
	resolveRepoNameOnly,
	type SandboxUsageInfo,
	sanitizeExtensionSource,
	type TokenUsage,
	type ToolCallStats,
	USAGE_SCHEMA_VERSION,
	type UsageSessionEventV1,
} from "./schema.ts";

const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

function readTeamPackageVersion(): string {
	try {
		const raw = fs.readFileSync(path.join(PACKAGE_ROOT, "package.json"), "utf8");
		const parsed = JSON.parse(raw) as { version?: unknown };
		return typeof parsed.version === "string" ? parsed.version : "unknown";
	} catch {
		return "unknown";
	}
}

function addTokenUsage(target: TokenUsage, raw: Record<string, unknown> | undefined): void {
	if (!raw) return;
	const input = typeof raw.input === "number" ? raw.input : 0;
	const output = typeof raw.output === "number" ? raw.output : 0;
	const cacheRead = typeof raw.cacheRead === "number" ? raw.cacheRead : 0;
	const cacheWrite = typeof raw.cacheWrite === "number" ? raw.cacheWrite : 0;
	const total =
		typeof raw.totalTokens === "number" ? raw.totalTokens : input + output + cacheRead + cacheWrite;

	target.input += input;
	target.output += output;
	target.cacheRead += cacheRead;
	target.cacheWrite += cacheWrite;
	target.total += total;
}

function addCostUsage(target: CostUsage, raw: Record<string, unknown> | undefined): void {
	if (!raw) return;
	const input = typeof raw.input === "number" ? raw.input : 0;
	const output = typeof raw.output === "number" ? raw.output : 0;
	const cacheRead = typeof raw.cacheRead === "number" ? raw.cacheRead : 0;
	const cacheWrite = typeof raw.cacheWrite === "number" ? raw.cacheWrite : 0;
	const total =
		typeof raw.total === "number" ? raw.total : input + output + cacheRead + cacheWrite;

	target.input += input;
	target.output += output;
	target.cacheRead += cacheRead;
	target.cacheWrite += cacheWrite;
	target.total += total;
}

export default function (pi: ExtensionAPI) {
	const teamPackageVersion = readTeamPackageVersion();

	let sessionStartedAtMs = Date.now();
	let sessionStartedIso = new Date(sessionStartedAtMs).toISOString();
	let sessionId = "ephemeral";
	let repoName: string | null = null;
	let mode = "unknown";
	let startReason = "startup";
	let primaryProvider: string | null = null;
	let primaryModel: string | null = null;
	let turnCount = 0;
	let totalToolCalls = 0;
	let totalToolErrors = 0;
	let exportedForSession = false;

	const tokens = emptyTokenUsage();
	const costUsd = emptyCostUsage();
	const modelsMap = new Map<string, ModelUsageEntry>();
	const toolCalls: Record<string, ToolCallStats> = {};
	const loadedExtensions = new Set<string>();
	const loadedSkills = new Set<string>();
	const skillPathToName = new Map<string, string>();
	const invokedSkills = new Set<string>();

	let sandbox: SandboxUsageInfo = {
		active: false,
		escapeHatchUsed: process.env.PI_SANDBOX_UNSAFE === "1",
		backend: null,
	};

	pi.events.on("pi-team:sandbox-state", (payload: unknown) => {
		if (!payload || typeof payload !== "object") return;
		const state = payload as {
			active?: unknown;
			escapeHatchUsed?: unknown;
			backend?: unknown;
		};
		sandbox = {
			active: Boolean(state.active),
			escapeHatchUsed: Boolean(state.escapeHatchUsed),
			backend: typeof state.backend === "string" ? state.backend : null,
		};
	});

	function resetSessionState(reason: string, ctx: ExtensionContext): void {
		sessionStartedAtMs = Date.now();
		sessionStartedIso = new Date(sessionStartedAtMs).toISOString();
		sessionId = ctx.sessionManager.getSessionId() || "ephemeral";
		repoName = resolveRepoNameOnly(ctx.cwd);
		mode = ctx.mode ?? "unknown";
		startReason = reason;
		primaryProvider = ctx.model?.provider ?? null;
		primaryModel = ctx.model?.id ?? null;
		turnCount = 0;
		totalToolCalls = 0;
		totalToolErrors = 0;
		exportedForSession = false;

		tokens.input = 0;
		tokens.output = 0;
		tokens.cacheRead = 0;
		tokens.cacheWrite = 0;
		tokens.total = 0;
		costUsd.input = 0;
		costUsd.output = 0;
		costUsd.cacheRead = 0;
		costUsd.cacheWrite = 0;
		costUsd.total = 0;
		modelsMap.clear();
		for (const key of Object.keys(toolCalls)) delete toolCalls[key];
		invokedSkills.clear();
		refreshLoadedResources();

		// Query gondolin-sandbox in case it started before this extension.
		pi.events.emit("pi-team:sandbox-query", {});
	}

	function refreshLoadedResources(): void {
		loadedExtensions.clear();
		loadedSkills.clear();
		skillPathToName.clear();

		for (const tool of pi.getAllTools()) {
			const extName = sanitizeExtensionSource(tool.sourceInfo?.source);
			if (extName) loadedExtensions.add(extName);
		}

		for (const cmd of pi.getCommands()) {
			if (cmd.source === "skill") {
				const skillName = cmd.name.startsWith("skill:") ? cmd.name.slice("skill:".length) : cmd.name;
				loadedSkills.add(skillName);
				if (cmd.sourceInfo?.path) {
					skillPathToName.set(path.resolve(cmd.sourceInfo.path), skillName);
				}
			} else if (cmd.source === "extension") {
				const extName = sanitizeExtensionSource(cmd.sourceInfo?.source);
				if (extName) loadedExtensions.add(extName);
			}
		}
	}

	function recordModelUsage(
		provider: string | undefined,
		model: string | undefined,
		usageRaw: Record<string, unknown> | undefined,
	): void {
		const p = provider || primaryProvider || "unknown";
		const m = model || primaryModel || "unknown";
		primaryProvider = p;
		primaryModel = m;

		if (!usageRaw) return;
		const costRaw =
			usageRaw.cost && typeof usageRaw.cost === "object"
				? (usageRaw.cost as Record<string, unknown>)
				: undefined;

		addTokenUsage(tokens, usageRaw);
		addCostUsage(costUsd, costRaw);

		const key = `${p}/${m}`;
		let entry = modelsMap.get(key);
		if (!entry) {
			entry = {
				provider: p,
				model: m,
				responses: 0,
				tokens: emptyTokenUsage(),
				costUsd: emptyCostUsage(),
			};
			modelsMap.set(key, entry);
		}
		entry.responses += 1;
		addTokenUsage(entry.tokens, usageRaw);
		addCostUsage(entry.costUsd, costRaw);
	}

	function flushSummary(endReason: string): void {
		if (exportedForSession) return;
		exportedForSession = true;

		// Refresh resource inventory right before flush to catch dynamically loaded skills/tools.
		try {
			refreshLoadedResources();
		} catch {
			// Ignore if runtime is already tearing down.
		}

		const endedAtMs = Date.now();
		const event: UsageSessionEventV1 = {
			schemaVersion: USAGE_SCHEMA_VERSION,
			eventType: "session_summary",
			startedAt: sessionStartedIso,
			endedAt: new Date(endedAtMs).toISOString(),
			durationMs: Math.max(0, endedAtMs - sessionStartedAtMs),
			sessionId,
			repoName,
			piVersion: VERSION,
			teamPackageVersion,
			mode,
			startReason,
			endReason,
			provider: primaryProvider,
			model: primaryModel,
			modelsUsed: [...modelsMap.values()],
			tokens,
			costUsd,
			turnCount,
			toolCalls,
			totalToolCalls,
			totalToolErrors,
			loadedExtensions: [...loadedExtensions],
			loadedSkills: [...loadedSkills],
			invokedSkills: [...invokedSkills],
			sandbox,
		};

		try {
			exportUsageEvent(event, defaultUsageLogPath());
		} catch {
			// Usage telemetry must never crash or disrupt the user's session.
		}
	}

	pi.on("session_start", (event, ctx) => {
		resetSessionState(event.reason, ctx);
	});

	pi.on("model_select", (event) => {
		primaryProvider = event.model.provider;
		primaryModel = event.model.id;
	});

	// Detect explicit `/skill:<name>` invocations without ever inspecting or storing the rest of input.
	pi.on("input", (event) => {
		const match = /^\s*\/skill:([A-Za-z0-9_.:-]+)/.exec(event.text);
		if (match?.[1]) {
			invokedSkills.add(match[1]);
		}
	});

	// Detect model-driven skill reads (reading a known skill's SKILL.md) — records ONLY the skill name.
	pi.on("tool_call", (event) => {
		if (event.toolName !== "read" || skillPathToName.size === 0) return;
		const input = event.input as { path?: unknown } | undefined;
		if (typeof input?.path !== "string") return;
		const resolved = path.resolve(input.path.replace(/^@/, "").trim());
		const matchedSkill = skillPathToName.get(resolved);
		if (matchedSkill) {
			invokedSkills.add(matchedSkill);
		}
	});

	pi.on("tool_execution_end", (event) => {
		const name = event.toolName || "unknown";
		if (!toolCalls[name]) {
			toolCalls[name] = { calls: 0, errors: 0 };
		}
		toolCalls[name].calls += 1;
		totalToolCalls += 1;
		if (event.isError) {
			toolCalls[name].errors += 1;
			totalToolErrors += 1;
		}
	});

	pi.on("message_end", (event) => {
		const msg = event.message as unknown as Record<string, unknown>;
		if (msg?.role !== "assistant") return;
		recordModelUsage(
			typeof msg.provider === "string" ? msg.provider : undefined,
			typeof msg.model === "string" ? msg.model : undefined,
			msg.usage && typeof msg.usage === "object"
				? (msg.usage as Record<string, unknown>)
				: undefined,
		);
	});

	pi.on("session_compact", (event) => {
		const entry = event.compactionEntry as unknown as Record<string, unknown> | undefined;
		if (entry?.usage && typeof entry.usage === "object") {
			recordModelUsage(undefined, undefined, entry.usage as Record<string, unknown>);
		}
	});

	pi.on("turn_end", () => {
		turnCount += 1;
	});

	pi.on("session_shutdown", (event) => {
		flushSummary(event.reason || "quit");
	});
}
