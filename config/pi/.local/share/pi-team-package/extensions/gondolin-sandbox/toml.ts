/**
 * Minimal, zero-dependency TOML parser for `~/.config/sandbox.toml`.
 *
 * Supports:
 * - `[section]` and `[section.sub]` table headers
 * - `#` line and inline comments (respecting quoted strings)
 * - basic `"..."` (with standard escapes) and literal `'...'` strings
 * - booleans (`true` / `false`) and integers
 * - single-line and multi-line arrays (including trailing commas)
 */

export type TomlValue = string | number | boolean | TomlValue[] | TomlTable;
export interface TomlTable {
	[key: string]: TomlValue;
}

function stripComment(line: string): string {
	let inBasic = false;
	let inLiteral = false;
	let escaped = false;
	for (let i = 0; i < line.length; i++) {
		const ch = line[i];
		if (inBasic) {
			if (escaped) {
				escaped = false;
			} else if (ch === "\\") {
				escaped = true;
			} else if (ch === '"') {
				inBasic = false;
			}
		} else if (inLiteral) {
			if (ch === "'") inLiteral = false;
		} else if (ch === '"') {
			inBasic = true;
		} else if (ch === "'") {
			inLiteral = true;
		} else if (ch === "#") {
			return line.slice(0, i);
		}
	}
	return line;
}

function parseBasicString(raw: string, lineNum: number): string {
	let out = "";
	for (let i = 1; i < raw.length - 1; i++) {
		const ch = raw[i];
		if (ch !== "\\") {
			out += ch;
			continue;
		}
		i++;
		const esc = raw[i];
		if (esc === '"') out += '"';
		else if (esc === "\\") out += "\\";
		else if (esc === "n") out += "\n";
		else if (esc === "r") out += "\r";
		else if (esc === "t") out += "\t";
		else throw new Error(`sandbox.toml:${lineNum}: unsupported escape \\${esc ?? ""}`);
	}
	return out;
}

function splitArrayItems(inner: string, lineNum: number): string[] {
	const items: string[] = [];
	let current = "";
	let inBasic = false;
	let inLiteral = false;
	let escaped = false;
	let depth = 0;

	for (let i = 0; i < inner.length; i++) {
		const ch = inner[i];
		if (inBasic) {
			current += ch;
			if (escaped) escaped = false;
			else if (ch === "\\") escaped = true;
			else if (ch === '"') inBasic = false;
		} else if (inLiteral) {
			current += ch;
			if (ch === "'") inLiteral = false;
		} else if (ch === '"') {
			inBasic = true;
			current += ch;
		} else if (ch === "'") {
			inLiteral = true;
			current += ch;
		} else if (ch === "[") {
			depth++;
			current += ch;
		} else if (ch === "]") {
			depth--;
			if (depth < 0) throw new Error(`sandbox.toml:${lineNum}: unexpected ']'`);
			current += ch;
		} else if (ch === "," && depth === 0) {
			const trimmed = current.trim();
			if (trimmed.length > 0) items.push(trimmed);
			current = "";
		} else {
			current += ch;
		}
	}

	if (inBasic || inLiteral || depth !== 0) {
		throw new Error(`sandbox.toml:${lineNum}: unterminated string or array`);
	}
	const tail = current.trim();
	if (tail.length > 0) items.push(tail);
	return items;
}

function parseValue(raw: string, lineNum: number): TomlValue {
	const trimmed = raw.trim();
	if (trimmed === "true") return true;
	if (trimmed === "false") return false;
	if (/^-?\d+$/.test(trimmed)) return Number.parseInt(trimmed, 10);

	if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
		return parseBasicString(trimmed, lineNum);
	}
	if (trimmed.startsWith("'") && trimmed.endsWith("'") && trimmed.length >= 2) {
		return trimmed.slice(1, -1);
	}
	if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
		const inner = trimmed.slice(1, -1).trim();
		if (!inner) return [];
		return splitArrayItems(inner, lineNum).map((item) => parseValue(item, lineNum));
	}

	throw new Error(`sandbox.toml:${lineNum}: unsupported value "${trimmed}"`);
}

function hasUnclosedBracket(text: string): boolean {
	let inBasic = false;
	let inLiteral = false;
	let escaped = false;
	let depth = 0;

	for (let i = 0; i < text.length; i++) {
		const ch = text[i];
		if (inBasic) {
			if (escaped) escaped = false;
			else if (ch === "\\") escaped = true;
			else if (ch === '"') inBasic = false;
		} else if (inLiteral) {
			if (ch === "'") inLiteral = false;
		} else if (ch === '"') {
			inBasic = true;
		} else if (ch === "'") {
			inLiteral = true;
		} else if (ch === "[") {
			depth++;
		} else if (ch === "]") {
			depth--;
		}
	}

	return depth > 0;
}

export function parseToml(source: string): TomlTable {
	const root: TomlTable = {};
	let currentSection: TomlTable = root;
	const lines = source.replace(/\r\n/g, "\n").split("\n");

	for (let i = 0; i < lines.length; i++) {
		const lineNum = i + 1;
		const cleaned = stripComment(lines[i] ?? "").trim();
		if (!cleaned) continue;

		if (cleaned.startsWith("[") && cleaned.endsWith("]")) {
			const header = cleaned.slice(1, -1).trim();
			if (!header || !/^[A-Za-z0-9_.-]+$/.test(header)) {
				throw new Error(`sandbox.toml:${lineNum}: invalid section header "${cleaned}"`);
			}
			let cursor: TomlTable = root;
			for (const part of header.split(".")) {
				const existing = cursor[part];
				if (existing === undefined) {
					const next: TomlTable = {};
					cursor[part] = next;
					cursor = next;
				} else if (typeof existing === "object" && existing !== null && !Array.isArray(existing)) {
					cursor = existing as TomlTable;
				} else {
					throw new Error(`sandbox.toml:${lineNum}: section "${header}" conflicts with existing key`);
				}
			}
			currentSection = cursor;
			continue;
		}

		const eqIndex = cleaned.indexOf("=");
		if (eqIndex <= 0) {
			throw new Error(`sandbox.toml:${lineNum}: expected key = value`);
		}

		const key = cleaned.slice(0, eqIndex).trim();
		if (!/^[A-Za-z0-9_-]+$/.test(key)) {
			throw new Error(`sandbox.toml:${lineNum}: invalid key "${key}"`);
		}

		let valueStr = cleaned.slice(eqIndex + 1).trim();
		while (hasUnclosedBracket(valueStr) && i + 1 < lines.length) {
			i++;
			const nextClean = stripComment(lines[i] ?? "").trim();
			if (nextClean) valueStr += ` ${nextClean}`;
		}

		currentSection[key] = parseValue(valueStr, lineNum);
	}

	return root;
}
