"""Provider clients for invoking agents via Codex, Gemini, etc."""

import asyncio
import logging
import os
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

logger = logging.getLogger(__name__)


class RateLimitError(Exception):
    """Raised when a provider hits rate limits."""
    pass


@dataclass
class InvokeResult:
    """Result of a provider invocation."""
    success: bool
    response: str
    provider: str
    error: Optional[str] = None


class ProviderClient(ABC):
    """Abstract base class for AI provider clients."""

    name: str = "base"

    @abstractmethod
    async def invoke(self, prompt: str) -> str:
        """Invoke the provider with a prompt."""
        pass

    def is_rate_limit_error(self, error_msg: str) -> bool:
        """Check if error message indicates rate limiting."""
        rate_limit_indicators = [
            "rate limit",
            "429",
            "too many requests",
            "usage limit",
            "quota exceeded",
        ]
        error_lower = error_msg.lower()
        return any(indicator in error_lower for indicator in rate_limit_indicators)


class CodexClient(ProviderClient):
    """Client for OpenAI Codex."""

    name = "codex"

    # Map agent model preferences to Codex models
    MODEL_MAPPING = {
        "haiku": "gpt-5.1-codex-mini",
        "sonnet": "gpt-5.2-codex",
        "opus": "gpt-5.1-codex-max",
    }

    def __init__(self, model: str = "gpt-5.2-codex"):
        self.model = model

    @classmethod
    def map_model(cls, agent_model: str) -> str:
        """Map agent's preferred model to Codex model."""
        return cls.MODEL_MAPPING.get(agent_model, "gpt-5.2-codex")

    async def invoke(self, prompt: str) -> str:
        """Invoke Codex with prompt."""
        cmd = [
            "codex",
            "exec",
            "-m", self.model,
            "--sandbox", "workspace-write",
            prompt,
        ]

        logger.info(f"[Codex] Invoking with model: {self.model}")

        try:
            cwd = os.getcwd()
            env = os.environ.copy()

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
                cwd=cwd,
            )

            stdout, stderr = await process.communicate()

            if process.returncode != 0:
                error_msg = stderr.decode() if stderr else "Unknown error"
                if self.is_rate_limit_error(error_msg):
                    raise RateLimitError(f"Codex rate limit: {error_msg}")
                raise RuntimeError(f"Codex failed: {error_msg}")

            response = stdout.decode().strip()
            logger.info(f"[Codex] Response length: {len(response)} chars")
            return response

        except FileNotFoundError:
            raise RuntimeError("Codex CLI not found. Install with: codex login")


class GeminiClient(ProviderClient):
    """Client for Google Gemini."""

    name = "gemini"
    model = "gemini-2.5-flash-preview"

    async def invoke(self, prompt: str) -> str:
        """Invoke Gemini with prompt."""
        cmd = [
            "gemini",
            "-p", prompt,
            "-m", self.model,
        ]

        logger.info(f"[Gemini] Invoking with model: {self.model}")

        try:
            cwd = os.getcwd()
            env = os.environ.copy()

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
                cwd=cwd,
            )

            stdout, stderr = await process.communicate()

            if process.returncode != 0:
                error_msg = stderr.decode() if stderr else "Unknown error"
                if self.is_rate_limit_error(error_msg):
                    raise RateLimitError(f"Gemini rate limit: {error_msg}")
                raise RuntimeError(f"Gemini failed: {error_msg}")

            response = stdout.decode().strip()
            logger.info(f"[Gemini] Response length: {len(response)} chars")
            return response

        except FileNotFoundError:
            raise RuntimeError("Gemini CLI not found. Install with: pip install gemini-cli")


class ProviderChain:
    """Chain of providers with fallback support."""

    def __init__(self, providers: list[ProviderClient], allow_skip: bool = False):
        """
        Initialize provider chain.

        Args:
            providers: List of providers to try in order
            allow_skip: If True, return skip message when all providers fail
        """
        self.providers = providers
        self.allow_skip = allow_skip

    async def invoke(
        self,
        system_prompt: str,
        user_prompt: str,
        task_id: Optional[str] = None,
    ) -> InvokeResult:
        """
        Invoke providers in chain until one succeeds.

        Returns:
            InvokeResult with success status, response, and provider used
        """
        combined_prompt = f"{system_prompt}\n\n---\n\n{user_prompt}"
        if task_id:
            combined_prompt = f"TASK_ID: {task_id}\n\n{combined_prompt}"

        errors = []

        for provider in self.providers:
            try:
                logger.info(f"Trying provider: {provider.name}")
                response = await provider.invoke(combined_prompt)
                return InvokeResult(
                    success=True,
                    response=response,
                    provider=provider.name,
                )
            except RateLimitError as e:
                logger.warning(f"{provider.name} rate limited: {e}")
                errors.append(f"{provider.name}: rate limited")
                continue
            except RuntimeError as e:
                logger.error(f"{provider.name} failed: {e}")
                errors.append(f"{provider.name}: {e}")
                continue

        # All providers failed
        if self.allow_skip:
            return InvokeResult(
                success=True,  # Skip is a valid outcome
                response="SKIPPED: All providers rate limited. Task skipped.",
                provider="skip",
                error="; ".join(errors),
            )

        return InvokeResult(
            success=False,
            response="",
            provider="none",
            error=f"All providers failed: {'; '.join(errors)}",
        )


def create_provider_chain(agent_model: str, agent_name: str) -> ProviderChain:
    """
    Create a provider chain for an agent.

    Args:
        agent_model: Agent's preferred model (haiku, sonnet, opus)
        agent_name: Name of the agent (for skip logic)

    Returns:
        ProviderChain configured for the agent
    """
    codex_model = CodexClient.map_model(agent_model)

    providers = [
        CodexClient(model=codex_model),
        GeminiClient(),
    ]

    # Code reviewer can be skipped if all providers fail
    allow_skip = agent_name == "code-reviewer"

    return ProviderChain(providers=providers, allow_skip=allow_skip)
