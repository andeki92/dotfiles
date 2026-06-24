#!/usr/bin/env python3
"""Validate a JSON or JSONC file.

Strict JSON passes immediately. Otherwise we strip JSONC extensions — `//` and
`/* */` comments and trailing commas — in a *string-aware* way (so `//` inside a
URL string is never mistaken for a comment) and re-validate. Exit 0 if the file
is valid JSON/JSONC, exit 1 with the parse error on stderr otherwise.
"""
import json
import re
import sys


def strip_jsonc(src: str) -> str:
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':  # copy a string literal verbatim, honoring escapes
            out.append(c)
            i += 1
            while i < n:
                ch = src[i]
                out.append(ch)
                if ch == '\\' and i + 1 < n:
                    out.append(src[i + 1])
                    i += 2
                    continue
                i += 1
                if ch == '"':
                    break
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '/':  # line comment
            i += 2
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':  # block comment
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    stripped = ''.join(out)
    # Drop trailing commas before a closing } or ].
    return re.sub(r',(\s*[}\]])', r'\1', stripped)


def main() -> int:
    path = sys.argv[1]
    with open(path, encoding='utf-8') as fh:
        src = fh.read()
    try:
        json.loads(src)
        return 0
    except json.JSONDecodeError:
        pass
    try:
        json.loads(strip_jsonc(src))
        return 0
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"{exc}\n")
        return 1


if __name__ == '__main__':
    sys.exit(main())
