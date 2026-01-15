"""Agent template loader for reading .md files."""

import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import yaml


@dataclass
class AgentTemplate:
    """Represents a loaded agent template."""
    name: str
    model: str
    description: str
    tools: list[str]
    system_prompt: str
    skills: Optional[list[str]] = None


class AgentLoader:
    """Loads agent templates from .md files."""

    def __init__(self, templates_path: str):
        """
        Initialize loader.

        Args:
            templates_path: Path to directory containing agent .md files
        """
        self.templates_path = Path(templates_path)
        if not self.templates_path.exists():
            raise FileNotFoundError(f"Templates path not found: {templates_path}")

    def load_agent(self, agent_name: str) -> AgentTemplate:
        """
        Load agent template from .md file.

        Args:
            agent_name: Name of agent (e.g., "scout", "detective")

        Returns:
            AgentTemplate with parsed frontmatter and system prompt

        Raises:
            FileNotFoundError: If agent .md file doesn't exist
            ValueError: If frontmatter is invalid
        """
        agent_file = self.templates_path / f"{agent_name}.md"

        if not agent_file.exists():
            raise FileNotFoundError(f"Agent template not found: {agent_file}")

        content = agent_file.read_text()

        # Parse frontmatter (YAML between --- markers)
        frontmatter_match = re.match(r'^---\n(.*?)\n---\n(.*)$', content, re.DOTALL)

        if not frontmatter_match:
            raise ValueError(f"Invalid agent template (missing frontmatter): {agent_file}")

        frontmatter_yaml = frontmatter_match.group(1)
        system_prompt = frontmatter_match.group(2).strip()

        try:
            frontmatter = yaml.safe_load(frontmatter_yaml)
        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML frontmatter in {agent_file}: {e}")

        return AgentTemplate(
            name=frontmatter["name"],
            model=frontmatter["model"],
            description=frontmatter["description"],
            tools=frontmatter.get("tools", []),
            skills=frontmatter.get("skills"),
            system_prompt=system_prompt,
        )
