from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ENTRY = ROOT / "src" / "testing.lua"
MODULES = ROOT / "src" / "modules"
DIST = ROOT / "dist"
OUTPUT = DIST / "heartsteel.lua"

MODULE_NAMES = (
    "AutoCycle",
    "ElementZonePull",
    "Flags",
    "MiscSpeed",
    "MiscConfig",
    "MiscElement",
    "MiscPosition",
    "MiscAntiAfk",
    "MiscSimMovement",
    "MiscEggAnimations",
    "PetdexFarm",
    "Pets",
    "PetdexRewards",
    "EggOpener",
    "Merchant",
    "LogsDungeon",
    "LogsPets",
    "LogsDiscordMonitor",
)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def extract_installer_body(module_name: str, module_text: str) -> str:
    lines = module_text.splitlines()
    if not lines or lines[0] != "return function(HS, S)":
        raise ValueError(f"{module_name}.lua must start with: return function(HS, S)")

    body_lines = lines[1:]

    while body_lines and body_lines[-1].strip() == "":
        body_lines.pop()

    if not body_lines or body_lines[-1].strip() != "end":
        raise ValueError(f"{module_name}.lua must end with final: end")

    body_lines = body_lines[:-1]

    return "\n".join(body_lines).rstrip() + "\n"


def replace_module(entry_text: str, module_name: str, module_body: str) -> str:
    start = f"-- HEARTSTEEL_MODULE_START: {module_name}"
    end = f"-- HEARTSTEEL_MODULE_END: {module_name}"

    start_index = entry_text.find(start)
    end_index = entry_text.find(end)

    if start_index == -1:
        raise ValueError(f"Missing start marker: {start}")
    if end_index == -1:
        raise ValueError(f"Missing end marker: {end}")
    if end_index <= start_index:
        raise ValueError(f"End marker appears before start marker for {module_name}")

    end_line_index = entry_text.find("\n", end_index)
    if end_line_index == -1:
        end_line_index = len(entry_text)
    else:
        end_line_index += 1

    replacement = (
        f"{start}\n"
        f"-- Bundled from src/modules/{module_name}.lua\n"
        f"do\n"
        f"{module_body}"
        f"end\n"
        f"{end}\n"
    )

    return entry_text[:start_index] + replacement + entry_text[end_line_index:]


def main() -> None:
    DIST.mkdir(exist_ok=True)

    entry_text = read_text(ENTRY)
    output_text = entry_text
    for module_name in MODULE_NAMES:
        module_text = read_text(MODULES / f"{module_name}.lua")
        module_body = extract_installer_body(module_name, module_text)
        output_text = replace_module(output_text, module_name, module_body)

    OUTPUT.write_text(output_text, encoding="utf-8")
    print(f"Bundled {ENTRY} + {len(MODULE_NAMES)} modules -> {OUTPUT}")


if __name__ == "__main__":
    main()
