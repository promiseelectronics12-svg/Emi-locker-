# Capsule MCP Setup

This project is configured to expose Capsule as an MCP server for IDEs and AI coding tools.

## Installed packages

- Global CLI: `@capsule-run/cli`
- Project SDK dependency: `@capsule-run/sdk`
- Project MCP server dependency: `@capsule-run/mcp-server`

## Server command

```bash
npx -y @capsule-run/mcp-server
```

## Project config files

- `.mcp.json` for project-level MCP clients that support the common `mcpServers` format.
- `.cursor/mcp.json` for Cursor.
- `.windsurf/mcp_config.json` for Windsurf-style project config.
- `.vscode/mcp.json` for VS Code MCP clients.

## Manual client command

For clients that do not read project files automatically, add a server named `capsule` with:

```json
{
  "command": "npx",
  "args": ["-y", "@capsule-run/mcp-server"]
}
```

The public MCP server listing for Capsule uses:

```bash
npx -y @capsule-run/mcp-server
```
