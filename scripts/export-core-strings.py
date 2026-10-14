#!/usr/bin/env python3
"""Register AppCore's user-facing English strings with the app's string catalogs.

    python3 scripts/export-core-strings.py          # write the files
    python3 scripts/export-core-strings.py --check  # fail if they're out of date (CI)

AppCore stays Foundation-only (it's tested on Linux), so its strings are plain
English. The app translates them at runtime with `L10n.core(_:)`, looking the
English text up in the catalog. This script writes `CoreStrings.swift` files
full of `String(localized:)` calls (never executed) so Xcode extracts those
keys for translators:

  ios/App/App/CoreStrings.swift              everything the app shows
  ios/GlowlitWidgets/CoreStrings.swift       template and category names, Live Activity text (widgets)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "ios" / "Packages" / "AppCore" / "Sources" / "AppCore"
APP_OUT = ROOT / "ios" / "App" / "App" / "CoreStrings.swift"
WIDGET_OUT = ROOT / "ios" / "GlowlitWidgets" / "CoreStrings.swift"

LITERAL = r'"((?:[^"\\\n]|\\.)*)"'


def literals(pattern: str, text: str) -> list[str]:
    return [m.group(1) for m in re.finditer(pattern, text)]


def block(text: str, header: str) -> str:
    """Body of the first `{ … }` block after `header`."""
    start = text.index(header)
    i = text.index("{", start) + 1
    depth = 1
    j = i
    while depth:
        depth += {"{": 1, "}": -1}.get(text[j], 0)
        j += 1
    return text[i:j - 1]


def collect() -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """(text, translator comment) pairs for the app and for the widgets."""
    read = lambda name: (CORE / name).read_text()
    app: list[tuple[str, str]] = []
    widget: list[tuple[str, str]] = []

    templates = read("TemplateCatalog.swift")
    categories = literals(r"return " + LITERAL, block(templates, "public var title: String"))
    categories += literals(r"return " + LITERAL, block(templates, "public var rowTitle: String"))
    titles = literals(r"\btitle: " + LITERAL, templates)
    subtitles = literals(r"\bsubtitle: " + LITERAL, templates)
    for text in categories:
        pair = (text, "Template collection heading")
        app.append(pair)
        widget.append(pair)
    for text in titles:
        pair = (text, "One-tap look (trend) name. Keep trend names people use in English, such as Y2K or Clean Girl.")
        app.append(pair)
        widget.append(pair)
    for text in subtitles:
        pair = (text, "One-tap look description, shown under its name")
        app.append(pair)
        widget.append(pair)

    shared = read("GlowShared.swift")
    stages = shared[shared.index("public enum GlowJobStage"):]
    for text in literals(r"return " + LITERAL, block(stages, "public var headline: String")):
        widget.append((text, "Live Activity headline (Dynamic Island and Lock Screen) while an AI job runs or when it ends"))
    for text in literals(r"return " + LITERAL, block(stages, "public var detail: String")):
        widget.append((text, "Live Activity line under the progress bar (Dynamic Island and Lock Screen)"))

    for text in literals(r"\bname: " + LITERAL, read("StyleCatalog.swift")):
        app.append((text, "Art style name on the Create screen"))
    for text in literals(r"return " + LITERAL, block(read("AspectRatio.swift"), "public var label: String")):
        app.append((text, "Image shape (aspect ratio) name"))
    for text in literals(r"return " + LITERAL, block(read("AIOperation.swift"), "public var displayName: String")):
        app.append((text, "Name of an editing tool"))
    for text in literals(r"reason: " + LITERAL, read("ContentPolicy.swift")):
        app.append((text, "Shown when a request is blocked by the content policy"))
    for text in literals(r"return " + LITERAL, block(read("BackendAPI.swift"), "public var errorDescription: String?")):
        app.append((text, "Error message"))
    backend = read("BackendAPI.swift")
    reasons = backend[backend.index("public enum ReportReason"):]
    for text in literals(r"return " + LITERAL, block(reasons, "public var title: String")):
        app.append((text, "Reason for reporting an AI result, a button in the Report dialog"))
    direct = read("DirectAI.swift")
    for text in literals(r"\.(?:invalidRequest|contentBlocked|network)\(" + LITERAL, direct + read("BackendAPI.swift")):
        app.append((text, "Error message"))
    prompts = read("PromptBuilder.swift")
    start = prompts.index("public static let surprisePrompts")
    ideas = prompts[prompts.index("[", prompts.index("=", start)):prompts.index("\n    ]", start)]
    for text in literals(LITERAL, ideas):
        app.append((text, "Example idea for creating an image, put in the prompt field"))
    for text in literals(r"\bidea\(" + LITERAL, read("LookSuggester.swift")):
        app.append((text, "Suggested Magic Edit request for her photo, shown on a chip in the editor"))

    def clean(pairs: list[tuple[str, str]]) -> list[tuple[str, str]]:
        seen: set[str] = set()
        out = []
        for text, comment in pairs:
            # Only static text can be looked up at runtime.
            if "\\(" in text or text in seen or not re.search(r"[A-Za-z]", text):
                continue
            seen.add(text)
            out.append((text, comment))
        return out

    return clean(app), clean(widget)


def render(pairs: list[tuple[str, str]], audience: str) -> str:
    lines = [
        "// Generated by scripts/export-core-strings.py from AppCore. Do not edit.",
        f"// Registers AppCore's English strings ({audience}) in the string catalog, so",
        "// `L10n.core(_:)` can translate them at runtime. Never called.",
        "enum CoreStrings {",
        "    static let all: [String] = [",
    ]
    for text, comment in pairs:
        lines.append(f'        String(localized: "{text}", comment: "{comment}"),')
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main() -> int:
    check = "--check" in sys.argv
    app, widget = collect()
    outputs = {APP_OUT: render(app, "everything the app shows"), WIDGET_OUT: render(widget, "names the widgets show")}
    stale = [path for path, text in outputs.items() if not path.exists() or path.read_text() != text]
    if check:
        if stale:
            print("Out of date: " + ", ".join(str(p.relative_to(ROOT)) for p in stale) + ". Run scripts/export-core-strings.py.")
            return 1
        print("Core strings are up to date.")
        return 0
    for path, text in outputs.items():
        path.write_text(text)
    print(f"Wrote {len(app)} app strings and {len(widget)} widget strings.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
