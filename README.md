# Trade-MCP - Foreign Trade CRM MCP Server

A foreign-trade customer relationship management system implemented as an
MCP (Model Context Protocol) server. Provides tools for customer
management, email records, and database operations.

> **Distribution model**
> - **Source code** lives in a **private** repository (`baolin1389/trade-source`).
> - **Prebuilt binaries + install script** are published to a **public**
>   repository (`baolin1389/trade-runtime`).
> - Clients (Hermes / OpenClaw / Claude Desktop) only ever talk to the
>   public runtime repo; the source tree is never distributed.

## One-Line Installation (recommended for AI agents)

```bash
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash
```

The script reads `manifest.json` from the public runtime repo, downloads
`runtime-last.tar.gz`, verifies its sha256, and installs to
`/opt/trade-mcp` with a symlink at `/usr/local/bin/trade-mcp`.

**Pinned installation:**
```bash
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash -s -- v0.4.0
```

**Custom prefix:**
```bash
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/main/install.sh | bash -s -- --prefix ~/.local/trade-mcp
```

## Configure your MCP client

After installation, add the binary to your MCP client config:

```json
{
  "mcpServers": {
    "trade-mcp": {
      "command": "/opt/trade-mcp/bin/trade-mcp",
      "args": []
    }
  }
}
```

Config file locations:
- **Claude Desktop (macOS):** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Claude Desktop (Windows):** `%APPDATA%\Claude\claude_desktop_config.json`
- **OpenClaw / Hermes:** use the built-in "install MCP server" command and
  paste the install URL above
- **VS Code:** in your MCP extension settings

## Features

- **Customer management**: create / list / get / update / delete / batch update / query / state transitions
- **Email records**: validated against format + MX, with send limits
- **State machine**: `pending_development → in_progress | excluded | no_email` (terminal)
- **Brand rejection**: configure `config/rejected_brands.yaml` to block companies
- **Database backup / restore / cleanup**: stored in `data/backups/`
- **Send windows**: per-country Beijing-time windows
- **Engine-level safety**: UPDATE/DELETE without a WHERE clause is hard-blocked

## Available Tools (23 total)

### Customer (8)
| Tool | Required Params |
|------|-----------------|
| `customer_create` | `company_name`, `country` |
| `customer_list` | - |
| `customer_get` | `id` |
| `customer_update` | `id` |
| `customer_delete` | `id` |
| `customer_batch_update` | `ids`, `updates` |
| `customer_query` | - |
| `customer_transition_status` | `id`, `new_status` |

### Email Record (8)
| Tool | Required Params |
|------|-----------------|
| `email_record_create` | `customer_id`, `company_name`, `email_address`, `sender_account` |
| `email_record_list` | - |
| `email_record_get` | `id` |
| `email_record_update` | `id` |
| `email_record_delete` | `id` |
| `email_record_batch_update` | `ids`, `updates` |
| `email_record_query` | - |
| `email_record_increment_send` | `id` |

### System (4)
| Tool | Required Params |
|------|-----------------|
| `system_validate_email` | `email` |
| `system_check_brand_rejection` | `company_name` |
| `system_get_send_window` | - (optional: `country`) |
| `system_get_email_limits` | - |

### Database (3)
| Tool | Required Params |
|------|-----------------|
| `database_backup` | - (optional: `name`) |
| `database_restore` | `name` |
| `database_cleanup_backups` | - (optional: `retention_days`, `keep_count`) |

## Business Rules

- Customer uniqueness: `(company_name, country)`
- Max 5 emails per customer; max 3 sends per email; min 7 days between sends
- Backups: default 30-day retention, keep at least 5
- Restore creates a `pre_restore_*.db` safety copy before overwriting
- Engine-level guard: any UPDATE/DELETE without WHERE is rejected

## Runtime Directory Layout

```
trade-mcp/
├── bin/trade-mcp         # compiled binary (Linux x86_64)
├── config/               # runtime config (default.yaml, rejected_brands.yaml)
├── resources/            # country mapping, email templates, industry keywords
├── prompts/              # AI prompt templates
├── skills/               # skill definitions
├── migrations/           # reserved for future schema migrations
├── data/                 # SQLite DB + backups (created at first run)
├── VERSION
├── README.md
├── USAGE.md
└── mcp.json              # MCP server manifest
```

## Build from source (private repo only)

The source tree (`baolin1389/trade-source`) is **not** meant to be cloned
by end users. If you have access:

```bash
pip install -r requirements.txt
pyinstaller --noconfirm src/mcp_server_linux.spec
# the binary lands in dist/trade-mcp/trade-mcp
```

Run tests:

```bash
PYTHONPATH=src python src/tests/test_safety_hooks.py
```

## License

MIT (binary distribution). Source code under separate terms.
