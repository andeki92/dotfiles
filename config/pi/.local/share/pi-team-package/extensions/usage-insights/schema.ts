import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const USAGE_SCHEMA_VERSION = 1 as const;

export interface TokenUsage {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	total: number;
}

export interface CostUsage {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	total: number;
}

export interface ModelUsageEntry {
	provider: string;
	model: string;
	responses: number;
	tokens: TokenUsage;
	costUsd: CostUsage;
}

export interface ToolCallStats {
	calls: number;
	errors: number;
}

export interface SandboxUsageInfo {
	active: boolean;
	escapeHatchUsed: boolean;
	backend: string | null;
}

export interface UsageSessionEventV1 {
	schemaVersion: typeof USAGE_SCHEMA_VERSION;
	eventType: "session_summary";
	startedAt: string;
	endedAt: string;
	durationMs: number;
	sessionId: string;
	repoName: string | null;
	piVersion: string;
	teamPackageVersion: string;
	mode: string;
	startReason: string;
	endReason: string;
	provider: string | null;
	model: string | null;
	modelsUsed: ModelUsageEntry[];
	tokens: TokenUsage;
	costUsd: CostUsage;
	turnCount: number;
	toolCalls: Record<string, ToolCallStats>;
	totalToolCalls: number;
	totalToolErrors: number;
	loadedExtensions: string[];
	loadedSkills: string[];
	invokedSkills: string[];
	sandbox: SandboxUsageInfo;
}

export function emptyTokenUsage(): TokenUsage {
	return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 };
}

export function emptyCostUsage(): CostUsage {
	return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 };
}

function nonNegativeNumber(value: unknown): number {
	return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0;
}

function roundUsd(value: number): number {
	return Math.round(value * 1_000_000) / 1_000_000;
}

/**
 * Extracts ONLY the repository (or directory) basename — never parent paths,
 * home paths, or usernames.
 */
export function resolveRepoNameOnly(cwd: string): string | null {
	if (!cwd) return null;
	let current = path.resolve(cwd);
	let targetDir = current;

	while (true) {
		if (fs.existsSync(path.join(current, ".git"))) {
			targetDir = current;
			break;
		}
		const parent = path.dirname(current);
		if (parent === current) break;
		current = parent;
	}

	const base = path.basename(targetDir).trim();
	if (!base || base === "/" || base === ".") return null;
	return base.replace(/[/\\]/g, "_").slice(0, 128);
}

/**
 * Converts a Pi `sourceInfo.source` string into a safe extension identifier
 * with no local host paths or usernames.
 */
export function sanitizeExtensionSource(rawSource: string | undefined): string | null {
	if (!rawSource) return null;
	const trimmed = rawSource.trim();
	if (!trimmed || trimmed === "builtin" || trimmed === "sdk") return null;

	// Package specs such as `npm:@scope/pkg@1.0.0` or `git:github.com/org/repo@v1`
	if (trimmed.startsWith("npm:")) {
		return trimmed.slice(0, 128);
	}
	if (trimmed.startsWith("git:") || trimmed.startsWith("https://") || trimmed.startsWith("http://")) {
		// Strip any accidental userinfo@ from URLs
		return trimmed.replace(/\/\/[^/@]+@/, "//").slice(0, 128);
	}

	// Local filesystem path: keep ONLY the final path segment (e.g. `pi-team-package` or `atuin.ts`).
	const normalized = trimmed.replace(/\\/g, "/").replace(/\/+$/, "");
	const base = path.posix.basename(normalized);
	if (!base || base === "." || base === "..") return null;
	return base.slice(0, 128);
}

/**
 * Strict allowlist serializer: constructs a fresh plain object with ONLY the
 * documented v1 metadata fields so prompts, outputs, commands, file contents,
 * paths, or env vars can never leak into the JSONL log.
 */
export function buildUsageEventV1(input: UsageSessionEventV1): UsageSessionEventV1 {
	const safeToolCalls: Record<string, ToolCallStats> = {};
	for (const toolName of Object.keys(input.toolCalls).sort()) {
		const stats = input.toolCalls[toolName];
		if (!stats) continue;
		const safeName = toolName.replace(/[^A-Za-z0-9_.:/-]/g, "_").slice(0, 128);
		safeToolCalls[safeName] = {
			calls: Math.trunc(nonNegativeNumber(stats.calls)),
			errors: Math.trunc(nonNegativeNumber(stats.errors)),
		};
	}

	const safeModels: ModelUsageEntry[] = input.modelsUsed.map((m) => ({
		provider: String(m.provider).slice(0, 128),
		model: String(m.model).slice(0, 128),
		responses: Math.trunc(nonNegativeNumber(m.responses)),
		tokens: {
			input: Math.trunc(nonNegativeNumber(m.tokens.input)),
			output: Math.trunc(nonNegativeNumber(m.tokens.output)),
			cacheRead: Math.trunc(nonNegativeNumber(m.tokens.cacheRead)),
			cacheWrite: Math.trunc(nonNegativeNumber(m.tokens.cacheWrite)),
			total: Math.trunc(nonNegativeNumber(m.tokens.total)),
		},
		costUsd: {
			input: roundUsd(nonNegativeNumber(m.costUsd.input)),
			output: roundUsd(nonNegativeNumber(m.costUsd.output)),
			cacheRead: roundUsd(nonNegativeNumber(m.costUsd.cacheRead)),
			cacheWrite: roundUsd(nonNegativeNumber(m.costUsd.cacheWrite)),
			total: roundUsd(nonNegativeNumber(m.costUsd.total)),
		},
	}));

	return {
		schemaVersion: USAGE_SCHEMA_VERSION,
		eventType: "session_summary",
		startedAt: input.startedAt,
		endedAt: input.endedAt,
		durationMs: Math.trunc(nonNegativeNumber(input.durationMs)),
		sessionId: String(input.sessionId || "ephemeral").slice(0, 128),
		repoName: input.repoName ? input.repoName.replace(/[/\\]/g, "_").slice(0, 128) : null,
		piVersion: String(input.piVersion || "unknown").slice(0, 64),
		teamPackageVersion: String(input.teamPackageVersion || "unknown").slice(0, 64),
		mode: String(input.mode || "unknown").slice(0, 32),
		startReason: String(input.startReason || "startup").slice(0, 32),
		endReason: String(input.endReason || "quit").slice(0, 32),
		provider: input.provider ? String(input.provider).slice(0, 128) : null,
		model: input.model ? String(input.model).slice(0, 128) : null,
		modelsUsed: safeModels,
		tokens: {
			input: Math.trunc(nonNegativeNumber(input.tokens.input)),
			output: Math.trunc(nonNegativeNumber(input.tokens.output)),
			cacheRead: Math.trunc(nonNegativeNumber(input.tokens.cacheRead)),
			cacheWrite: Math.trunc(nonNegativeNumber(input.tokens.cacheWrite)),
			total: Math.trunc(nonNegativeNumber(input.tokens.total)),
		},
		costUsd: {
			input: roundUsd(nonNegativeNumber(input.costUsd.input)),
			output: roundUsd(nonNegativeNumber(input.costUsd.output)),
			cacheRead: roundUsd(nonNegativeNumber(input.costUsd.cacheRead)),
			cacheWrite: roundUsd(nonNegativeNumber(input.costUsd.cacheWrite)),
			total: roundUsd(nonNegativeNumber(input.costUsd.total)),
		},
		turnCount: Math.trunc(nonNegativeNumber(input.turnCount)),
		toolCalls: safeToolCalls,
		totalToolCalls: Math.trunc(nonNegativeNumber(input.totalToolCalls)),
		totalToolErrors: Math.trunc(nonNegativeNumber(input.totalToolErrors)),
		loadedExtensions: [...new Set(input.loadedExtensions)].sort(),
		loadedSkills: [...new Set(input.loadedSkills)].sort(),
		invokedSkills: [...new Set(input.invokedSkills)].sort(),
		sandbox: {
			active: Boolean(input.sandbox.active),
			escapeHatchUsed: Boolean(input.sandbox.escapeHatchUsed),
			backend: input.sandbox.backend ? String(input.sandbox.backend).slice(0, 32) : null,
		},
	};
}

export function defaultUsageLogPath(env: NodeJS.ProcessEnv = process.env): string {
	if (env.PI_USAGE_LOG_PATH?.trim()) {
		return path.resolve(env.PI_USAGE_LOG_PATH.trim());
	}
	const stateHome = env.XDG_STATE_HOME?.trim() || path.join(os.homedir(), ".local", "state");
	return path.join(stateHome, "pi", "usage.jsonl");
}

/**
 * Single telemetry sink for Pi usage events.
 *
 * Today: writes one metadata-only JSONL record to the local XDG state file.
 * Future software-factory collector: add or swap in an OTLP/HTTP exporter
 * (e.g. batched POST to an internal OpenTelemetry Collector endpoint) here
 * without changing any event collection logic.
 */
export function exportUsageEvent(
	event: UsageSessionEventV1,
	logPath: string = defaultUsageLogPath(),
): void {
	const sanitized = buildUsageEventV1(event);
	const dir = path.dirname(logPath);
	fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
	fs.appendFileSync(logPath, `${JSON.stringify(sanitized)}\n`, {
		encoding: "utf8",
		mode: 0o600,
	});
}
