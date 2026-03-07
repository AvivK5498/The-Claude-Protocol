"""Tests for bootstrap.py — project name inference, copy_and_replace, setup_gitignore."""

import json
import sys
from pathlib import Path

import pytest

# Add project root to path so we can import bootstrap
sys.path.insert(0, str(Path(__file__).parent.parent))

from bootstrap import (
    infer_project_name,
    copy_and_replace,
    setup_gitignore,
    _from_package_json,
    _from_pyproject,
    _from_cargo,
    _from_go_mod,
    TEMPLATES_DIR,
)


# ============================================================================
# infer_project_name
# ============================================================================

class TestInferProjectName:
    def test_from_package_json(self, tmp_path):
        (tmp_path / "package.json").write_text(json.dumps({"name": "my-cool-app"}))
        assert infer_project_name(tmp_path) == "My Cool App"

    def test_from_package_json_with_scope(self, tmp_path):
        (tmp_path / "package.json").write_text(json.dumps({"name": "@org/my-package"}))
        assert infer_project_name(tmp_path) == "@Org/My Package"

    def test_from_package_json_underscores(self, tmp_path):
        (tmp_path / "package.json").write_text(json.dumps({"name": "my_cool_app"}))
        assert infer_project_name(tmp_path) == "My Cool App"

    def test_from_package_json_empty_name(self, tmp_path):
        (tmp_path / "package.json").write_text(json.dumps({"name": ""}))
        # Falls through to directory name
        result = infer_project_name(tmp_path)
        assert isinstance(result, str)
        assert len(result) > 0

    def test_from_package_json_malformed(self, tmp_path):
        (tmp_path / "package.json").write_text("not json {{{")
        # Falls through to directory name
        result = infer_project_name(tmp_path)
        assert isinstance(result, str)

    def test_from_go_mod(self, tmp_path):
        (tmp_path / "go.mod").write_text("module github.com/user/my-project\n\ngo 1.21\n")
        assert infer_project_name(tmp_path) == "My Project"

    def test_from_go_mod_simple_module(self, tmp_path):
        (tmp_path / "go.mod").write_text("module myapp\n")
        assert infer_project_name(tmp_path) == "Myapp"

    def test_fallback_to_directory_name(self, tmp_path):
        result = infer_project_name(tmp_path)
        # tmp_path has a generated name, but it should be titlecased
        assert isinstance(result, str)
        assert len(result) > 0

    def test_directory_name_dashes_to_spaces(self, tmp_path):
        project_dir = tmp_path / "my-awesome-project"
        project_dir.mkdir()
        assert infer_project_name(project_dir) == "My Awesome Project"

    def test_directory_name_underscores_to_spaces(self, tmp_path):
        project_dir = tmp_path / "my_awesome_project"
        project_dir.mkdir()
        assert infer_project_name(project_dir) == "My Awesome Project"

    def test_priority_package_json_over_go_mod(self, tmp_path):
        (tmp_path / "package.json").write_text(json.dumps({"name": "node-app"}))
        (tmp_path / "go.mod").write_text("module github.com/user/go-app\n")
        assert infer_project_name(tmp_path) == "Node App"


class TestFromPackageJson:
    def test_returns_none_when_missing(self, tmp_path):
        assert _from_package_json(tmp_path) is None

    def test_returns_none_for_empty_json(self, tmp_path):
        (tmp_path / "package.json").write_text("{}")
        assert _from_package_json(tmp_path) is None


class TestFromPyproject:
    def test_returns_none_when_missing(self, tmp_path):
        assert _from_pyproject(tmp_path) is None

    @pytest.mark.skipif(sys.version_info < (3, 11), reason="tomllib requires Python 3.11+")
    def test_reads_project_name(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text(
            '[project]\nname = "my-python-lib"\n'
        )
        assert _from_pyproject(tmp_path) == "My Python Lib"

    @pytest.mark.skipif(sys.version_info < (3, 11), reason="tomllib requires Python 3.11+")
    def test_reads_poetry_name(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text(
            '[tool.poetry]\nname = "poetry-project"\n'
        )
        assert _from_pyproject(tmp_path) == "Poetry Project"


class TestFromCargo:
    def test_returns_none_when_missing(self, tmp_path):
        assert _from_cargo(tmp_path) is None

    @pytest.mark.skipif(sys.version_info < (3, 11), reason="tomllib requires Python 3.11+")
    def test_reads_package_name(self, tmp_path):
        (tmp_path / "Cargo.toml").write_text(
            '[package]\nname = "rust-cli"\nversion = "0.1.0"\n'
        )
        assert _from_cargo(tmp_path) == "Rust Cli"


class TestFromGoMod:
    def test_returns_none_when_missing(self, tmp_path):
        assert _from_go_mod(tmp_path) is None

    def test_extracts_last_segment(self, tmp_path):
        (tmp_path / "go.mod").write_text("module github.com/org/my-service\n")
        assert _from_go_mod(tmp_path) == "My Service"


# ============================================================================
# copy_and_replace
# ============================================================================

class TestCopyAndReplace:
    def test_replaces_placeholder(self, tmp_path):
        source = tmp_path / "template.md"
        source.write_text("# [Project] Guide\n\nWelcome to [Project].")
        dest = tmp_path / "output" / "guide.md"

        copy_and_replace(source, dest, {"[Project]": "My App"})

        result = dest.read_text()
        assert result == "# My App Guide\n\nWelcome to My App."

    def test_creates_parent_dirs(self, tmp_path):
        source = tmp_path / "src.txt"
        source.write_text("content")
        dest = tmp_path / "a" / "b" / "c" / "file.txt"

        copy_and_replace(source, dest, {})

        assert dest.exists()
        assert dest.read_text() == "content"

    def test_multiple_replacements(self, tmp_path):
        source = tmp_path / "tmpl.txt"
        source.write_text("[Name] uses [Lang]")
        dest = tmp_path / "out.txt"

        copy_and_replace(source, dest, {"[Name]": "MyApp", "[Lang]": "Python"})

        assert dest.read_text() == "MyApp uses Python"

    def test_no_replacements(self, tmp_path):
        source = tmp_path / "tmpl.txt"
        source.write_text("unchanged content")
        dest = tmp_path / "out.txt"

        copy_and_replace(source, dest, {})

        assert dest.read_text() == "unchanged content"


# ============================================================================
# setup_gitignore
# ============================================================================

class TestSetupGitignore:
    def test_creates_gitignore_when_missing(self, tmp_path, capsys):
        setup_gitignore(tmp_path)

        gitignore = tmp_path / ".gitignore"
        assert gitignore.exists()
        content = gitignore.read_text()
        assert ".beads/" in content
        assert ".worktrees/" in content

    def test_appends_missing_entries(self, tmp_path, capsys):
        gitignore = tmp_path / ".gitignore"
        gitignore.write_text("node_modules/\n.env\n")

        setup_gitignore(tmp_path)

        content = gitignore.read_text()
        assert "node_modules/" in content
        assert ".env" in content
        assert ".beads/" in content
        assert ".worktrees/" in content

    def test_skips_when_already_configured(self, tmp_path, capsys):
        gitignore = tmp_path / ".gitignore"
        gitignore.write_text("node_modules/\n.beads/\n.worktrees/\n")

        setup_gitignore(tmp_path)

        content = gitignore.read_text()
        # Should not duplicate entries
        assert content.count(".beads/") == 1

    def test_adds_newline_if_missing(self, tmp_path, capsys):
        gitignore = tmp_path / ".gitignore"
        gitignore.write_text("node_modules/")  # no trailing newline

        setup_gitignore(tmp_path)

        content = gitignore.read_text()
        assert ".beads/" in content
        # Should have added a newline before the section
        assert "node_modules/\n" in content

    def test_detects_entries_without_trailing_slash(self, tmp_path, capsys):
        gitignore = tmp_path / ".gitignore"
        gitignore.write_text(".beads\n.worktrees\n")

        setup_gitignore(tmp_path)

        content = gitignore.read_text()
        # Should detect ".beads" matches ".beads/" and not add duplicate
        assert content.count("beads") == 1


# ============================================================================
# Templates directory
# ============================================================================

class TestTemplatesDir:
    def test_templates_dir_exists(self):
        assert TEMPLATES_DIR.exists(), f"Templates dir not found: {TEMPLATES_DIR}"

    def test_has_hooks(self):
        hooks_dir = TEMPLATES_DIR / "hooks"
        assert hooks_dir.exists()
        hooks = list(hooks_dir.glob("*.cjs"))
        assert len(hooks) >= 6  # At least 6 hook files

    def test_has_agents(self):
        agents_dir = TEMPLATES_DIR / "agents"
        assert agents_dir.exists()
        agents = list(agents_dir.glob("*.md"))
        assert len(agents) >= 2  # code-reviewer + merge-supervisor

    def test_has_settings_json(self):
        assert (TEMPLATES_DIR / "settings.json").exists()

    def test_has_claude_md(self):
        assert (TEMPLATES_DIR / "CLAUDE.md").exists()

    def test_has_beads_workflow_rule(self):
        assert (TEMPLATES_DIR / "rules" / "beads-workflow.md").exists()
