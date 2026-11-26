import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
	buildUsageEventV1,
	emptyCostUsage,
	emptyTokenUsage,
	exportUsageEvent,
	resolveRepoNameOnly,
	sanitizeExtensionSource,
	USAGE_SCHEMA_VERSION,
} from "./schema.ts";

test("resolveRepoNameOnly returns basename only and never parent paths", () => {
	const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pi-usage-repo-"));
	try {
		const repo = path.join(tmp, "payments-service");
		const nested = path.join(repo, "src", "handlers");
		fs.mkdirSync(path.join(repo, ".git"), { recursive: true });
		fs.mkdirSync(nested, { recursive: true });
		assert.equal(resolveRepoNameOnly(nested), "payments-service");
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});

test("sanitizeExtensionSource strips local host paths and credentials", () => {
	assert.equal(sanitizeExtensionSource("builtin"), null);
	assert.equal(sanitizeExtensionSource("sdk"), null);
	assert.equal(sanitizeExtensionSource("npm:pi-web-access@0.48.0"), "npm:pi-web-access@0.48.0");
	assert.equal(
		sanitizeExtensionSource("https://token@github.com/org/pi-pkg"),
		"https://github.com/org/pi-pkg",
	);
	assert.equal(
		sanitizeExtensionSource("/home/alice/.local/share/pi-team-package"),
		"pi-team-package",
	);
	assert.equal(
		sanitizeExtensionSource("/home/alice/.pi/agent/extensions/custom-ext.ts"),
		"custom-ext.ts",
	);
});

test("exportUsageEvent writes valid v1 JSONL with strictly allowlisted metadata keys", () => {
	const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pi-usage-log-"));
	const logPath = path.join(tmp, "usage.jsonl");
	try {
		const rawWithExtras = {
			schemaVersion: USAGE_SCHEMA_VERSION,
			eventType: "session_summary",
			startedAt: "2026-11-25T10:00:00.000Z",
			endedAt: "2026-11-25T10:01:00.000Z",
			durationMs: 60000,
			sessionId: "sess-123",
			repoName: "my-repo",
			piVersion: "1.6.0",
			teamPackageVersion: "0.1.0",
			mode: "print",
			startReason: "startup",
			endReason: "quit",
			provider: "anthropic",
			model: "claude-sonnet-4-5",
			modelsUsed: [],
			tokens: emptyTokenUsage(),
			costUsd: emptyCostUsage(),
			turnCount: 2,
			toolCalls: { bash: { calls: 3, errors: 1 } },
			totalToolCalls: 3,
			totalToolErrors: 1,
			loadedExtensions: ["pi-team-package"],
			loadedSkills: ["sandbox-pr-workflow"],
			invokedSkills: ["sandbox-pr-workflow"],
			sandbox: { active: true, escapeHatchUsed: false, backend: "krun" },
			// Attempted forbidden fields that must be stripped by allowlist serializer:
			prompt: "SECRET PROMPT",
			output: "SECRET OUTPUT",
			command: "cat ~/.oci/config",
			env: { OCI_TENANCY: "secret" },
		};

		exportUsageEvent(buildUsageEventV1(rawWithExtras), logPath);
		const lines = fs.readFileSync(logPath, "utf8").trim().split("\n");
		assert.equal(lines.length, 1);
		const parsed = JSON.parse(lines[0]);
		assert.equal(parsed.schemaVersion, 1);
		assert.equal(parsed.prompt, undefined);
		assert.equal(parsed.output, undefined);
		assert.equal(parsed.command, undefined);
		assert.equal(parsed.env, undefined);
		assert.equal(parsed.sandbox.active, true);
		assert.equal(parsed.toolCalls.bash.calls, 3);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
});
