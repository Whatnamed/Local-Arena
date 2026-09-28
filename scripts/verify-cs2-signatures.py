"""Read-only signature check against an installed CS2 Windows build.

Usage: python scripts/verify-cs2-signatures.py <Counter-Strike Global Offensive/game directory> [CounterStrikeSharp gamedata.json]

Pass the directory containing both csgo/bin/win64/server.dll and
bin/win64/engine2.dll, not the game/csgo directory used by Local Arena UI.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def matches(data: bytes, signature: str) -> list[int]:
    pattern = [None if part == "?" else int(part, 16) for part in signature.split()]
    runs = []
    start = 0
    while start < len(pattern):
        if pattern[start] is None:
            start += 1
            continue
        end = start
        while end < len(pattern) and pattern[end] is not None:
            end += 1
        runs.append((start, bytes(pattern[start:end])))
        start = end
    anchor_start, anchor = max(runs, key=lambda run: len(run[1]))
    found = []
    pos = 0
    while (pos := data.find(anchor, pos)) != -1:
        candidate = pos - anchor_start
        if candidate >= 0 and candidate + len(pattern) <= len(data) and all(
            byte is None or data[candidate + index] == byte
            for index, byte in enumerate(pattern)
        ):
            found.append(candidate)
        pos += 1
    return found


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(__doc__.strip())
        return 2
    game = Path(sys.argv[1]).resolve()
    modules = {
        "server": game / "csgo/bin/win64/server.dll",
        "engine2": game / "bin/win64/engine2.dll",
    }
    data = {name: path.read_bytes() for name, path in modules.items()}
    bothider = json.loads((ROOT / "addons/BotHider/gamedata.json").read_text("utf-8"))
    targets = {
        name: (entry["signatures"]["library"], entry["signatures"]["windows"])
        for name, entry in bothider.items()
        if "signatures" in entry and entry["signatures"].get("windows")
    }
    source = (ROOT / "addons/counterstrikesharp/shared/CosmeticNativeSignatures.cs").read_text("utf-8")
    for name in ("AttributeWriter", "ItemViewConstructor", "SetWearables", "SetModel"):
        match = re.search(rf"internal static string {name} =>.*?\n\s*: \"([^\"]+)\";", source, re.S)
        if match is None:
            raise ValueError(f"Missing Windows signature: {name}")
        targets[f"Cosmetics::{name}"] = ("server", match.group(1))
    if len(sys.argv) == 3:
        css_gamedata = json.loads(Path(sys.argv[2]).read_text("utf-8"))
        for name, entry in css_gamedata.items():
            signature = entry.get("signatures", {})
            if signature.get("windows") and signature.get("library", "server") in data:
                targets[f"CounterStrikeSharp::{name}"] = (
                    signature.get("library", "server"), signature["windows"]
                )
    failed = False
    for name, (module, signature) in targets.items():
        offsets = matches(data[module], signature)
        print(f"{name}: {len(offsets)} match(es) in {module}" +
              (f" at 0x{offsets[0]:X}" if len(offsets) == 1 else ""))
        if not offsets:
            parts = signature.split()
            for length in (10, 20, 30, 40, 50):
                if length >= len(parts): break
                partial = matches(data[module], " ".join(parts[:length]))
                print(f"  first {length} bytes: {len(partial)} match(es)" +
                      (f" at 0x{partial[0]:X}" if len(partial) == 1 else ""))
        failed |= len(offsets) != 1
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
