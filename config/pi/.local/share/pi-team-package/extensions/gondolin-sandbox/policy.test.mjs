import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
	assertSafeWorkspaceDir,
	buildGuestEnv,
	DEFAULT_ALLOWED_HOSTS,
	evaluateGitHubRepoAccess,
	GUEST_PATH,
	isGitHubRepoAllowed,
	loadEgressPolicy,
	loadSandboxConfig,
	resolveBackendConfig,
	resolveGitHubAuth,
	toGuestPath,
} from "./policy.ts";
import { parseToml } from "./toml.ts";

test("parseToml parses sections, comments, booleans, strings, and multiline arrays", () => {
	const parsed = parseToml(`
# top comment
[vm]
image = "pi-sandbox:latest" # inline comment
vmm = 'krun'

[network]
extra_allowed_hosts = [
  "git.internal.example",
  "artifactory.internal.example", # trailing comma
]

[github]
token_file = "~/.config/sandbox-gh-token"
use_host_auth = true
allowed_repos = ["myorg/repo-a", "myorg/gitops-*"]
`);

	assert.equal(parsed.vm.image, "pi-sandbox:latest");
	assert.equal(parsed.vm.vmm, "krun");
	assert.deepEqual(parsed.network.extra_allowed_hosts, [
		"git.internal.example",
		"artifactory.internal.example",
	]);
	assert.equal(parsed.github.use_host_auth, true);
	assert.deepEqual(parsed.github.allowed_repos, ["myorg/repo-a", "myorg/gitops-*"]);
});

test("loadSandboxConfig merges sandbox.toml with sandbox.local.toml overrides", () => {
	const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pi-sandbox-cfg-"));
	const baseFile = path.join(tmp, "sandbox.toml");
	const localFile = path.join(tmp, "sandbox.local.toml");
	try {
		fs.writeFileSync(
			baseFile,
			`
[vm]
image = "pi-sandbox:latest"

[network]
extra_allowed_hosts = ["registry.example.com"]

[github]
use_host_auth = false
allowed_repos = []
`,
		);
		fs.writeFileSync(
			localFile,
			`
[network]
extra_allowed_hosts = ["artifacts.internal"]

[github]
use_host_auth = true
allowed_repos = ["myorg/my-repo"]

[git]
user_name = "Local Dev"
`,
		);

		const cfg = loadSandboxConfig({}, baseFile);
		assert.equal(cfg.loadedFiles.length, 2);
		assert.equal(cfg.vm.image, "pi-sandbox:latest");
		assert.deepEqual(cfg.network.extraAllowedHosts, [
			"registry.example.com",
			"artifacts.internal",
		]);
		assert.equal(cfg.github.useHostAuth, true);
		assert.deepEqual(cfg.github.allowedRepos, ["myorg/my-repo"]);
		assert.equal(cfg.git.userName, "Local Dev");
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});

test("buildGuestEnv scrubs OCI, KUBECONFIG, cloud, SSH, host git tokens, and passes only placeholder GH_TOKEN", () => {
	const env = buildGuestEnv(
		{
			OCI_CLI_PROFILE: "prod",
			OCI_TENANCY: "ocid1.tenancy.oc1..secret",
			KUBECONFIG: "/home/dev/.kube/config",
			AWS_SECRET_ACCESS_KEY: "super-secret",
			SSH_AUTH_SOCK: "/tmp/ssh-agent.sock",
			GITHUB_TOKEN: "ghp_host_real_secret",
			GH_TOKEN: "ghp_host_real_secret_2",
			PI_SANDBOX_GH_TOKEN: "ghp_scoped_real_secret",
			GIT_CONFIG_VALUE_0: "!glab auth git-credential",
			ANTHROPIC_API_KEY: "sk-ant-secret",
			WSL_DISTRO_NAME: "Ubuntu-26.04",
			PATH: "/mnt/c/WINDOWS/System32:/usr/bin",
			TERM: "xterm-256color",
			COLORTERM: "truecolor",
			NO_COLOR: "1",
		},
		{ GH_TOKEN: "ghp_placeholder_only_not_real_token_123456" },
		{ name: "Dev Bot", email: "dev@example.com" },
	);

	assert.equal(env.HOME, "/root");
	assert.equal(env.PATH, GUEST_PATH);
	assert.equal(env.TERM, "xterm-256color");
	assert.equal(env.COLORTERM, "truecolor");
	assert.equal(env.NO_COLOR, "1");
	assert.equal(env.GIT_TERMINAL_PROMPT, "0");
	assert.equal(env.GH_PROMPT_DISABLED, "1");
	assert.equal(env.GIT_SSL_CAINFO, "/run/gondolin/ca-certificates.crt");
	assert.equal(env.GH_TOKEN, "ghp_placeholder_only_not_real_token_123456");
	assert.equal(env.GITHUB_TOKEN, "ghp_placeholder_only_not_real_token_123456");
	assert.equal(env.GIT_AUTHOR_NAME, "Dev Bot");
	assert.equal(env.GIT_AUTHOR_EMAIL, "dev@example.com");

	for (const forbidden of [
		"OCI_CLI_PROFILE",
		"OCI_TENANCY",
		"KUBECONFIG",
		"AWS_SECRET_ACCESS_KEY",
		"SSH_AUTH_SOCK",
		"PI_SANDBOX_GH_TOKEN",
		"GIT_CONFIG_VALUE_0",
		"ANTHROPIC_API_KEY",
		"WSL_DISTRO_NAME",
	]) {
		assert.equal(env[forbidden], undefined, `expected ${forbidden} to be stripped`);
	}
});

test("toGuestPath maps workspace files into guestWorkspace and keeps external paths in guest root", () => {
	assert.equal(toGuestPath("/work/repo", "/workspace", "src/app.ts"), "/workspace/src/app.ts");
	assert.equal(toGuestPath("/work/repo", "/workspace", "/work/repo/README.md"), "/workspace/README.md");
	assert.equal(toGuestPath("/work/repo", "/workspace", "~/.kube/config"), "/root/.kube/config");
	assert.equal(toGuestPath("/work/repo", "/workspace", "/home/user/.oci/config"), "/home/user/.oci/config");
	assert.equal(toGuestPath("/work/repo", "/workspace", "/mnt/c/Windows"), "/mnt/c/Windows");
});

test("assertSafeWorkspaceDir refuses /, HOME, /mnt/c, and credential dirs", () => {
	assert.throws(() => assertSafeWorkspaceDir("/", "/home/dev"));
	assert.throws(() => assertSafeWorkspaceDir("/home/dev", "/home/dev"));
	assert.throws(() => assertSafeWorkspaceDir("/home/dev/.kube", "/home/dev"));
	assert.throws(() => assertSafeWorkspaceDir("/home/dev/.oci", "/home/dev"));
	assert.throws(() => assertSafeWorkspaceDir("/home/dev/.ssh", "/home/dev"));
	assert.throws(() => assertSafeWorkspaceDir("/home/dev/.pi/agent", "/home/dev"));
	assert.throws(() => assertSafeWorkspaceDir("/mnt/c/Users/dev", "/home/dev"));
	assert.doesNotThrow(() => assertSafeWorkspaceDir("/home/dev/projects/app", "/home/dev"));
});

test("loadEgressPolicy reads sandbox.toml, enforces default-deny allowlist, and supports env overrides", () => {
	const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pi-egress-test-"));
	const cfgPath = path.join(tmp, "sandbox.toml");
	try {
		const emptyCfg = loadSandboxConfig({}, path.join(tmp, "missing.toml"));
		const def = loadEgressPolicy({}, emptyCfg);
		assert.deepEqual(def.allowedHosts, [...DEFAULT_ALLOWED_HOSTS]);
		assert.ok(def.allowedHosts.includes("registry.npmjs.org"));
		assert.ok(def.allowedHosts.includes("uploads.github.com"));
		assert.ok(!def.allowedHosts.includes("example.com"));
		assert.deepEqual(def.allowedGitHubRepos, []);

		fs.writeFileSync(
			cfgPath,
			`
[network]
extra_allowed_hosts = ["charts.example.org"]

[github]
allowed_repos = ["myorg/app-one"]
`,
		);
		const fromToml = loadEgressPolicy({}, loadSandboxConfig({}, cfgPath));
		assert.ok(fromToml.allowedHosts.includes("charts.example.org"));
		assert.deepEqual(fromToml.allowedGitHubRepos, ["myorg/app-one"]);

		const override = loadEgressPolicy(
			{
				PI_SANDBOX_ALLOWED_HOSTS: "registry.npmjs.org, *, github.com",
				PI_SANDBOX_GH_ALLOWED_REPOS: "myorg/app-two, myorg/gitops-*, invalid",
			},
			loadSandboxConfig({}, cfgPath),
		);
		assert.deepEqual(override.allowedHosts, ["registry.npmjs.org", "github.com"]);
		assert.deepEqual(override.allowedGitHubRepos, ["myorg/app-two", "myorg/gitops-*"]);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});

test("resolveGitHubAuth reads token_file / use_host_auth from sandbox.toml and enforces 0600 permissions", () => {
	const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pi-ghauth-test-"));
	const tokenFile = path.join(tmp, "sandbox-gh-token");
	const baseCfg = {
		vm: {},
		network: { extraAllowedHosts: [] },
		github: { tokenFile, useHostAuth: false },
		git: {},
		loadedFiles: [],
	};
	try {
		// Default: returns null (never silently reads host gh auth)
		assert.equal(resolveGitHubAuth({}, baseCfg, () => "should-not-be-called"), null);

		// Env var wins
		const fromEnv = resolveGitHubAuth({ PI_SANDBOX_GH_TOKEN: "tok-env" }, baseCfg);
		assert.deepEqual(fromEnv, { token: "tok-env", source: "env:PI_SANDBOX_GH_TOKEN" });

		// File with overly broad permissions is rejected
		fs.writeFileSync(tokenFile, "tok-file\n", { mode: 0o644 });
		if (process.platform !== "win32") {
			assert.throws(() => resolveGitHubAuth({}, baseCfg), /permissions are too open/);
		}

		// File with 0600 succeeds
		fs.chmodSync(tokenFile, 0o600);
		assert.deepEqual(resolveGitHubAuth({}, baseCfg), {
			token: "tok-file",
			source: "file:token_file",
		});

		// Opt-in host gh auth via sandbox.toml works when token file absent
		fs.unlinkSync(tokenFile);
		assert.deepEqual(
			resolveGitHubAuth(
				{},
				{ ...baseCfg, github: { tokenFile, useHostAuth: true } },
				() => "tok-host",
			),
			{ token: "tok-host", source: "host:gh-cli" },
		);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});

test("evaluateGitHubRepoAccess enforces allowed_repos on git, REST API, and GraphQL variables", () => {
	const allowed = ["myorg/platform-gitops", "myorg/service-*"];
	assert.equal(isGitHubRepoAllowed("myorg/platform-gitops", allowed), true);
	assert.equal(isGitHubRepoAllowed("myorg/service-payments.git", allowed), true);
	assert.equal(isGitHubRepoAllowed("otherorg/secret-repo", allowed), false);

	assert.equal(
		evaluateGitHubRepoAccess("https://github.com/myorg/platform-gitops.git/info/refs", allowed).allowed,
		true,
	);
	assert.equal(
		evaluateGitHubRepoAccess("https://github.com/otherorg/secret.git/git-receive-pack", allowed).allowed,
		false,
	);
	assert.equal(
		evaluateGitHubRepoAccess("https://api.github.com/repos/myorg/service-auth/pulls", allowed).allowed,
		true,
	);
	assert.equal(
		evaluateGitHubRepoAccess("https://api.github.com/repos/otherorg/secret/pulls", allowed).allowed,
		false,
	);
	assert.equal(
		evaluateGitHubRepoAccess("https://api.github.com/user", allowed).allowed,
		true,
	);
	assert.equal(
		evaluateGitHubRepoAccess("https://api.github.com/graphql", allowed, {
			owner: "otherorg",
			name: "secret",
		}).allowed,
		false,
	);
	assert.equal(
		evaluateGitHubRepoAccess("https://api.github.com/graphql", allowed, {
			owner: "myorg",
			name: "platform-gitops",
		}).allowed,
		true,
	);
});

test("resolveBackendConfig fails closed when KVM device or runner is missing", () => {
	const emptyCfg = {
		vm: {},
		network: { extraAllowedHosts: [] },
		github: {},
		git: {},
		loadedFiles: [],
	};
	if (process.platform === "linux") {
		assert.throws(
			() =>
				resolveBackendConfig(
					"/nonexistent",
					{
						PI_SANDBOX_KVM_DEVICE: "/nonexistent/kvm-device",
						PATH: "/usr/bin:/bin",
					},
					undefined,
					emptyCfg,
				),
			/Hardware virtualization required/,
		);
	}
	assert.throws(
		() =>
			resolveBackendConfig(
				"/nonexistent",
				{
					PI_SANDBOX_ALLOW_EMULATION: "1",
					PI_SANDBOX_VMM: "krun",
					GONDOLIN_KRUN_RUNNER: "/nonexistent/krun-runner",
					PATH: "/usr/bin:/bin",
				},
				undefined,
				emptyCfg,
			),
		/GONDOLIN_KRUN_RUNNER/,
	);
});
