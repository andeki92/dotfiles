#!/usr/bin/env node
/**
 * Mandatory pre-launch sandbox check invoked by the managed `pi` launcher
 * (`~/.pi/agent/bin/pi`) BEFORE executing Pi itself.
 *
 * Pi's extension loader logs extension import/load errors and continues with
 * raw host tools. Running this preflight before `exec pi` guarantees Pi refuses
 * to start if Gondolin cannot import, if the sandbox extension is disabled or
 * missing from settings, or if sandbox.toml / KVM / runner prerequisites fail.
 *
 * Bypassed ONLY when `PI_SANDBOX_UNSAFE=1` (`pi-unsafe`).
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	assertSafeWorkspaceDir,
	expandHomePath,
	loadEgressPolicy,
	loadSandboxConfig,
	resolveBackendConfig,
	resolveGitHubAuth,
} from "./policy.ts";

const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SANDBOX_ENTRY = path.join(PACKAGE_ROOT, "extensions", "gondolin-sandbox", "index.ts");

function fail(reason) {
	process.stderr.write(
		[
			"",
			"[pi-sandbox] FATAL: Sandbox preflight failed before starting Pi.",
			`[pi-sandbox] Reason: ${reason}`,
			"[pi-sandbox] Refusing to start Pi with host tools (fail-closed).",
			"[pi-sandbox] If you explicitly intend to run unsandboxed, use: pi-unsafe",
			"",
		].join("\n"),
	);
	process.exit(2);
}

function hasExplicitSandboxExtensionFlag(argv) {
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === "--") break;
		if ((arg === "-e" || arg === "--extension") && argv[i + 1]) {
			const candidate = path.resolve(argv[i + 1]);
			if (
				candidate === PACKAGE_ROOT ||
				candidate === SANDBOX_ENTRY ||
				candidate === path.dirname(SANDBOX_ENTRY)
			) {
				return true;
			}
			i++;
		}
	}
	return false;
}

function hasNoExtensionsFlag(argv) {
	for (const arg of argv) {
		if (arg === "--") break;
		if (arg === "-ne" || arg === "--no-extensions") return true;
	}
	return false;
}

function verifySandboxConfiguredInSettings(argv) {
	if (hasNoExtensionsFlag(argv) && !hasExplicitSandboxExtensionFlag(argv)) {
		throw new Error(
			"Flag --no-extensions (-ne) disables the Gondolin sandbox extension. Use `pi-unsafe` if you intentionally want to run unsandboxed.",
		);
	}

	if (hasExplicitSandboxExtensionFlag(argv)) return;

	const agentDir = process.env.PI_CODING_AGENT_DIR
		? expandHomePath(process.env.PI_CODING_AGENT_DIR)
		: path.join(os.homedir(), ".pi", "agent");
	const settingsPath = path.join(agentDir, "settings.json");

	if (!fs.existsSync(settingsPath)) {
		throw new Error(
			`Pi settings file not found at "${settingsPath}". Run scripts/pi-bootstrap.sh to configure the sandbox package.`,
		);
	}

	const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
	const realPkgRoot = fs.existsSync(PACKAGE_ROOT) ? fs.realpathSync(PACKAGE_ROOT) : PACKAGE_ROOT;
	const realSandboxEntry = fs.existsSync(SANDBOX_ENTRY)
		? fs.realpathSync(SANDBOX_ENTRY)
		: SANDBOX_ENTRY;

	const packages = Array.isArray(settings.packages) ? settings.packages : [];
	for (const entry of packages) {
		const rawSource = typeof entry === "string" ? entry : entry?.source;
		if (typeof rawSource !== "string") continue;
		if (rawSource.startsWith("npm:") || rawSource.startsWith("git:") || rawSource.includes("://")) {
			continue;
		}
		const resolved = rawSource.startsWith("~")
			? expandHomePath(rawSource)
			: path.resolve(agentDir, rawSource);
		if (!fs.existsSync(resolved)) continue;
		const realResolved = fs.realpathSync(resolved);
		if (realResolved === realPkgRoot) {
			// Ensure the object form did not disable extensions via `extensions: []` or `-...gondolin-sandbox...`
			if (typeof entry === "object" && entry !== null && Array.isArray(entry.extensions)) {
				if (entry.extensions.length === 0) {
					throw new Error("settings.json disables extensions on the sandbox package (extensions: []).");
				}
				const explicitlyExcluded = entry.extensions.some(
					(p) => typeof p === "string" && (p.startsWith("!") || p.startsWith("-")) && p.includes("gondolin-sandbox"),
				);
				if (explicitlyExcluded) {
					throw new Error("settings.json excludes gondolin-sandbox from the sandbox package.");
				}
			}
			return;
		}
	}

	const extensions = Array.isArray(settings.extensions) ? settings.extensions : [];
	for (const ext of extensions) {
		if (typeof ext !== "string" || ext.startsWith("!") || ext.startsWith("-")) continue;
		const resolved = ext.startsWith("~") ? expandHomePath(ext) : path.resolve(agentDir, ext);
		if (!fs.existsSync(resolved)) continue;
		const realResolved = fs.realpathSync(resolved);
		if (realResolved === realSandboxEntry || realResolved === path.dirname(realSandboxEntry)) {
			return;
		}
	}

	throw new Error(
		`Gondolin sandbox package (${PACKAGE_ROOT}) is not configured in "${settingsPath}". Run scripts/pi-bootstrap.sh.`,
	);
}

try {
	const argv = process.argv.slice(2);

	// 1. Verify sandbox extension files exist and are active in settings.json
	if (!fs.existsSync(SANDBOX_ENTRY)) {
		throw new Error(`Sandbox extension entrypoint missing at "${SANDBOX_ENTRY}"`);
	}
	verifySandboxConfiguredInSettings(argv);

	// 2. Verify @earendil-works/gondolin actually imports cleanly (catches broken/missing node_modules
	//    BEFORE Pi's extension loader can ignore the import failure and start with host tools)
	const gondolin = await import("@earendil-works/gondolin");
	if (typeof gondolin.VM?.create !== "function" || typeof gondolin.createHttpHooks !== "function") {
		throw new Error("@earendil-works/gondolin imported without expected VM/createHttpHooks exports");
	}

	// 3. Validate workspace, sandbox.toml / sandbox.local.toml, egress policy, KVM/VMM, and GitHub auth
	const localCwd = process.cwd();
	const realLocalCwd = fs.existsSync(localCwd) ? fs.realpathSync(localCwd) : localCwd;
	assertSafeWorkspaceDir(realLocalCwd);

	const sandboxConfig = loadSandboxConfig(process.env);
	loadEgressPolicy(process.env, sandboxConfig);

	const hasLocalImage = (imageRef) => {
		try {
			const expectedArch = process.arch === "arm64" ? "aarch64" : "x86_64";
			return gondolin
				.listImageRefs()
				.some((ref) => ref.reference === imageRef && Boolean(ref.targets?.[expectedArch]));
		} catch {
			return false;
		}
	};
	resolveBackendConfig(PACKAGE_ROOT, process.env, hasLocalImage, sandboxConfig);
	resolveGitHubAuth(process.env, sandboxConfig);
} catch (error) {
	const message = error instanceof Error ? error.message : String(error);
	fail(message);
}
