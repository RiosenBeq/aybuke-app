"""Resolves a conflicted JSON file in the index by a word-level three-way merge
of every string (both sides' edits apply when they don't overlap).

    merge_json_words.py <path-in-repo>     (run from the repo root during a merge)
"""
import json
import re
import subprocess
import sys
from difflib import SequenceMatcher

path = sys.argv[1]


def stage(n):
    return json.loads(subprocess.run(["git", "show", f":{n}:{path}"], capture_output=True, text=True, check=True).stdout)


base, ours, theirs = stage(1), stage(2), stage(3)
unresolved = []


def tokens(s):
    return re.findall(r"\s+|[^\s]+", s)


def merge3(b, o, t, where):
    if o == t or t == b:
        return o
    if o == b:
        return t
    B, O, T = tokens(b), tokens(o), tokens(t)

    def edits(x):
        return [(i1, i2, x[j1:j2]) for tag, i1, i2, j1, j2 in SequenceMatcher(None, B, x, autojunk=False).get_opcodes() if tag != "equal"]
    eo, et = edits(O), edits(T)
    for a1, a2, _ in eo:
        for b1, b2, _ in et:
            if (a1 < b2 and b1 < a2) or a1 == a2 == b1 == b2:
                unresolved.append(where)
                return o
    out, pos = [], 0
    for i1, i2, rep in sorted(eo + et, key=lambda e: (e[0], e[1])):
        out.extend(B[pos:i1])
        out.extend(rep)
        pos = i2
    out.extend(B[pos:])
    return "".join(out)


def walk(b, o, t, where):
    if isinstance(o, dict):
        result = {k: walk((b or {}).get(k) if isinstance(b, dict) else None, o[k], (t or {}).get(k, o[k]), f"{where}.{k}") for k in o}
        for k, v in (t or {}).items():
            if k not in o and (not isinstance(b, dict) or k not in b):
                result[k] = v
        return result
    if isinstance(o, list):
        return [walk(b[i] if isinstance(b, list) and i < len(b) else None, o[i], t[i] if isinstance(t, list) and i < len(t) else o[i], f"{where}[{i}]") for i in range(len(o))]
    if isinstance(o, str) and isinstance(t, str):
        return merge3(b if isinstance(b, str) else o, o, t, where)
    if o == t or t == b:
        return o
    return t if o == b else o


result = walk(base, ours, theirs, "$")
if unresolved:
    print("overlapping edits, resolve by hand:", *unresolved, sep="\n  ")
    sys.exit(1)
with open(path, "w", encoding="utf-8") as f:
    f.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print("merged", path)
