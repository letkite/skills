#!/usr/bin/env python3
"""Check every skill and plugin in this repo. Run from the repo root: python3 tools/check.py

Skills must work both as plugin skills in Claude Code and as zip uploads to claude.ai, so SKILL.md
frontmatter is held to claude.ai's stricter rules."""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALLOWED = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
SECRET = re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}"
                    r"|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----")
errors = []


def err(where, msg):
    errors.append(f"{where}: {msg}")


def frontmatter(path):
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        err(path, "must start with a --- frontmatter block on line 1")
        return {}, text
    head, _, body = text[4:].partition("\n---\n")
    fields, key = {}, None
    for line in head.splitlines():
        m = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):\s?(.*)$", line)
        if m:
            key = m.group(1)
            fields[key] = m.group(2).strip()
        elif key and line.startswith((" ", "\t")):
            fields[key] += " " + line.strip()
    return fields, body


market = json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())
listed = {}
for p in market.get("plugins", []):
    src = (ROOT / p["source"]).resolve()
    listed[src] = p["name"]
    manifest = src / ".claude-plugin/plugin.json"
    if not manifest.is_file():
        err(p["source"], "listed in marketplace.json but has no .claude-plugin/plugin.json")
        continue
    if json.loads(manifest.read_text()).get("name") != p["name"]:
        err(manifest, f"name must equal the marketplace entry name '{p['name']}'")

for plugin in sorted((ROOT / "plugins").iterdir()):
    if plugin.is_dir() and plugin.resolve() not in listed:
        err(plugin, "plugin directory not listed in .claude-plugin/marketplace.json")

for skill_md in sorted(ROOT.glob("plugins/*/skills/*/SKILL.md")):
    d = skill_md.parent
    f, body = frontmatter(skill_md)
    extra = set(f) - ALLOWED
    if extra:
        err(skill_md, f"frontmatter keys not accepted by claude.ai: {sorted(extra)}")
    name = f.get("name", "")
    if name != d.name:
        err(skill_md, f"name '{name}' must equal the folder name '{d.name}'")
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) or len(name) > 64:
        err(skill_md, "name: lowercase letters, digits and single hyphens, at most 64 characters")
    if re.search(r"claude|anthropic", name):
        err(skill_md, "name must not contain 'claude' or 'anthropic' (claude.ai rejects it)")
    desc = f.get("description", "")
    if not 1 <= len(desc) <= 1024:
        err(skill_md, f"description must be 1-1024 characters (is {len(desc)})")
    if "compatibility" in f and len(f["compatibility"]) > 500:
        err(skill_md, "compatibility must be at most 500 characters")
    if re.search(r"<[A-Za-z/]", desc):
        err(skill_md, "no XML/HTML tags in the description")
    lines = body.count("\n")
    if lines > 500:
        err(skill_md, f"body is {lines} lines; keep it under 500 and move detail to references/")
    for link in re.findall(r"\]\(((?:references|scripts|assets)/[^)#]+)\)", body):
        if not (d / link).exists():
            err(skill_md, f"links to missing file {link}")

for path in sorted(ROOT.rglob("*")):
    if ".git" in path.parts or not path.is_file() or path.suffix in {".png", ".jpg", ".zip"}:
        continue
    try:
        if SECRET.search(path.read_text(encoding="utf-8")):
            err(path, "looks like it contains a secret")
    except UnicodeDecodeError:
        pass

scripts = [str(p) for p in ROOT.glob("plugins/*/skills/*/scripts/*")
           if p.is_file() and p.read_text(errors="ignore").startswith("#!/usr/bin/env bash")]
if scripts:
    try:
        r = subprocess.run(["shellcheck", "-S", "warning", *scripts], capture_output=True, text=True)
        if r.returncode:
            err("shellcheck", "\n" + r.stdout)
    except FileNotFoundError:
        print("note: shellcheck not installed, scripts not linted", file=sys.stderr)

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"ok: {len(listed)} plugin(s), {len(list(ROOT.glob('plugins/*/skills/*/SKILL.md')))} skill(s)")
