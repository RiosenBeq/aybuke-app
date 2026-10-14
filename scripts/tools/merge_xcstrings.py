"""Three-way merge for Xcode String Catalogs (.xcstrings), usable as a git merge driver.

    merge_xcstrings.py <base> <ours> <theirs>     # writes the result to <ours>

Keys added on either side are kept; a key added on the other side is placed
right after the key that precedes it there (Xcode re-sorts on its next save).
Per key, a side that changed the entry wins over a side that didn't; when both
changed the same key differently, the localizations are merged per language
(a language changed on one side only takes that side) and real clashes are
reported and fail the merge.
"""
import json
import re
import sys
from pathlib import Path


def xcode_json(data) -> str:
    out = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "))
    return re.sub(r'^( *)(".*" : )\{\}(,?)$', lambda m: f"{m.group(1)}{m.group(2)}{{\n\n{m.group(1)}}}{m.group(3)}", out, flags=re.M)


def load(path):
    text = Path(path).read_text(encoding="utf-8").strip()
    return json.loads(text) if text else {"sourceLanguage": "en", "strings": {}, "version": "1.0"}


def merge_entry(key, base, ours, theirs, clashes):
    if ours == theirs:
        return ours
    if base == ours:
        return theirs
    if base == theirs:
        return ours
    # Both changed: merge localizations language by language.
    result = dict(ours)
    base_l = (base or {}).get("localizations", {})
    ours_l = (ours or {}).get("localizations", {})
    theirs_l = (theirs or {}).get("localizations", {})
    merged = dict(ours_l)
    for lang in set(ours_l) | set(theirs_l):
        b, o, t = base_l.get(lang), ours_l.get(lang), theirs_l.get(lang)
        if o == t or t == b:
            continue
        if o == b:
            if t is None:
                merged.pop(lang, None)
            else:
                merged[lang] = t
        else:
            clashes.append(f"{key!r} [{lang}]")
    if merged:
        result["localizations"] = merged
    for field in set((ours or {}).keys()) | set((theirs or {}).keys()):
        if field == "localizations":
            continue
        b, o, t = (base or {}).get(field), (ours or {}).get(field), (theirs or {}).get(field)
        if o != t and o == b:
            if t is None:
                result.pop(field, None)
            else:
                result[field] = t
        elif o != t and t != b:
            clashes.append(f"{key!r} field {field}")
    return result


def main():
    base_path, ours_path, theirs_path = sys.argv[1:4]
    base, ours, theirs = load(base_path), load(ours_path), load(theirs_path)
    b, o, t = base["strings"], ours["strings"], theirs["strings"]
    clashes = []
    result = {}
    for key, entry in o.items():
        if key in t:
            result[key] = merge_entry(key, b.get(key), entry, t[key], clashes)
        elif key in b and entry == b[key]:
            continue  # deleted on their side, untouched on ours
        else:
            result[key] = entry
    # Their new keys, after the key that precedes them on their side.
    ordered = list(result.items())
    position = {key: i for i, (key, _) in enumerate(ordered)}
    their_keys = list(t)
    inserts = {}
    for index, key in enumerate(their_keys):
        if key in result or key in b:
            continue
        anchor = None
        for previous in reversed(their_keys[:index]):
            if previous in position or previous in inserts:
                anchor = previous
                break
        inserts[key] = anchor
    final = []
    pending = {}
    for key, anchor in inserts.items():
        pending.setdefault(anchor, []).append(key)

    def emit(key):
        for child in pending.get(key, []):
            final.append((child, t[child]))
            emit(child)

    emit(None)
    for key, entry in ordered:
        final.append((key, entry))
        emit(key)
    out = dict(ours)
    out["strings"] = dict(final)
    Path(ours_path).write_text(xcode_json(out), encoding="utf-8")
    if clashes:
        print("xcstrings merge clashes:", *clashes, sep="\n  ", file=sys.stderr)
        sys.exit(1)


main()
