"""MCP server for delegating agents to AI providers with fallback support."""

import asyncio
import logging
import os
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

from .agent_loader import AgentLoader
from .provider_client import create_provider_chain

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize components
# AGENT_TEMPLATES_PATH should be set via .mcp.json env config
AGENT_TEMPLATES_PATH = os.getenv("AGENT_TEMPLATES_PATH", ".claude/agents")

agent_loader = AgentLoader(templates_path=AGENT_TEMPLATES_PATH)

# Initialize MCP server
app = Server("provider-delegator")

@app.list_tools()
async def list_tools() -> list[Tool]:
    """List available tools."""
    return [
        Tool(
            name="invoke_agent",
            description=(
                "Delegate a task to a specialized agent. "
                "Tries Codex first, falls back to Gemini if rate limited. "
                "Available agents: scout, detective, architect, scribe, code-reviewer. "
                "Agents have full MCP tool access (context7, vibe_kanban, playwright, github)."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "agent": {
                        "type": "string",
                        "enum": ["scout", "detective", "architect", "scribe", "code-reviewer"],
                        "description": "Which agent to invoke",
                    },
                    "task_prompt": {
                        "type": "string",
                        "description": "The task prompt/instructions for the agent",
                    },
                    "task_id": {
                        "type": "string",
                        "description": "Optional Kanban task ID (e.g., RCH-123) for tracking",
                    },
                },
                "required": ["agent", "task_prompt"],
            },
        )
    ]

@app.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent]:
    """Handle tool calls."""
    if name != "invoke_agent":
        raise ValueError(f"Unknown tool: {name}")

    agent_name = arguments["agent"]
    task_prompt = arguments["task_prompt"]
    task_id = arguments.get("task_id")

    logger.info(f"Invoking agent: {agent_name} (task_id: {task_id})")

    try:
        # Load agent template
        template = agent_loader.load_agent(agent_name)
        logger.info(f"Loaded template for {agent_name} (model: {template.model})")

        # Create provider chain with fallback support
        chain = create_provider_chain(
            agent_model=template.model,
            agent_name=agent_name,
        )

        # Invoke with fallback chain: Codex -> Gemini -> Skip (for code-reviewer)
        result = await chain.invoke(
            system_prompt=template.system_prompt,
            user_prompt=task_prompt,
            task_id=task_id,
        )

        if result.success:
            logger.info(f"Agent {agent_name} completed via {result.provider}")
            return [TextContent(
                type="text",
                text=result.response
            )]
        else:
            logger.error(f"Agent {agent_name} failed: {result.error}")
            return [TextContent(
                type="text",
                text=f"ERROR: {result.error}"
            )]

    except FileNotFoundError as e:
        error_msg = f"Agent template not found: {agent_name}. Error: {e}"
        logger.error(error_msg)
        return [TextContent(type="text", text=f"ERROR: {error_msg}")]

    except Exception as e:
        error_msg = f"Unexpected error invoking {agent_name}: {e}"
        logger.exception(error_msg)
        return [TextContent(type="text", text=f"ERROR: {error_msg}")]

async def main():
    """Run the MCP server."""
    logger.info("Starting MCP Provider Delegator")
    logger.info(f"Agent templates path: {AGENT_TEMPLATES_PATH}")
    logger.info("Fallback chain: Codex -> Gemini -> Skip (code-reviewer only)")

    async with stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options()
        )

def run():
    """Entry point for CLI."""
    asyncio.run(main())

if __name__ == "__main__":
    run()
