#!/usr/bin/env python3
"""
Bootstrap script for beads-based orchestration.

Creates:
- .beads/ directory with beads CLI
- .claude/agents/ with code-reviewer and merge-supervisor
- .claude/hooks/ with enforcement hooks (Node.js)
- .claude/rules/ with beads-workflow and optional dev rules
- .claude/skills/ with project-discovery
- .claude/settings.json with hook configuration
- CLAUDE.md with orchestrator instructions

Usage:
    python bootstrap.py [--project-name NAME] [--project-dir DIR] [--with-rules]
"""

import os
import sys
import json
import shutil
import subprocess
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

_SHELL = sys.platform == "win32"
SCRIPT_DIR = Path(__file__).parent.resolve()
TEMPLATES_DIR = SCRIPT_DIR / "templates"


# ============================================================================
# PROJECT NAME INFERENCE
# ============================================================================

def infer_project_name(project_dir: Path) -> str:
    """Auto-infer project name from package files or directory name."""
    for detect_fn in [_from_package_json, _from_pyproject, _from_cargo, _from_go_mod]:
        name = detect_fn(project_dir)
        if name:
            return name
    return project_dir.name.replace("-", " ").replace("_", " ").title()


def _from_package_json(project_dir: Path) -> str | None:
    p = project_dir / "package.json"
    if not p.exists():
        return None
    try:
        name = json.loads(p.read_text()).get("name")
        return name.replace("-", " ").replace("_", " ").title() if name else None
    except Exception:
        return None


def _from_pyproject(project_dir: Path) -> str | None:
    if not tomllib:
        return None
    p = project_dir / "pyproject.toml"
    if not p.exists():
        return None
    try:
        data = tomllib.loads(p.read_text())
        name = data.get("project", {}).get("name") or data.get("tool", {}).get("poetry", {}).get("name")
        return name.replace("-", " ").replace("_", " ").title() if name else None
    except Exception:
        return None


def _from_cargo(project_dir: Path) -> str | None:
    if not tomllib:
        return None
    p = project_dir / "Cargo.toml"
    if not p.exists():
        return None
    try:
        name = tomllib.loads(p.read_text()).get("package", {}).get("name")
        return name.replace("-", " ").replace("_", " ").title() if name else None
    except Exception:
        return None


def _from_go_mod(project_dir: Path) -> str | None:
    p = project_dir / "go.mod"
    if not p.exists():
        return None
    try:
        for line in p.read_text().splitlines():
            if line.startswith("module "):
                name = line.split()[1].split("/")[-1]
                return name.replace("-", " ").replace("_", " ").title()
    except Exception:
        pass
    return None


# ============================================================================
# HELPERS
# ============================================================================

def copy_and_replace(source: Path, dest: Path, replacements: dict) -> None:
    content = source.read_text()
    for placeholder, value in replacements.items():
        content = content.replace(placeholder, value)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content)


# ============================================================================
# STEPS
# ============================================================================

def install_beads(project_dir: Path) -> bool:
    """Install beads CLI and initialize .beads directory."""
    print("\n[1/6] Installing beads...")

    if not shutil.which("bd"):
        print("  - beads CLI (bd) not found, installing...")
        for method, cmd in [
            ("Homebrew", ["brew", "install", "steveyegge/beads/bd"]),
            ("npm", ["npm", "install", "-g", "@beads/bd"]),
            ("go", ["go", "install", "github.com/steveyegge/beads/cmd/bd@latest"]),
        ]:
            if shutil.which(cmd[0]):
                result = subprocess.run(cmd, capture_output=True, text=True, shell=_SHELL)
                if result.returncode == 0:
                    print(f"  - Installed via {method}")
                    break
        else:
            print("  ERROR: Could not install beads CLI (bd)")
            print("  Install manually: https://github.com/steveyegge/beads#-installation")
            return False
    else:
        print("  - beads CLI already installed")

    beads_dir = project_dir / ".beads"
    if not beads_dir.exists():
        print("  - Initializing .beads directory...")
        try:
            result = subprocess.run(
                ["bd", "init"], cwd=project_dir,
                capture_output=True, text=True, shell=_SHELL,
                stdin=subprocess.DEVNULL, timeout=15,
            )
        except subprocess.TimeoutExpired:
            result = None
            print("  - bd init timed out (Dolt server not running?)")
        if result is None or result.returncode != 0:
            beads_dir.mkdir(exist_ok=True)
            (beads_dir / "issues.jsonl").touch()
            print("  - Created .beads manually (run 'bd init' later with Dolt server running)")

    # Setup memory/knowledge base
    memory_dir = beads_dir / "memory"
    memory_dir.mkdir(parents=True, exist_ok=True)
    knowledge_file = memory_dir / "knowledge.jsonl"
    if not knowledge_file.exists():
        knowledge_file.touch()

    recall_src = TEMPLATES_DIR / "hooks" / "recall.cjs"
    if recall_src.exists():
        shutil.copy2(recall_src, memory_dir / "recall.cjs")

    print("  DONE")
    return True


def copy_agents(project_dir: Path, project_name: str) -> None:
    """Copy code-reviewer and merge-supervisor templates."""
    print("\n[2/6] Copying agents...")
    agents_dir = project_dir / ".claude" / "agents"
    agents_dir.mkdir(parents=True, exist_ok=True)

    replacements = {"[Project]": project_name}
    for agent_file in (TEMPLATES_DIR / "agents").glob("*.md"):
        copy_and_replace(agent_file, agents_dir / agent_file.name, replacements)
        print(f"  - {agent_file.name}")
    print("  DONE")


def copy_hooks(project_dir: Path) -> None:
    """Copy Node.js hooks."""
    print("\n[3/6] Copying hooks...")
    hooks_dir = project_dir / ".claude" / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)

    for hook_file in (TEMPLATES_DIR / "hooks").glob("*.cjs"):
        shutil.copy2(hook_file, hooks_dir / hook_file.name)
        print(f"  - {hook_file.name}")
    print("  DONE")


def copy_rules_and_skills(project_dir: Path, with_rules: bool) -> None:
    """Copy beads-workflow rule, project-discovery skill, and optional dev rules."""
    print("\n[4/6] Copying rules and skills...")
    rules_dir = project_dir / ".claude" / "rules"
    rules_dir.mkdir(parents=True, exist_ok=True)

    # Always copy beads workflow
    beads_src = TEMPLATES_DIR / "rules" / "beads-workflow.md"
    if beads_src.exists():
        shutil.copy2(beads_src, rules_dir / "beads-workflow.md")
        print("  - rules/beads-workflow.md")

    # Optional dev rules
    if with_rules:
        for rule_file in (TEMPLATES_DIR / "rules").glob("*.md"):
            if rule_file.name != "beads-workflow.md":
                shutil.copy2(rule_file, rules_dir / rule_file.name)
                print(f"  - rules/{rule_file.name}")

    # Project discovery skill
    skills_dir = project_dir / ".claude" / "skills"
    skill_src = TEMPLATES_DIR / "skills" / "project-discovery"
    if skill_src.exists():
        dest = skills_dir / "project-discovery"
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(skill_src, dest)
        print("  - skills/project-discovery/")

    print("  DONE")


def copy_settings_and_claude_md(project_dir: Path, project_name: str) -> None:
    """Copy settings.json (merge hooks) and CLAUDE.md (append if exists)."""
    print("\n[5/6] Copying settings and CLAUDE.md...")

    # --- settings.json: merge hooks into existing ---
    settings_dest = project_dir / ".claude" / "settings.json"
    settings_src = TEMPLATES_DIR / "settings.json"
    if settings_src.exists():
        new_settings = json.loads(settings_src.read_text())
        if settings_dest.exists():
            try:
                existing = json.loads(settings_dest.read_text())
                # Merge hooks by event type
                for event, hooks_list in new_settings.get("hooks", {}).items():
                    existing.setdefault("hooks", {}).setdefault(event, [])
                    existing_commands = {
                        h["hooks"][0]["command"]
                        for h in existing["hooks"][event]
                        if h.get("hooks") and h["hooks"][0].get("command")
                    }
                    for hook in hooks_list:
                        cmd = hook.get("hooks", [{}])[0].get("command", "")
                        if cmd not in existing_commands:
                            existing["hooks"][event].append(hook)
                settings_dest.write_text(json.dumps(existing, indent=2) + "\n")
                print("  - settings.json (merged hooks)")
            except Exception:
                shutil.copy2(settings_src, settings_dest)
                print("  - settings.json (replaced — could not merge)")
        else:
            settings_dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(settings_src, settings_dest)
            print("  - settings.json")

    # --- CLAUDE.md: append beads section if file exists ---
    claude_dest = project_dir / "CLAUDE.md"
    claude_src = TEMPLATES_DIR / "CLAUDE.md"
    if claude_src.exists():
        beads_content = claude_src.read_text().replace("[Project]", project_name)
        if claude_dest.exists():
            existing_content = claude_dest.read_text()
            if "## Workflow" in existing_content and "beads" in existing_content.lower():
                print("  - CLAUDE.md (already has beads section, skipped)")
            else:
                separator = "\n\n---\n\n# Beads Orchestration\n\n"
                with open(claude_dest, "a") as f:
                    f.write(separator + beads_content)
                print("  - CLAUDE.md (appended beads section)")
        else:
            claude_dest.write_text(beads_content)
            print("  - CLAUDE.md (created)")

    print("  DONE")


def setup_gitignore(project_dir: Path) -> None:
    """Ensure .beads/ is in .gitignore."""
    print("\n[6/6] Setting up .gitignore...")
    gitignore_path = project_dir / ".gitignore"
    entries = [".beads/", ".worktrees/"]

    if gitignore_path.exists():
        content = gitignore_path.read_text()
        missing = [e for e in entries if e not in content and e.rstrip("/") not in content]
        if missing:
            with open(gitignore_path, "a") as f:
                if content and not content.endswith("\n"):
                    f.write("\n")
                f.write("\n# Beads orchestration\n")
                for entry in missing:
                    f.write(f"{entry}\n")
                    print(f"  - Added {entry}")
        else:
            print("  - Already configured")
    else:
        gitignore_path.write_text("# Beads orchestration\n.beads/\n.worktrees/\n")
        print("  - Created .gitignore")

    print("  DONE")


# ============================================================================
# MAIN
# ============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(description="Bootstrap beads orchestration")
    parser.add_argument("--project-name", default=None, help="Project name (auto-inferred if not provided)")
    parser.add_argument("--project-dir", default=".", help="Project directory")
    parser.add_argument("--with-rules", action="store_true", help="Also copy dev rules (implementation-standard, logging, tdd)")
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    project_dir.mkdir(parents=True, exist_ok=True)

    project_name = args.project_name or infer_project_name(project_dir)
    print(f"\nBootstrapping beads orchestration for: {project_name}")
    print(f"Directory: {project_dir}")
    print("=" * 60)

    if not TEMPLATES_DIR.exists():
        print(f"\nERROR: Templates not found: {TEMPLATES_DIR}")
        sys.exit(1)

    if not install_beads(project_dir):
        sys.exit(1)

    copy_agents(project_dir, project_name)
    copy_hooks(project_dir)
    copy_rules_and_skills(project_dir, args.with_rules)
    copy_settings_and_claude_md(project_dir, project_name)
    setup_gitignore(project_dir)

    print("\n" + "=" * 60)
    print("BOOTSTRAP COMPLETE")
    print("=" * 60)
    print(f"""
Next steps:

1. Restart Claude Code to load hooks and agents
2. Run /project-discovery to extract project conventions
3. Create your first bead: bd create "Task" -d "Description"
4. Dispatch work: Task(subagent_type="general-purpose", prompt="BEAD_ID: ...")
""")


if __name__ == "__main__":
    main()
