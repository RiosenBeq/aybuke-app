# Repo tools

- `rename-brand.py <repo> [--write]`: renames the user-facing brand Glowlit → Aybuke
  (dry run without `--write`). Keeps internal identifiers (type names, the Xcode
  project and scheme, bundle ids, the App Group, `glowlit://`), fixes Turkish
  suffixes and Korean particles, and writes String Catalogs in Xcode's format.
- `merge_xcstrings.py`: a git merge driver for String Catalogs. Enable it with
  `git config merge.xcstrings.driver "python3 scripts/tools/merge_xcstrings.py %O %A %B"`
  and `*.xcstrings merge=xcstrings` in `.git/info/attributes`.
- `merge_json_words.py <path>`: during a merge, resolves a conflicted JSON file by a
  word-level three-way merge of every string.
