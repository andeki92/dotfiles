import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parseToml, type TomlTable } from "./toml.ts";

/**
 * Default-deny egress allowlist: only package registries and common git hosts
 * are reachable over mediated HTTP(S). Internal/private/metadata IP ranges are
 * always blocked by Gondolin (`blockInternalRanges: true`).
 *
 * Configured via `~/.config/sandbox.toml` (+ optional `~/.config/sandbox.local.toml`),
 * with environment variables taking highest precedence for one-off overrides.
 */
export const DEFAULT_ALLOWED_HOSTS: readonly string[] = [
	// Git hosts (HTTPS) & GitHub CLI APIs
	"github.com",
	"api.github.com",
	"uploads.github.com",
	"raw.githubusercontent.com",
	"objects.githubusercontent.com",
	"codeload.github.com",
	"gitlab.com",
	// JavaScript / Node registries
	"registry.npmjs.org",
	// Python registries
	"pypi.org",
	"files.pythonhosted.org",
	// Go module proxy & checksum DB
	"proxy.golang.org",
	"sum.golang.org",
	// Rust crates
	"crates.io",
	"static.crates.io",
	"index.crates.io",
	// JVM registries
	"repo1.maven.org",
	"plugins.gradle.org",
	// Alpine packages (guest OS)
	"dl-cdn.alpinelinux.org",
];

/** Hosts permitted to receive host-substituted GitHub token headers. */
export const GITHUB_SECRET_HOSTS: readonly string[] = [
	"github.com",
	"api.github.com",
	"uploads.github.com",
];

/** Default custom Gondolin image built by scripts/pi-build-image.sh (includes git, gh, kustomize). */
export const DEFAULT_CUSTOM_IMAGE_TAG = "pi-sandbox:latest";

/** Clean guest-only PATH containing only standard Linux paths (no /mnt/c or host paths). */
export const GUEST_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";

export interface SandboxFileConfig {
	vm: {
		image?: string;
		vmm?: string;
		rootfs?: string;
	};
	network: {
		allowedHosts?: string[];
		extraAllowedHosts: string[];
	};
	github: {
		tokenFile?: string;
		useHostAuth?: boolean;
		allowedRepos?: string[];
	};
	git: {
		userName?: string;
		userEmail?: string;
	};
	loadedFiles: string[];
}

export interface EgressPolicy {
	allowedHosts: string[];
	allowedGitHubRepos: string[];
	source: string;
}

export interface GitHubAuthConfig {
	token: string;
	source: "env:PI_SANDBOX_GH_TOKEN" | "file:token_file" | "host:gh-cli";
}

export interface GitIdentity {
	name?: string;
	email?: string;
}

export interface ReadOnlyHostMount {
	hostDir: string;
	realHostDir: string;
	guestDir: string;
}

export interface BackendConfig {
	vmm: "krun" | "qemu";
	rootfsMode: "readonly" | "cow";
	guestWorkspace: string;
	imagePath?: string;
	krunRunnerPath?: string;
	qemuPath?: string;
}

export function expandHomePath(raw: string, homeDir: string = os.homedir()): string {
	if (raw === "~") return homeDir;
	if (raw.startsWith("~/")) return path.join(homeDir, raw.slice(2));
	return path.resolve(raw);
}

function expectTable(val: unknown, label: string): TomlTable | undefined {
	if (val === undefined) return undefined;
	if (typeof val !== "object" || val === null || Array.isArray(val)) {
		throw new Error(`Invalid sandbox config: "${label}" must be a TOML table`);
	}
	return val as TomlTable;
}

function expectOptionalString(val: unknown, label: string): string | undefined {
	if (val === undefined) return undefined;
	if (typeof val !== "string") {
		throw new Error(`Invalid sandbox config: "${label}" must be a string`);
	}
	const trimmed = val.trim();
	return trimmed.length > 0 ? trimmed : undefined;
}

function expectOptionalBoolean(val: unknown, label: string): boolean | undefined {
	if (val === undefined) return undefined;
	if (typeof val !== "boolean") {
		throw new Error(`Invalid sandbox config: "${label}" must be a boolean`);
	}
	return val;
}

function expectOptionalStringArray(val: unknown, label: string): string[] | undefined {
	if (val === undefined) return undefined;
	if (!Array.isArray(val)) {
		throw new Error(`Invalid sandbox config: "${label}" must be an array of strings`);
	}
	const out: string[] = [];
	for (const entry of val) {
		if (typeof entry !== "string") {
			throw new Error(`Invalid sandbox config: every entry in "${label}" must be a string`);
		}
		out.push(entry);
	}
	return out;
}

function mergeTomlIntoConfig(target: SandboxFileConfig, table: TomlTable): void {
	const vm = expectTable(table.vm, "vm");
	if (vm) {
		const image = expectOptionalString(vm.image, "vm.image");
		const vmm = expectOptionalString(vm.vmm, "vm.vmm");
		const rootfs = expectOptionalString(vm.rootfs, "vm.rootfs");
		if (image !== undefined) target.vm.image = image;
		if (vmm !== undefined) target.vm.vmm = vmm;
		if (rootfs !== undefined) target.vm.rootfs = rootfs;
	}

	const network = expectTable(table.network, "network");
	if (network) {
		const allowed = expectOptionalStringArray(network.allowed_hosts, "network.allowed_hosts");
		const extra = expectOptionalStringArray(
			network.extra_allowed_hosts,
			"network.extra_allowed_hosts",
		);
		if (allowed !== undefined) target.network.allowedHosts = allowed;
		if (extra !== undefined) {
			target.network.extraAllowedHosts = [...target.network.extraAllowedHosts, ...extra];
		}
	}

	const github = expectTable(table.github, "github");
	if (github) {
		const tokenFile = expectOptionalString(github.token_file, "github.token_file");
		const useHostAuth = expectOptionalBoolean(github.use_host_auth, "github.use_host_auth");
		const repos = expectOptionalStringArray(github.allowed_repos, "github.allowed_repos");
		if (tokenFile !== undefined) target.github.tokenFile = tokenFile;
		if (useHostAuth !== undefined) target.github.useHostAuth = useHostAuth;
		if (repos !== undefined) target.github.allowedRepos = repos;
	}

	const git = expectTable(table.git, "git");
	if (git) {
		const userName = expectOptionalString(git.user_name, "git.user_name");
		const userEmail = expectOptionalString(git.user_email, "git.user_email");
		if (userName !== undefined) target.git.userName = userName;
		if (userEmail !== undefined) target.git.userEmail = userEmail;
	}
}

/**
 * Loads `~/.config/sandbox.toml` and merges optional `~/.config/sandbox.local.toml`
 * on top (or a custom path via `PI_SANDBOX_CONFIG` / explicit `configPath`).
 */
export function loadSandboxConfig(
	env: NodeJS.ProcessEnv = process.env,
	configPath?: string,
	localConfigPath?: string,
): SandboxFileConfig {
	const xdgConfig = env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
	const basePath =
		configPath ??
		(env.PI_SANDBOX_CONFIG?.trim()
			? expandHomePath(env.PI_SANDBOX_CONFIG.trim())
			: path.join(xdgConfig, "sandbox.toml"));

	const resolvedLocalPath =
		localConfigPath ??
		(configPath || env.PI_SANDBOX_CONFIG?.trim()
			? path.join(
					path.dirname(basePath),
					path.basename(basePath).replace(/\.toml$/i, ".local.toml"),
				)
			: path.join(xdgConfig, "sandbox.local.toml"));

	const config: SandboxFileConfig = {
		vm: {},
		network: { extraAllowedHosts: [] },
		github: {},
		git: {},
		loadedFiles: [],
	};

	for (const candidate of [basePath, resolvedLocalPath]) {
		if (!candidate || !fs.existsSync(candidate)) continue;
		const parsed = parseToml(fs.readFileSync(candidate, "utf8"));
		mergeTomlIntoConfig(config, parsed);
		config.loadedFiles.push(candidate);
	}

	return config;
}

function parseCsvList(raw: string | undefined): string[] | undefined {
	if (raw === undefined) return undefined;
	const trimmed = raw.trim();
	if (!trimmed) return [];
	return trimmed.split(",").map((entry) => entry.trim());
}

function isSafeHostPattern(pattern: string): boolean {
	return (
		pattern.length > 0 &&
		pattern !== "*" &&
		!/\s/.test(pattern) &&
		!pattern.includes("://") &&
		!pattern.includes("/")
	);
}

function isSafeRepoPattern(pattern: string): boolean {
	return /^[a-z0-9_.-]+\/[a-z0-9_.*-]+$/i.test(pattern);
}

/**
 * Validates and deduplicates host or repository restriction patterns.
 * Fails closed (throws) on any invalid entry so a malformed restriction can
 * NEVER silently collapse to `[]` and disable enforcement.
 */
function validateAndDedupe(
	values: readonly string[],
	validate: (v: string) => boolean,
	label: string,
): string[] {
	const seen = new Set<string>();
	const out: string[] = [];
	for (const raw of values) {
		const normalized = raw.trim().toLowerCase();
		if (!validate(normalized)) {
			throw new Error(
				`Invalid ${label} entry ${JSON.stringify(raw)}. Fix your sandbox.toml or environment override (fail-closed).`,
			);
		}
		if (!seen.has(normalized)) {
			seen.add(normalized);
			out.push(normalized);
		}
	}
	return out;
}

export function loadEgressPolicy(
	env: NodeJS.ProcessEnv = process.env,
	sandboxConfig?: SandboxFileConfig,
): EgressPolicy {
	const cfg = sandboxConfig ?? loadSandboxConfig(env);

	let hosts = [...DEFAULT_ALLOWED_HOSTS];
	let allowedGitHubRepos: string[] = [];
	let source = cfg.loadedFiles.length > 0 ? cfg.loadedFiles.join(" + ") : "default";

	if (cfg.network.allowedHosts !== undefined) {
		hosts = [...cfg.network.allowedHosts];
	}
	if (cfg.network.extraAllowedHosts.length > 0) {
		hosts = [...hosts, ...cfg.network.extraAllowedHosts];
	}
	if (cfg.github.allowedRepos !== undefined) {
		allowedGitHubRepos = [...cfg.github.allowedRepos];
	}

	const envReplace = parseCsvList(env.PI_SANDBOX_ALLOWED_HOSTS);
	if (envReplace !== undefined && envReplace.length > 0) {
		hosts = envReplace;
		source = "env:PI_SANDBOX_ALLOWED_HOSTS";
	}

	const envExtra = parseCsvList(env.PI_SANDBOX_EXTRA_ALLOWED_HOSTS);
	if (envExtra !== undefined && envExtra.length > 0) {
		hosts = [...hosts, ...envExtra];
		source = `${source}+env:PI_SANDBOX_EXTRA_ALLOWED_HOSTS`;
	}

	const envRepos = parseCsvList(env.PI_SANDBOX_GH_ALLOWED_REPOS);
	if (envRepos !== undefined) {
		allowedGitHubRepos = envRepos;
	}

	return {
		allowedHosts: validateAndDedupe(hosts, isSafeHostPattern, "allowed_hosts"),
		allowedGitHubRepos: validateAndDedupe(
			allowedGitHubRepos,
			isSafeRepoPattern,
			'github.allowed_repos (expected "owner/repo" or "owner/prefix-*")',
		),
		source,
	};
}

/**
 * Resolves a GitHub token strictly on the host for Gondolin's placeholder
 * substitution (NEVER passed directly into the guest VM).
 */
export function resolveGitHubAuth(
	env: NodeJS.ProcessEnv = process.env,
	sandboxConfig?: SandboxFileConfig,
	hostGhTokenFetcher?: () => string | null,
): GitHubAuthConfig | null {
	const cfg = sandboxConfig ?? loadSandboxConfig(env);

	const envToken = env.PI_SANDBOX_GH_TOKEN?.trim();
	if (envToken) {
		return { token: envToken, source: "env:PI_SANDBOX_GH_TOKEN" };
	}

	const xdgConfig = env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
	const tokenFileSetting = cfg.github.tokenFile ?? path.join(xdgConfig, "sandbox-gh-token");
	const resolvedTokenFile = expandHomePath(tokenFileSetting);

	if (fs.existsSync(resolvedTokenFile)) {
		const stat = fs.statSync(resolvedTokenFile);
		if (process.platform !== "win32" && (stat.mode & 0o077) !== 0) {
			throw new Error(
				`Refusing to read "${resolvedTokenFile}": permissions are too open (${(stat.mode & 0o777).toString(8)}). Fix with: chmod 600 "${resolvedTokenFile}"`,
			);
		}
		const fileToken = fs.readFileSync(resolvedTokenFile, "utf8").trim();
		if (fileToken) {
			return { token: fileToken, source: "file:token_file" };
		}
	}

	const useHostAuth =
		env.PI_SANDBOX_GH_USE_HOST_AUTH !== undefined
			? env.PI_SANDBOX_GH_USE_HOST_AUTH === "1"
			: Boolean(cfg.github.useHostAuth);

	if (useHostAuth) {
		const fetched = hostGhTokenFetcher
			? hostGhTokenFetcher()
			: (() => {
					try {
						return execFileSync("gh", ["auth", "token"], {
							encoding: "utf8",
							stdio: ["ignore", "pipe", "ignore"],
							timeout: 5000,
						}).trim();
					} catch {
						return null;
					}
				})();
		if (fetched) {
			return { token: fetched, source: "host:gh-cli" };
		}
		throw new Error(
			"GitHub host auth is enabled (`use_host_auth = true` / `PI_SANDBOX_GH_USE_HOST_AUTH=1`), but `gh auth token` failed on the host. Run `gh auth login` or configure `token_file` / `PI_SANDBOX_GH_TOKEN`.",
		);
	}

	return null;
}

export function isGitHubRepoAllowed(repoSlug: string, allowedPatterns: readonly string[]): boolean {
	if (allowedPatterns.length === 0) return true;
	const normalized = repoSlug.trim().toLowerCase().replace(/\.git$/, "");
	for (const pattern of allowedPatterns) {
		const p = pattern.trim().toLowerCase().replace(/\.git$/, "");
		if (p === normalized) return true;
		if (p.includes("*")) {
			const regex = new RegExp(
				`^${p.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replaceAll("*", "[^/]*")}$`,
			);
			if (regex.test(normalized)) return true;
		}
	}
	return false;
}

/**
 * Host-side check for GitHub HTTP/Git/REST requests when `allowed_repos` is set.
 * Blocks `/graphql` unconditionally under `allowed_repos` because arbitrary GraphQL
 * documents (e.g. inline `repository(owner: ..., name: ...)` arguments or aliases)
 * cannot be safely repo-scoped from request variables alone.
 */
export function evaluateGitHubRepoAccess(
	urlString: string,
	allowedRepos: readonly string[],
): { allowed: boolean; reason?: string } {
	if (allowedRepos.length === 0) return { allowed: true };

	let url: URL;
	try {
		url = new URL(urlString);
	} catch {
		return { allowed: false, reason: "Invalid request URL" };
	}

	const host = url.hostname.toLowerCase();
	const segments = url.pathname.split("/").filter(Boolean);

	if (host === "github.com") {
		if (segments.length >= 2) {
			const owner = segments[0];
			const repo = segments[1].replace(/\.git$/i, "");
			const nonRepoPrefixes = new Set(["login", "settings", "notifications", "features", "about"]);
			if (!nonRepoPrefixes.has(owner.toLowerCase())) {
				const slug = `${owner}/${repo}`;
				if (!isGitHubRepoAllowed(slug, allowedRepos)) {
					return {
						allowed: false,
						reason: `GitHub repository "${slug}" is not in allowed_repos`,
					};
				}
			}
		}
		return { allowed: true };
	}

	if (host === "api.github.com") {
		if (segments[0]?.toLowerCase() === "graphql") {
			return {
				allowed: false,
				reason:
					"GitHub GraphQL (/graphql) is blocked while allowed_repos is set because GraphQL queries can target arbitrary repos via inline arguments. Use git HTTPS / REST API (/repos/<owner>/<repo>/...) or a fine-grained repository-scoped PAT with allowed_repos = [].",
			};
		}
		if (segments[0]?.toLowerCase() === "repos" && segments.length >= 3) {
			const slug = `${segments[1]}/${segments[2].replace(/\.git$/i, "")}`;
			if (!isGitHubRepoAllowed(slug, allowedRepos)) {
				return {
					allowed: false,
					reason: `GitHub API repository "${slug}" is not in allowed_repos`,
				};
			}
		}
		return { allowed: true };
	}

	return { allowed: true };
}

export function resolveHostGitIdentity(
	localCwd: string,
	env: NodeJS.ProcessEnv = process.env,
	sandboxConfig?: SandboxFileConfig,
): GitIdentity {
	const cfg = sandboxConfig ?? loadSandboxConfig(env);

	const name =
		env.PI_SANDBOX_GIT_USER_NAME?.trim() ||
		cfg.git.userName ||
		(() => {
			try {
				return execFileSync("git", ["-C", localCwd, "config", "--get", "user.name"], {
					encoding: "utf8",
					stdio: ["ignore", "pipe", "ignore"],
					timeout: 2000,
				}).trim();
			} catch {
				return "";
			}
		})();

	const email =
		env.PI_SANDBOX_GIT_USER_EMAIL?.trim() ||
		cfg.git.userEmail ||
		(() => {
			try {
				return execFileSync("git", ["-C", localCwd, "config", "--get", "user.email"], {
					encoding: "utf8",
					stdio: ["ignore", "pipe", "ignore"],
					timeout: 2000,
				}).trim();
			} catch {
				return "";
			}
		})();

	return {
		...(name ? { name } : {}),
		...(email ? { email } : {}),
	};
}

function sanitizeTerm(value: string | undefined): string {
	if (!value) return "xterm-256color";
	return /^[A-Za-z0-9_.-]{1,64}$/.test(value) ? value : "xterm-256color";
}

export function buildGuestEnv(
	hostEnv: NodeJS.ProcessEnv = process.env,
	hookEnv: Record<string, string> = {},
	gitIdentity: GitIdentity = {},
): Record<string, string> {
	const env: Record<string, string> = {
		HOME: "/root",
		USER: "root",
		LOGNAME: "root",
		PATH: GUEST_PATH,
		TERM: sanitizeTerm(hostEnv.TERM),
		LANG: "C.UTF-8",
		LC_ALL: "C.UTF-8",
		GIT_TERMINAL_PROMPT: "0",
		GH_PROMPT_DISABLED: "1",
		GIT_SSL_CAINFO: "/run/gondolin/ca-certificates.crt",
	};

	if (hostEnv.COLORTERM === "truecolor" || hostEnv.COLORTERM === "24bit") {
		env.COLORTERM = hostEnv.COLORTERM;
	}
	if (hostEnv.NO_COLOR) {
		env.NO_COLOR = "1";
	}
	if (hostEnv.CI) {
		env.CI = "1";
	}

	if (gitIdentity.name) {
		env.GIT_AUTHOR_NAME = gitIdentity.name;
		env.GIT_COMMITTER_NAME = gitIdentity.name;
	}
	if (gitIdentity.email) {
		env.GIT_AUTHOR_EMAIL = gitIdentity.email;
		env.GIT_COMMITTER_EMAIL = gitIdentity.email;
	}

	for (const [key, value] of Object.entries(hookEnv)) {
		if (typeof value === "string") {
			env[key] = value;
		}
	}

	if (typeof hookEnv.GH_TOKEN === "string" && !env.GITHUB_TOKEN) {
		env.GITHUB_TOKEN = hookEnv.GH_TOKEN;
	}

	return env;
}

export function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

export function toPosix(value: string): string {
	return value.split(path.sep).join(path.posix.sep);
}

export function isInsideHostPath(root: string, candidate: string): boolean {
	const relativePath = path.relative(root, candidate);
	return relativePath === "" || (!relativePath.startsWith("..") && !path.isAbsolute(relativePath));
}

export function assertSafeWorkspaceDir(
	localCwd: string,
	homeDir: string = os.homedir(),
): void {
	const resolvedCwd = path.resolve(localCwd);
	const resolvedHome = path.resolve(homeDir);

	if (resolvedCwd === "/" || resolvedCwd === resolvedHome) {
		throw new Error(
			`Refusing to mount "${resolvedCwd}" into the Gondolin sandbox because it would expose host credentials (~/.kube, ~/.oci, ~/.ssh, ~/.pi). cd into a project directory first.`,
		);
	}

	if (resolvedCwd === "/mnt" || resolvedCwd.startsWith("/mnt/")) {
		throw new Error(
			`Refusing to mount Windows/host drive path "${resolvedCwd}" into the Gondolin sandbox.`,
		);
	}

	const sensitiveDirs = [
		path.join(resolvedHome, ".kube"),
		path.join(resolvedHome, ".oci"),
		path.join(resolvedHome, ".ssh"),
		path.join(resolvedHome, ".pi"),
	];

	for (const sensitive of sensitiveDirs) {
		if (isInsideHostPath(resolvedCwd, sensitive) || isInsideHostPath(sensitive, resolvedCwd)) {
			throw new Error(
				`Refusing to mount "${resolvedCwd}" into the Gondolin sandbox because it overlaps sensitive credential path "${sensitive}".`,
			);
		}
	}
}

/**
 * Checks whether a trusted skill directory is safe to expose read-only inside
 * the VM (never mounts /, $HOME, /mnt, ~/.kube, ~/.oci, ~/.ssh, or ~/.pi/agent root).
 */
export function isSafeReadOnlySkillDir(
	skillDir: string,
	homeDir: string = os.homedir(),
): boolean {
	const resolved = path.resolve(skillDir);
	const resolvedHome = path.resolve(homeDir);
	if (resolved === "/" || resolved === resolvedHome) return false;
	if (resolved === "/mnt" || resolved.startsWith("/mnt/")) return false;

	const forbiddenExactOrSub = [
		path.join(resolvedHome, ".kube"),
		path.join(resolvedHome, ".oci"),
		path.join(resolvedHome, ".ssh"),
	];
	for (const dir of forbiddenExactOrSub) {
		if (isInsideHostPath(dir, resolved) || isInsideHostPath(resolved, dir)) return false;
	}

	// Allow skill subdirectories under ~/.pi/agent/skills/... or ~/.pi/agent/npm/...,
	// but NEVER ~/.pi or ~/.pi/agent root (which contain auth.json and sessions).
	const piRoot = path.join(resolvedHome, ".pi");
	const piAgentRoot = path.join(piRoot, "agent");
	if (resolved === piRoot || resolved === piAgentRoot) return false;
	if (isInsideHostPath(resolved, piAgentRoot)) return false;

	return true;
}

/**
 * Builds deduplicated read-only guest mounts for trusted skill directories that
 * live outside the project workspace so the model can `read` SKILL.md and
 * supporting files through the sandbox without any host-read fallback.
 */
export function buildTrustedSkillMounts(
	skillFilePaths: readonly string[],
	localCwd: string,
	realLocalCwd: string,
	homeDir: string = os.homedir(),
): ReadOnlyHostMount[] {
	const mounts: ReadOnlyHostMount[] = [];
	const seenRealDirs = new Set<string>();

	for (const rawFilePath of skillFilePaths) {
		if (!rawFilePath) continue;
		const hostDir = path.resolve(path.dirname(rawFilePath));
		let realHostDir: string;
		try {
			realHostDir = fs.realpathSync(hostDir);
			if (!fs.statSync(realHostDir).isDirectory()) continue;
		} catch {
			continue;
		}

		// Skip skills already inside the mounted project workspace.
		if (
			isInsideHostPath(localCwd, hostDir) ||
			isInsideHostPath(realLocalCwd, realHostDir)
		) {
			continue;
		}

		if (
			!isSafeReadOnlySkillDir(hostDir, homeDir) ||
			!isSafeReadOnlySkillDir(realHostDir, homeDir)
		) {
			continue;
		}

		if (seenRealDirs.has(realHostDir)) continue;
		seenRealDirs.add(realHostDir);

		const safeBase =
			path
				.basename(realHostDir)
				.replace(/[^A-Za-z0-9_.-]/g, "_")
				.slice(0, 48) || "skill";
		const guestDir = `/tmp/pi-skills/${mounts.length}-${safeBase}`;
		mounts.push({ hostDir, realHostDir, guestDir });
	}

	return mounts;
}

export function toGuestPath(
	localCwd: string,
	guestWorkspace: string,
	inputPath: string,
	realLocalCwd?: string,
	extraMounts: readonly ReadOnlyHostMount[] = [],
): string {
	const trimmed = stripAtPrefix(inputPath.trim());
	if (!trimmed) return guestWorkspace;

	if (trimmed === "~") return "/root";
	if (trimmed.startsWith("~/")) {
		return path.posix.resolve("/root", toPosix(trimmed.slice(2)));
	}

	if (path.isAbsolute(trimmed)) {
		for (const base of realLocalCwd && realLocalCwd !== localCwd ? [localCwd, realLocalCwd] : [localCwd]) {
			if (isInsideHostPath(base, trimmed)) {
				const rel = path.relative(base, trimmed);
				return rel ? path.posix.join(guestWorkspace, toPosix(rel)) : guestWorkspace;
			}
		}

		// Translate paths inside explicitly mounted read-only trusted skill directories.
		for (const mount of extraMounts) {
			for (const base of mount.realHostDir !== mount.hostDir
				? [mount.hostDir, mount.realHostDir]
				: [mount.hostDir]) {
				if (isInsideHostPath(base, trimmed)) {
					const rel = path.relative(base, trimmed);
					return rel ? path.posix.join(mount.guestDir, toPosix(rel)) : mount.guestDir;
				}
			}
		}

		// Any other absolute path resolves inside the guest root, where host
		// ~/.kube, ~/.oci, ~/.ssh, and /mnt/c do not exist.
		return path.posix.resolve("/", toPosix(trimmed));
	}

	return path.posix.resolve(guestWorkspace, toPosix(trimmed));
}

export function findExecutableOnPath(
	name: string,
	env: NodeJS.ProcessEnv = process.env,
): string | undefined {
	const pathValue = env.PATH ?? "";
	for (const dir of pathValue.split(path.delimiter)) {
		if (!dir) continue;
		const candidate = path.join(dir, name);
		try {
			fs.accessSync(candidate, fs.constants.X_OK);
			const stat = fs.statSync(candidate);
			if (stat.isFile()) return candidate;
		} catch {
			// continue searching
		}
	}
	return undefined;
}

function findInstalledKrunRunner(packageRoot: string, env: NodeJS.ProcessEnv): string | undefined {
	const explicit = env.GONDOLIN_KRUN_RUNNER?.trim();
	if (explicit) {
		try {
			fs.accessSync(explicit, fs.constants.X_OK);
			return explicit;
		} catch {
			throw new Error(
				`GONDOLIN_KRUN_RUNNER is set to "${explicit}" but that file is missing or not executable.`,
			);
		}
	}

	const platformKey = `${process.platform}-${process.arch}`;
	const pkgRunner = path.join(
		packageRoot,
		"node_modules",
		`@earendil-works/gondolin-krun-runner-${platformKey}`,
		"bin",
		"gondolin-krun-runner",
	);
	try {
		fs.accessSync(pkgRunner, fs.constants.X_OK);
		return pkgRunner;
	} catch {
		// fall through to PATH lookup
	}

	return findExecutableOnPath("gondolin-krun-runner", env);
}

export function resolveBackendConfig(
	packageRoot: string,
	env: NodeJS.ProcessEnv = process.env,
	hasCustomImage?: (imageRef: string) => boolean,
	sandboxConfig?: SandboxFileConfig,
): BackendConfig {
	const cfg = sandboxConfig ?? loadSandboxConfig(env);

	const requestedVmm = (env.PI_SANDBOX_VMM?.trim() || cfg.vm.vmm || "").toLowerCase();
	if (requestedVmm && requestedVmm !== "krun" && requestedVmm !== "qemu") {
		throw new Error(`Invalid sandbox vmm "${requestedVmm}". Expected "krun" or "qemu".`);
	}

	const requestedRootfs = (env.PI_SANDBOX_ROOTFS?.trim() || cfg.vm.rootfs || "").toLowerCase();
	if (requestedRootfs && requestedRootfs !== "readonly" && requestedRootfs !== "cow") {
		throw new Error(`Invalid sandbox rootfs "${requestedRootfs}". Expected "readonly" or "cow".`);
	}

	const allowEmulation = env.PI_SANDBOX_ALLOW_EMULATION === "1";

	if (process.platform === "linux") {
		const kvmDevice = env.PI_SANDBOX_KVM_DEVICE || "/dev/kvm";
		try {
			fs.accessSync(kvmDevice, fs.constants.R_OK | fs.constants.W_OK);
		} catch {
			if (!allowEmulation) {
				let hint = `On WSL2/Linux, ensure nested virtualization is enabled and run: sudo usermod -aG kvm "$USER" (then restart herdr / start a fresh login).`;
				try {
					const user = env.USER || os.userInfo().username;
					const dbGroups = execFileSync("id", ["-nG", user], {
						encoding: "utf8",
						stdio: ["ignore", "pipe", "ignore"],
						timeout: 2000,
					});
					if (` ${dbGroups.trim()} `.includes(" kvm ")) {
						hint =
							"Your user IS already in the kvm group, but this shell inherited old groups from its parent session (e.g. a long-running herdr server). From a fresh WSL shell where `id` includes kvm, run: herdr server stop && herdr";
					}
				} catch {
					// keep default hint
				}
				throw new Error(
					`Hardware virtualization required: "${kvmDevice}" is missing or not readable/writable. ${hint}`,
				);
			}
		}
	}

	const qemuArchBinary = process.arch === "arm64" ? "qemu-system-aarch64" : "qemu-system-x86_64";
	const qemuImg = findExecutableOnPath("qemu-img", env);

	const defaultVmm: "krun" | "qemu" =
		(process.platform === "linux" && process.arch === "x64") ||
		(process.platform === "darwin" && process.arch === "arm64")
			? "krun"
			: "qemu";

	const vmm: "krun" | "qemu" = (requestedVmm as "krun" | "qemu" | "") || defaultVmm;

	let krunRunnerPath: string | undefined;
	let qemuPath: string | undefined;

	if (vmm === "krun") {
		krunRunnerPath = findInstalledKrunRunner(packageRoot, env);
		if (!krunRunnerPath) {
			throw new Error(
				`Gondolin krun runner binary not found. Run scripts/pi-bootstrap.sh (which installs optional platform dependencies) or set vmm = "qemu" with ${qemuArchBinary} installed.`,
			);
		}
	} else {
		const explicitQemu = env.PI_SANDBOX_QEMU_PATH?.trim();
		if (explicitQemu) {
			try {
				fs.accessSync(explicitQemu, fs.constants.X_OK);
				qemuPath = explicitQemu;
			} catch {
				throw new Error(
					`PI_SANDBOX_QEMU_PATH="${explicitQemu}" is missing or not executable.`,
				);
			}
		} else {
			qemuPath = findExecutableOnPath(qemuArchBinary, env);
			if (!qemuPath) {
				throw new Error(
					`QEMU binary "${qemuArchBinary}" not found on PATH. Install qemu-system-x86 or use vmm = "krun".`,
				);
			}
		}
	}

	const envImage = env.PI_SANDBOX_IMAGE?.trim();
	const configuredImage = envImage || cfg.vm.image || DEFAULT_CUSTOM_IMAGE_TAG;

	let imagePath: string | undefined;
	let hasBakedWorkspaceMount = false;
	if (envImage) {
		imagePath = envImage;
		hasBakedWorkspaceMount = envImage.startsWith("pi-sandbox");
	} else if (hasCustomImage?.(configuredImage)) {
		imagePath = configuredImage;
		hasBakedWorkspaceMount = configuredImage.startsWith("pi-sandbox");
	}

	let rootfsMode: "readonly" | "cow";
	if (requestedRootfs) {
		if (requestedRootfs === "cow" && !qemuImg) {
			throw new Error(
				`rootfs = "cow" requires "qemu-img" on PATH (install qemu-utils or qemu, or use rootfs = "readonly").`,
			);
		}
		rootfsMode = requestedRootfs as "readonly" | "cow";
	} else {
		rootfsMode = hasBakedWorkspaceMount || !qemuImg ? "readonly" : "cow";
	}

	const guestWorkspace =
		rootfsMode === "cow" || hasBakedWorkspaceMount ? "/workspace" : "/tmp/workspace";

	return {
		vmm,
		rootfsMode,
		guestWorkspace,
		imagePath,
		krunRunnerPath,
		qemuPath,
	};
}
