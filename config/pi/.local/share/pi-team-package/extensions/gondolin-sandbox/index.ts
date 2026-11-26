import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	BASE62_ALPHABET,
	createHttpHooks,
	HttpRequestBlockedError,
	listImageRefs,
	makePlaceholderFunc,
	RealFSProvider,
	VM,
} from "@earendil-works/gondolin";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
	type BashOperations,
	createBashTool,
	createEditTool,
	createFindTool,
	createGrepTool,
	createLsTool,
	createReadTool,
	createWriteTool,
	DEFAULT_MAX_BYTES,
	type EditOperations,
	type FindOperations,
	formatSize,
	type GrepToolDetails,
	type GrepToolInput,
	type LsOperations,
	type ReadOperations,
	truncateHead,
	truncateLine,
	type WriteOperations,
} from "@earendil-works/pi-coding-agent";
import {
	assertSafeWorkspaceDir,
	type BackendConfig,
	buildGuestEnv,
	evaluateGitHubRepoAccess,
	GITHUB_SECRET_HOSTS,
	loadEgressPolicy,
	loadSandboxConfig,
	resolveBackendConfig,
	resolveGitHubAuth,
	resolveHostGitIdentity,
	toGuestPath,
	toPosix,
} from "./policy.ts";

const DEFAULT_GREP_LIMIT = 100;
const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

export interface SandboxStatePayload {
	active: boolean;
	escapeHatchUsed: boolean;
	backend: "krun" | "qemu" | null;
	rootfsMode: "readonly" | "cow" | null;
	guestWorkspace: string | null;
}

type TextToolResult<TDetails> = {
	content: Array<{ type: "text"; text: string }>;
	details: TDetails | undefined;
};

function hasLocalGondolinImage(imageRef: string): boolean {
	try {
		const expectedArch = process.arch === "arm64" ? "aarch64" : "x86_64";
		const refs = listImageRefs();
		return refs.some(
			(ref) => ref.reference === imageRef && Boolean(ref.targets?.[expectedArch]),
		);
	} catch {
		return false;
	}
}

function createGondolinReadOps(
	vm: VM,
	localCwd: string,
	realLocalCwd: string,
	guestWorkspace: string,
): ReadOperations {
	return {
		readFile: async (filePath) =>
			vm.fs.readFile(toGuestPath(localCwd, guestWorkspace, filePath, realLocalCwd)),
		access: async (filePath) => {
			await vm.fs.access(toGuestPath(localCwd, guestWorkspace, filePath, realLocalCwd));
		},
		detectImageMimeType: async (filePath) => {
			const ext = path.posix
				.extname(toGuestPath(localCwd, guestWorkspace, filePath, realLocalCwd))
				.toLowerCase();
			if (ext === ".png") return "image/png";
			if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
			if (ext === ".gif") return "image/gif";
			if (ext === ".webp") return "image/webp";
			return null;
		},
	};
}

function createGondolinWriteOps(
	vm: VM,
	localCwd: string,
	realLocalCwd: string,
	guestWorkspace: string,
): WriteOperations {
	return {
		writeFile: async (filePath, content) => {
			await vm.fs.writeFile(toGuestPath(localCwd, guestWorkspace, filePath, realLocalCwd), content, {
				encoding: "utf8",
			});
		},
		mkdir: async (dirPath) => {
			await vm.fs.mkdir(toGuestPath(localCwd, guestWorkspace, dirPath, realLocalCwd), {
				recursive: true,
			});
		},
	};
}

function createGondolinEditOps(
	vm: VM,
	localCwd: string,
	realLocalCwd: string,
	guestWorkspace: string,
): EditOperations {
	const readOps = createGondolinReadOps(vm, localCwd, realLocalCwd, guestWorkspace);
	const writeOps = createGondolinWriteOps(vm, localCwd, realLocalCwd, guestWorkspace);
	return {
		readFile: readOps.readFile,
		writeFile: writeOps.writeFile,
		access: readOps.access,
	};
}

function createGondolinLsOps(
	vm: VM,
	localCwd: string,
	realLocalCwd: string,
	guestWorkspace: string,
): LsOperations {
	return {
		exists: async (filePath) => {
			try {
				await vm.fs.access(toGuestPath(localCwd, guestWorkspace, filePath, realLocalCwd));
				return true;
			} catch {
				return false;
			}
		},
		stat: async (filePath) =>
			vm.fs.stat(toGuestPath(localCwd, guestWorkspace, filePath, realLocalCwd)),
		readdir: async (dirPath) =>
			vm.fs.listDir(toGuestPath(localCwd, guestWorkspace, dirPath, realLocalCwd)),
	};
}

async function walkGuestFiles(
	vm: VM,
	root: string,
	visit: (guestPath: string, relativePath: string) => Promise<boolean>,
	signal?: AbortSignal,
): Promise<boolean> {
	if (signal?.aborted) throw new Error("Operation aborted");
	const stat = await vm.fs.stat(root, { signal });
	if (!stat.isDirectory()) return visit(root, path.posix.basename(root));

	const walkDirectory = async (dir: string, relativeDir: string): Promise<boolean> => {
		if (signal?.aborted) throw new Error("Operation aborted");
		const entries = await vm.fs.listDir(dir, { signal });
		for (const entry of entries) {
			if (entry === ".git" || entry === "node_modules") continue;
			const guestPath = path.posix.join(dir, entry);
			const relativePath = relativeDir ? path.posix.join(relativeDir, entry) : entry;
			let entryStat: Awaited<ReturnType<VM["fs"]["stat"]>>;
			try {
				entryStat = await vm.fs.stat(guestPath, { signal });
			} catch {
				continue;
			}
			if (entryStat.isDirectory()) {
				if (!(await walkDirectory(guestPath, relativePath))) return false;
			} else if (!(await visit(guestPath, relativePath))) {
				return false;
			}
		}
		return true;
	};

	return walkDirectory(root, "");
}

function matchesToolGlob(relativePath: string, pattern: string): boolean {
	const normalizedPattern = toPosix(pattern).replace(/^(?:\.\/)+/, "");
	if (normalizedPattern.includes("/")) return path.posix.matchesGlob(relativePath, normalizedPattern);
	return path.posix.matchesGlob(path.posix.basename(relativePath), normalizedPattern);
}

function createGondolinFindOps(
	vm: VM,
	localCwd: string,
	realLocalCwd: string,
	guestWorkspace: string,
): FindOperations {
	return {
		exists: async (filePath) => {
			try {
				await vm.fs.access(toGuestPath(localCwd, guestWorkspace, filePath, realLocalCwd));
				return true;
			} catch {
				return false;
			}
		},
		glob: async (pattern, cwd, options) => {
			const root = toGuestPath(localCwd, guestWorkspace, cwd, realLocalCwd);
			const results: string[] = [];
			await walkGuestFiles(vm, root, async (guestPath, relativePath) => {
				if (results.length >= options.limit) return false;
				if (matchesToolGlob(relativePath, pattern)) results.push(guestPath);
				return results.length < options.limit;
			});
			return results;
		},
	};
}

function createLineMatcher(
	pattern: string,
	literal: boolean | undefined,
	ignoreCase: boolean | undefined,
) {
	if (literal) {
		const needle = ignoreCase ? pattern.toLowerCase() : pattern;
		return (line: string) => (ignoreCase ? line.toLowerCase() : line).includes(needle);
	}
	const regex = new RegExp(pattern, ignoreCase ? "i" : undefined);
	return (line: string) => regex.test(line);
}

function appendGrepBlock(params: {
	outputLines: string[];
	lines: string[];
	relativePath: string;
	lineIndex: number;
	contextLines: number;
}): boolean {
	let linesTruncated = false;
	const start =
		params.contextLines > 0 ? Math.max(0, params.lineIndex - params.contextLines) : params.lineIndex;
	const end =
		params.contextLines > 0
			? Math.min(params.lines.length - 1, params.lineIndex + params.contextLines)
			: params.lineIndex;

	for (let index = start; index <= end; index++) {
		const rawLine = params.lines[index] ?? "";
		const { text, wasTruncated } = truncateLine(rawLine.replace(/\r/g, ""));
		if (wasTruncated) linesTruncated = true;
		const separator = index === params.lineIndex ? ":" : "-";
		params.outputLines.push(`${params.relativePath}${separator}${index + 1}${separator} ${text}`);
	}
	return linesTruncated;
}

async function executeGondolinGrep(
	vm: VM,
	localCwd: string,
	realLocalCwd: string,
	guestWorkspace: string,
	params: GrepToolInput,
	signal?: AbortSignal,
): Promise<TextToolResult<GrepToolDetails>> {
	const root = toGuestPath(localCwd, guestWorkspace, params.path ?? ".", realLocalCwd);
	const rootStat = await vm.fs.stat(root, { signal });
	const rootIsDirectory = rootStat.isDirectory();
	const matcher = createLineMatcher(params.pattern, params.literal, params.ignoreCase);
	const contextLines = params.context && params.context > 0 ? params.context : 0;
	const effectiveLimit = Math.max(1, params.limit ?? DEFAULT_GREP_LIMIT);
	const outputLines: string[] = [];
	const details: GrepToolDetails = {};
	let matchCount = 0;
	let matchLimitReached = false;
	let linesTruncated = false;

	await walkGuestFiles(
		vm,
		root,
		async (guestPath, relativePath) => {
			if (matchCount >= effectiveLimit) return false;
			if (params.glob && !matchesToolGlob(relativePath, params.glob)) return true;
			let content: string;
			try {
				content = await vm.fs.readFile(guestPath, { encoding: "utf8", signal });
			} catch {
				return true;
			}
			const lines = content.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
			const displayPath = rootIsDirectory ? relativePath : path.posix.basename(guestPath);
			for (let index = 0; index < lines.length; index++) {
				if (signal?.aborted) throw new Error("Operation aborted");
				if (!matcher(lines[index] ?? "")) continue;
				matchCount++;
				if (
					appendGrepBlock({
						outputLines,
						lines,
						relativePath: displayPath,
						lineIndex: index,
						contextLines,
					})
				) {
					linesTruncated = true;
				}
				if (matchCount >= effectiveLimit) {
					matchLimitReached = true;
					return false;
				}
			}
			return true;
		},
		signal,
	);

	if (matchCount === 0) {
		return { content: [{ type: "text", text: "No matches found" }], details: undefined };
	}

	const rawOutput = outputLines.join("\n");
	const truncation = truncateHead(rawOutput, { maxLines: Number.MAX_SAFE_INTEGER });
	const notices: string[] = [];
	let output = truncation.content;

	if (matchLimitReached) {
		details.matchLimitReached = effectiveLimit;
		notices.push(`${effectiveLimit} matches limit reached`);
	}
	if (linesTruncated) {
		details.linesTruncated = true;
		notices.push("long lines truncated");
	}
	if (truncation.truncated) {
		details.truncation = truncation;
		notices.push(`${formatSize(DEFAULT_MAX_BYTES)} limit reached`);
	}
	if (notices.length > 0) output += `\n\n[${notices.join(". ")}]`;

	return {
		content: [{ type: "text", text: output }],
		details: Object.keys(details).length > 0 ? details : undefined,
	};
}

function createGondolinBashOps(
	vm: VM,
	localCwd: string,
	realLocalCwd: string,
	guestWorkspace: string,
	shellPath: string,
	guestEnv: Record<string, string>,
): BashOperations {
	return {
		exec: async (command, cwd, { onData, signal, timeout }) => {
			if (signal?.aborted) throw new Error("aborted");
			const guestCwd = toGuestPath(localCwd, guestWorkspace, cwd, realLocalCwd);
			const controller = new AbortController();
			const onAbort = () => controller.abort();
			signal?.addEventListener("abort", onAbort, { once: true });

			let timedOut = false;
			const timer =
				timeout && timeout > 0
					? setTimeout(() => {
							timedOut = true;
							controller.abort();
						}, timeout * 1000)
					: undefined;

			try {
				const proc = vm.exec([shellPath, "-lc", command], {
					cwd: guestCwd,
					env: guestEnv,
					signal: controller.signal,
					stdout: "pipe",
					stderr: "pipe",
				});
				for await (const chunk of proc.output()) onData(chunk.data);
				const result = await proc;
				return { exitCode: result.exitCode };
			} catch (error) {
				if (signal?.aborted) throw new Error("aborted");
				if (timedOut) throw new Error(`timeout:${timeout}`);
				throw error;
			} finally {
				if (timer) clearTimeout(timer);
				signal?.removeEventListener("abort", onAbort);
			}
		},
	};
}

function failClosedExit(reason: string): never {
	process.stderr.write(
		[
			"",
			"[gondolin-sandbox] FATAL: Failed to start Gondolin micro-VM sandbox.",
			`[gondolin-sandbox] Reason: ${reason}`,
			"[gondolin-sandbox] Refusing to fall back to host tools (fail-closed).",
			"[gondolin-sandbox] If you explicitly intend to run unsandboxed, use: pi-unsafe",
			"",
		].join("\n"),
	);
	process.exit(2);
}

export default function (pi: ExtensionAPI) {
	const escapeHatchUsed = process.env.PI_SANDBOX_UNSAFE === "1";

	if (escapeHatchUsed) {
		const unsafeState: SandboxStatePayload = {
			active: false,
			escapeHatchUsed: true,
			backend: null,
			rootfsMode: null,
			guestWorkspace: null,
		};

		pi.events.on("pi-team:sandbox-query", () => {
			pi.events.emit("pi-team:sandbox-state", unsafeState);
		});

		pi.on("session_start", (_event, ctx) => {
			pi.events.emit("pi-team:sandbox-state", unsafeState);
			if (ctx.hasUI) {
				ctx.ui.setStatus("gondolin", ctx.ui.theme.fg("error", "SANDBOX OFF (pi-unsafe)"));
				ctx.ui.notify(
					"Gondolin sandbox is DISABLED via pi-unsafe. Built-in tools have direct host access.",
					"warning",
				);
			}
		});

		pi.registerCommand("sandbox", {
			description: "Show Gondolin sandbox status",
			handler: async (_args, ctx) => {
				ctx.ui.notify(
					"Gondolin sandbox is DISABLED (PI_SANDBOX_UNSAFE=1 / pi-unsafe). Tools run directly on the host.",
					"warning",
				);
			},
		});

		return;
	}

	const localCwd = process.cwd();
	const realLocalCwd = fs.existsSync(localCwd) ? fs.realpathSync(localCwd) : localCwd;
	const localRead = createReadTool(localCwd);
	const localWrite = createWriteTool(localCwd);
	const localEdit = createEditTool(localCwd);
	const localBash = createBashTool(localCwd, { exposeSessionEnvironment: false });
	const localGrep = createGrepTool(localCwd);
	const localFind = createFindTool(localCwd);
	const localLs = createLsTool(localCwd);

	let vm: VM | undefined;
	let vmStarting: Promise<VM> | undefined;
	let shellPath = "/bin/sh";
	let activeBackend: BackendConfig | undefined;
	let activeGuestEnv: Record<string, string> = {};
	let activeAllowedHosts: string[] = [];
	let activeAllowedRepos: string[] = [];
	let activeEgressSource = "default";
	let activeConfigFiles: string[] = [];
	let activeGhAuthSource: string | null = null;

	function currentState(): SandboxStatePayload {
		return {
			active: vm !== undefined,
			escapeHatchUsed: false,
			backend: activeBackend?.vmm ?? null,
			rootfsMode: activeBackend?.rootfsMode ?? null,
			guestWorkspace: activeBackend?.guestWorkspace ?? null,
		};
	}

	pi.events.on("pi-team:sandbox-query", () => {
		pi.events.emit("pi-team:sandbox-state", currentState());
	});

	async function startVm(ctx?: ExtensionContext): Promise<VM> {
		assertSafeWorkspaceDir(realLocalCwd);
		const sandboxConfig = loadSandboxConfig(process.env);
		const backend = resolveBackendConfig(
			PACKAGE_ROOT,
			process.env,
			hasLocalGondolinImage,
			sandboxConfig,
		);
		const egress = loadEgressPolicy(process.env, sandboxConfig);
		const ghAuth = resolveGitHubAuth(process.env, sandboxConfig);
		const gitIdentity = resolveHostGitIdentity(realLocalCwd, process.env, sandboxConfig);

		const { httpHooks, env: hookEnv } = createHttpHooks({
			allowedHosts: egress.allowedHosts,
			blockInternalRanges: true,
			...(ghAuth
				? {
						secrets: {
							GH_TOKEN: {
								hosts: [...GITHUB_SECRET_HOSTS],
								value: ghAuth.token,
								placeholder: makePlaceholderFunc({
									prefix: "ghp_",
									length: 36,
									alphabet: BASE62_ALPHABET,
								}),
							},
						},
					}
				: {}),
			...(egress.allowedGitHubRepos.length > 0
				? {
						onRequest: async (request: Request) => {
							let graphqlVariables: Record<string, unknown> | undefined;
							if (
								request.method === "POST" &&
								new URL(request.url).hostname.toLowerCase() === "api.github.com" &&
								new URL(request.url).pathname === "/graphql"
							) {
								try {
									const body = (await request.clone().json()) as {
										variables?: Record<string, unknown>;
									};
									if (body?.variables && typeof body.variables === "object") {
										graphqlVariables = body.variables;
									}
								} catch {
									// non-JSON body; let normal checks handle it
								}
							}
							const verdict = evaluateGitHubRepoAccess(
								request.url,
								egress.allowedGitHubRepos,
								graphqlVariables,
							);
							if (!verdict.allowed) {
								throw new HttpRequestBlockedError(
									verdict.reason || "GitHub repository blocked by sandbox policy",
									403,
									"Forbidden",
								);
							}
						},
					}
				: {}),
		});

		const guestEnv = buildGuestEnv(process.env, hookEnv, gitIdentity);

		ctx?.ui.setStatus(
			"gondolin",
			ctx.ui.theme.fg("accent", `Sandbox: starting (${backend.vmm})`),
		);

		const created = await VM.create({
			sessionLabel: `pi ${path.basename(realLocalCwd)}`,
			sandbox: {
				vmm: backend.vmm,
				...(backend.imagePath ? { imagePath: backend.imagePath } : {}),
				...(backend.krunRunnerPath ? { krunRunnerPath: backend.krunRunnerPath } : {}),
				...(backend.qemuPath ? { qemuPath: backend.qemuPath } : {}),
			},
			rootfs: { mode: backend.rootfsMode },
			httpHooks,
			env: guestEnv,
			dns: { mode: "synthetic" },
			allowWebSockets: false,
			vfs: {
				mounts: {
					[backend.guestWorkspace]: new RealFSProvider(realLocalCwd),
				},
			},
		});

		const bashProbe = await created.exec(["/bin/sh", "-lc", "command -v bash || true"], {
			env: guestEnv,
		});
		shellPath = bashProbe.stdout.trim() || "/bin/sh";
		vm = created;
		activeBackend = backend;
		activeGuestEnv = guestEnv;
		activeAllowedHosts = egress.allowedHosts;
		activeAllowedRepos = egress.allowedGitHubRepos;
		activeEgressSource = egress.source;
		activeConfigFiles = sandboxConfig.loadedFiles;
		activeGhAuthSource = ghAuth?.source ?? null;

		pi.events.emit("pi-team:sandbox-state", currentState());
		const ghBadge = activeGhAuthSource ? " +gh" : "";
		ctx?.ui.setStatus(
			"gondolin",
			ctx.ui.theme.fg("accent", `Sandbox: ${backend.vmm}${ghBadge} (${backend.guestWorkspace})`),
		);
		return created;
	}

	async function ensureVm(ctx?: ExtensionContext): Promise<VM> {
		if (vm) return vm;
		if (!vmStarting) {
			vmStarting = startVm(ctx).finally(() => {
				vmStarting = undefined;
			});
		}
		return vmStarting;
	}

	pi.on("session_start", async (_event, ctx) => {
		try {
			await ensureVm(ctx);
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			failClosedExit(message);
		}
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		const activeVm = vm;
		vm = undefined;
		vmStarting = undefined;
		if (!activeVm) return;
		if (ctx.hasUI) {
			ctx.ui.setStatus("gondolin", ctx.ui.theme.fg("muted", "Sandbox: stopping"));
		}
		try {
			await activeVm.close();
		} finally {
			if (ctx.hasUI) {
				ctx.ui.setStatus("gondolin", undefined);
			}
		}
	});

	pi.on("tool_call", async (event) => {
		if (event.toolName === "powershell") {
			return {
				block: true,
				reason: "Blocked by gondolin-sandbox: Windows/PowerShell interop is disabled inside sandboxed sessions.",
			};
		}

		if (event.toolName === "subagent") {
			const input = event.input as Record<string, unknown> | undefined;
			if (input && input.async === false) {
				return {
					block: true,
					reason:
						"Blocked by gondolin-sandbox: foreground subagents (async: false) do not load ambient extensions and would bypass Gondolin. Run background subagents (async: true) instead.",
				};
			}
		}
	});

	pi.registerCommand("sandbox", {
		description: "Show Gondolin sandbox status, image, GitHub auth mode, and egress allowlist",
		handler: async (_args, ctx) => {
			const activeVm = await ensureVm(ctx);
			ctx.ui.notify(
				[
					`Gondolin VM: ${activeVm.id}`,
					`Config: ${activeConfigFiles.length > 0 ? activeConfigFiles.join(" + ") : "(defaults — create ~/.config/sandbox.toml)"}`,
					`Image: ${activeBackend?.imagePath ?? "alpine-base (run scripts/pi-build-image.sh for git+gh+kustomize)"}`,
					`Backend: ${activeBackend?.vmm ?? "unknown"} (rootfs: ${activeBackend?.rootfsMode ?? "unknown"})`,
					`Workspace mount: ${realLocalCwd} -> ${activeBackend?.guestWorkspace ?? "/workspace"}`,
					`Guest shell: ${shellPath}`,
					`GitHub auth (host-substituted placeholder): ${activeGhAuthSource ?? "none (configure [github] in ~/.config/sandbox.toml or sandbox.local.toml)"}`,
					`GitHub repo allowlist: ${activeAllowedRepos.length > 0 ? activeAllowedRepos.join(", ") : "(none — enforced by token scope)"}`,
					`Egress policy (${activeEgressSource}): ${activeAllowedHosts.length} allowlisted host(s), internal ranges blocked, synthetic DNS`,
				].join("\n"),
				"info",
			);
		},
	});

	pi.registerTool({
		...localRead,
		async execute(id, params, signal, onUpdate, ctx) {
			const activeVm = await ensureVm(ctx);
			const workspace = activeBackend!.guestWorkspace;
			const tool = createReadTool(workspace, {
				operations: createGondolinReadOps(activeVm, localCwd, realLocalCwd, workspace),
			});
			return tool.execute(id, params, signal, onUpdate);
		},
	});

	pi.registerTool({
		...localWrite,
		async execute(id, params, signal, onUpdate, ctx) {
			const activeVm = await ensureVm(ctx);
			const workspace = activeBackend!.guestWorkspace;
			const tool = createWriteTool(workspace, {
				operations: createGondolinWriteOps(activeVm, localCwd, realLocalCwd, workspace),
			});
			return tool.execute(id, params, signal, onUpdate);
		},
	});

	pi.registerTool({
		...localEdit,
		async execute(id, params, signal, onUpdate, ctx) {
			const activeVm = await ensureVm(ctx);
			const workspace = activeBackend!.guestWorkspace;
			const tool = createEditTool(workspace, {
				operations: createGondolinEditOps(activeVm, localCwd, realLocalCwd, workspace),
			});
			return tool.execute(id, params, signal, onUpdate);
		},
	});

	pi.registerTool({
		...localBash,
		async execute(id, params, signal, onUpdate, ctx) {
			const activeVm = await ensureVm(ctx);
			const workspace = activeBackend!.guestWorkspace;
			const tool = createBashTool(workspace, {
				exposeSessionEnvironment: false,
				operations: createGondolinBashOps(
					activeVm,
					localCwd,
					realLocalCwd,
					workspace,
					shellPath,
					activeGuestEnv,
				),
			});
			return tool.execute(id, params, signal, onUpdate);
		},
	});

	pi.registerTool({
		...localLs,
		async execute(id, params, signal, onUpdate, ctx) {
			const activeVm = await ensureVm(ctx);
			const workspace = activeBackend!.guestWorkspace;
			const tool = createLsTool(workspace, {
				operations: createGondolinLsOps(activeVm, localCwd, realLocalCwd, workspace),
			});
			return tool.execute(id, params, signal, onUpdate);
		},
	});

	pi.registerTool({
		...localFind,
		async execute(id, params, signal, onUpdate, ctx) {
			const activeVm = await ensureVm(ctx);
			const workspace = activeBackend!.guestWorkspace;
			const tool = createFindTool(workspace, {
				operations: createGondolinFindOps(activeVm, localCwd, realLocalCwd, workspace),
			});
			return tool.execute(id, params, signal, onUpdate);
		},
	});

	pi.registerTool({
		...localGrep,
		async execute(_id, params, signal, _onUpdate, ctx) {
			const activeVm = await ensureVm(ctx);
			const workspace = activeBackend!.guestWorkspace;
			return executeGondolinGrep(activeVm, localCwd, realLocalCwd, workspace, params, signal);
		},
	});

	pi.on("user_bash", async (_event, ctx) => {
		const activeVm = await ensureVm(ctx);
		const workspace = activeBackend!.guestWorkspace;
		return {
			operations: createGondolinBashOps(
				activeVm,
				localCwd,
				realLocalCwd,
				workspace,
				shellPath,
				activeGuestEnv,
			),
		};
	});

	pi.on("before_agent_start", async (event, ctx) => {
		try {
			await ensureVm(ctx);
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			failClosedExit(message);
		}
		const workspace = activeBackend?.guestWorkspace ?? "/workspace";
		if (event.systemPromptOptions) {
			const ghNote = activeGhAuthSource
				? "GitHub CLI (`gh`) and HTTPS `git` are authenticated via host-substituted secret placeholders (never print or attempt to extract real tokens; use `gh repo clone`, `git`, and `gh pr create` normally)."
				: "GitHub token injection is not enabled for this session (public HTTPS clones work; configure `[github]` in `~/.config/sandbox.toml` or `~/.config/sandbox.local.toml` for private clones, pushes, and `gh pr create`).";
			event.systemPromptOptions.sections = {
				...event.systemPromptOptions.sections,
				gondolin_sandbox: [
					`Built-in file and shell tools run inside an isolated Gondolin Linux micro-VM (${activeBackend?.vmm ?? "krun"}, image ${activeBackend?.imagePath ?? "alpine-base"}).`,
					`The project working directory is mounted read-write at ${workspace}.`,
					ghNote,
					"Host files outside the project (~/.kube, ~/.oci, ~/.ssh, ~/.pi, /mnt/c), host environment variables, and non-allowlisted network hosts are unavailable inside the VM.",
				].join("\n"),
			};
		}
	});
}
