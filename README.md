# Trade-MCP - Foreign-trade CRM MCP Server

A foreign-trade customer relationship management system implemented as an
MCP (Model Context Protocol) server. Provides tools for customer management,
email records, and database operations.

> **Distribution model**
> - **Source code** lives in a **private** repository (`baolin1389/trade-source`).
> - **Prebuilt binaries + install script** are published to a **public**
>   repository (`baolin1389/trade-runtime`).
> - Clients (Hermes / OpenClaw / Claude Desktop) only ever talk to the
>   public runtime repo; the source tree is never distributed.

## One-Line Installation (recommended for AI agents)

```bash
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/install.sh | bash
```

The script reads `manifest.json` from the public runtime repo, downloads
`runtime-last.tar.gz`, verifies its sha256, and installs to
`/opt/trade-mcp` with a symlink at `/usr/local/bin/trade-mcp`.

**Pinned installation:**
```bash
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/install.sh | bash -s -- v0.4.0
```

**Custom prefix:**
```bash
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/install.sh | bash -s -- --prefix ~/.local/trade-mcp
```

## Upgrade Instructions

### Using the upgrade script (recommended)

```bash
# One-line upgrade (preserves all data automatically)
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash
```

The upgrade script:
- ✅ Automatically backs up your database before upgrade
- ✅ Preserves all data in `data/` directory
- ✅ Preserves your custom config modifications
- ✅ Detects and stops running instances
- ✅ Verifies sha256 of downloaded tarball
- ✅ Creates rollback backup file

**Upgrade options:**
```bash
# Upgrade to specific version
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash -s -- v0.4.2

# Custom installation directory
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash -s -- --prefix ~/.local/trade-mcp

# Skip automatic backup (if you already backed up)
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash -s -- --no-backup

# Force reinstall same version
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/upgrade.sh | bash -s -- --force
```

### Manual upgrade from v0.3.x or earlier

```bash
# Stop any running instances first
pkill trade-mcp 2>/dev/null || true

# Backup your database before upgrade
/opt/trade-mcp/bin/trade-mcp << 'EOF'
{"method":"tools/call","params":{"name":"database_backup","arguments":{"name":"pre_upgrade_0.4"}}}
EOF

# Re-run the install script to get the latest version
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/install.sh | bash

# Verify upgrade
cat /opt/trade-mcp/VERSION
```

### Upgrading from v0.4.x (in-place upgrade)

```bash
# For minor version upgrades, just re-run install.sh
# It will preserve your data/ directory automatically
curl -fsSL https://raw.githubusercontent.com/baolin1389/trade-runtime/master/install.sh | bash
```

**What gets preserved during upgrade:**
- ✅ `data/` directory (database + backups)
- ✅ Customized `config/` files
- ❌ Built-in resources/prompts/skills are overwritten with latest versions

## Breaking Changes

### v0.4.0 → v0.4.2
- **Response format changed**: Tools now return MCP-standard `{"content": [{"type": "text", "text": "..."}]}` format instead of `{"result": {...}}`. This may require client updates for proper parsing.
- **business_category enum updated**: Changed from `zero_point / angle_head / checking_fixture` to `importer / distributor / wholesaler / retailer / brand_owner / oem_manufacturer / trading_company`. Existing data with old values will still work but may need migration.

### v0.3.x → v0.4.0
- **Database backup format**: Backups are now stored in `data/backups/` instead of `backups/`
- **Configuration location**: Config files moved from `./` to `config/` directory

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

## Available Tools (24 total)

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

### System (6)
| Tool | Required Params |
|------|-----------------|
| `system_validate_email` | `email` |
| `system_check_brand_rejection` | `company_name` |
| `system_list_rejected_brands` | - |
| `system_get_send_window` | - (optional: `country`) |
| `system_get_email_limits` | - |
| `system_get_next_sendable_email` | - |

### Database (5)
| Tool | Required Params |
|------|-----------------|
| `database_backup` | - (optional: `name`) |
| `database_restore` | `name` |
| `database_cleanup_backups` | - (optional: `retention_days`, `keep_count`) |
| `database_migrate` | - |
| `database_get_migration_status` | - |

## Business Rules

- Customer uniqueness: `(company_name, country)` — attempting to create a duplicate will return an error.
- Max 5 emails per customer; max 3 sends per email; min 7 days between sends to the same email.
- Email addresses are globally unique across all customers.
- `email_address` passes both format validation and MX record check.
- `sender_account` passes format validation.
- `country` must be one of the keys in the `send_window_mapping` (see below).
- Backups: default 30-day retention, keep at least 5.
- Restore creates a `pre_restore_*.db` safety copy before overwriting.
- Engine-level guard: any UPDATE/DELETE statement without a WHERE clause is rejected — even if it bypasses application-level validation.
- State machine: customers in `pending_development` can transition to `in_progress`, `excluded`, or `no_email`. The other three states are terminal.

### Send Window Format

The `send_window` field uses **Beijing Time (UTC+8)** with the format `HH:MM-HH:MM` (24-hour format):

| Format | Example | Meaning |
|--------|---------|---------|
| Normal | `09:00-18:00` | 09:00 to 18:00 same day |
| Overnight | `17:00-01:00` | 17:00 to 01:00 next day (spans midnight) |

**Rules:**
- Start time `<` end time = normal window (same day)
- Start time `>` end time = overnight window (crosses midnight)
- Start time `=` end time = invalid
- Hours: 0-23, Minutes: 0-59
- Leading zeros required (e.g. `08:00` not `8:0`)

On `customer_create`, the `country` field is looked up in the `send_window_mapping` table (see next section) and the resulting Beijing-time window is auto-set into email records when `send_window` is omitted.

### Country / Send Window Mapping

The full mapping lives in `config/default.yaml` under `send_window_mapping`. It includes 100+ countries/regions across Asia-Pacific, the Middle East, Europe, North & South America, and Africa.

A non-exhaustive list of common entries:

| Country / Region | Window (Beijing time) | Notes |
|------------------|----------------------|-------|
| `China` | 09:00-18:00 | default for the office TZ |
| `Japan` | 08:00-17:00 | JST (UTC+9) |
| `South Korea` | 08:00-17:00 | KST (UTC+9) |
| `Singapore` | 09:00-18:00 | SGT (UTC+8) |
| `Hong Kong` | 09:00-18:00 | HKT (UTC+8) |
| `Taiwan` | 09:00-18:00 | CST (UTC+8) |
| `India` | 11:30-20:30 | IST (UTC+5:30) |
| `United Kingdom` | 17:00-01:00 | BST overnight |
| `Germany` | 15:00-00:00 | CEST overnight |
| `France` | 15:00-00:00 | CEST overnight |
| `Spain` | 15:00-00:00 | CEST overnight |
| `Sweden` | 15:00-00:00 | CEST overnight |
| `Finland` | 14:00-23:00 | EEST |
| `Russia (Moscow)` | 14:00-23:00 | MSK |
| `United States (Eastern)` | 21:00-05:00 | EDT overnight |
| `United States (Pacific)` | 00:00-09:00 | PDT overnight |
| `Canada (Eastern)` | 21:00-05:00 | EDT |
| `Mexico` | 23:00-08:00 | CDT |
| `Brazil (Brasília)` | 20:00-05:00 | BRT |
| `UAE` | 13:00-22:00 | GST (UTC+4) |
| `Saudi Arabia` | 14:00-23:00 | AST |
| `Turkey` | 14:00-23:00 | TRT |
| `Australia (Sydney)` | 07:00-16:00 | AEST |
| `Australia (Perth)` | 09:00-18:00 | AWST (UTC+8) |
| `New Zealand` | 05:00-14:00 | NZST |
| `Egypt` | 14:00-23:00 | EET |
| `South Africa` | 13:00-22:00 | SAST |
| `default` | 17:00-01:00 | fallback when country is not listed |

To get the complete list programmatically, call `system_get_send_window` with a specific country, or read `config/default.yaml`.

## Error Messages & How to Fix Them

All tools return `{"content": [{"type": "text", "text": "Error: <reason and guidance>"}]` on failure. The engine also returns structured `{"success": false, "error": "..."}` that the MCP formatter wraps into the text payload.

### Customer errors

| Scenario | Error text | Fix |
|----------|-----------|-----|
| `company_name` missing | `company_name is required. How to fix: pass a non-empty string for company_name.` | Add `company_name` parameter |
| `country` missing | `country is required. How to fix: ... country value must be one of the known countries in send_window_mapping ...` | Add a valid `country` value |
| `country` invalid | `Invalid country: 'XYZ'. The country field must match an entry in send_window_mapping. Valid options: China, Germany, ... How to fix: pick a value from the list above, or call system_get_send_window(country=...) to look up.` | Use the exact country name from the mapping; call `system_get_send_window` to validate. |
| `company_name` is a rejected brand | `Company 'XYZ' rejected due to brand rules. How to fix: use a different company name or check the rejected_brands list via system_list_rejected_brands.` | See `system_list_rejected_brands` output. |
| Uniqueness violation | `Company 'XYZ' in country 'Z' already exists (uniqueness constraint: company_name + country must be unique). How to fix: use customer_update on the existing record (id=N) or change the company_name/country.` | Update the existing record or adjust fields. |
| Customer not found on update/delete | `Customer not found (id=N). How to fix: verify the id by calling customer_list or customer_query.` | Query the customer first to obtain the correct id. |
| 🚫 Update without id | `🚫 RED LINE: id is required. customer_update WITHOUT a specific record id is NOT allowed. Bulk / unconditional updates are blocked to prevent accidental data corruption. How to fix: pass the integer id of the customer you want to update. If you need to update multiple records, use customer_batch_update with an explicit ids list.` | Always pass an `id` on update/delete. |
| 🚫 Delete without id | Similar to above, but says `customer_delete WITHOUT a specific record id is NOT allowed ...` | Always pass an `id` on delete. |
| 🚫 Batch update without ids | `🚫 RED LINE: ids list is required. customer_batch_update WITHOUT an explicit ids list is NOT allowed ...` | Pass a non-empty list like `ids: [1,2,3]`. |
| Invalid status transition | `Invalid transition from 'in_progress' to 'pending_development'. Valid transitions from 'in_progress': []. How to fix: pick a valid target status ... Note: 'excluded' and 'no_email' are terminal. Valid statuses: pending_development, in_progress, excluded, no_email.` | Review the state machine rules above. |

### Email record errors

| Scenario | Error text | Fix |
|----------|-----------|-----|
| `customer_id` missing | `customer_id is required. How to fix: pass the integer id of the customer this email belongs to.` | Provide `customer_id`. |
| `email_address` invalid format/MX | `Invalid email_address: ... How to fix: ensure the email has a valid format and its domain has an MX record.` | Correct the email or try a different address. |
| `sender_account` invalid format | `Invalid sender_account: 'xyz' must be a valid email address format. How to fix: pass something like 'outreach@yourdomain.com'.` | Provide a properly formatted sender address. |
| Email address duplicate | `Email address 'a@b.com' already exists (id=N). Uniqueness constraint: each email_address can only appear once.` | Use a different email or update the existing record. |
| Customer not found | `Customer not found (id=N). How to fix: create the customer first via customer_create, or verify the id with customer_list.` | Create the customer first or correct the id. |
| Too many emails per customer | `Customer already has N email records, which exceeds the max_per_customer=5 limit. How to fix: pick a different customer_id, or delete an existing email record first.` | Use another customer or prune emails. |
| Max send count reached | `Email has reached max_send_count=3 sends already (current=3). How to fix: this email is done; pick a different email address.` | Choose a different email. |
| Min interval not passed | `Email was last sent at ... Minimum interval not yet passed (min_send_interval_days=7). How to fix: wait until enough days have passed, or use system_get_next_sendable_email.` | Wait for the cooldown, or use a different email. |
| Terminal email status | `Cannot increment send count: email status is 'bounced'. How to fix: emails marked as bounced or replied are not eligible for further sends; use email_record_update to change status if this is a mistake.` | Either correct the status, or move on to another email. |

### Database errors

| Scenario | Error text | Fix |
|----------|-----------|-----|
| Backup name exists | `Backup 'backup_xxx.db' already exists` | Choose another custom `name` or omit to use timestamp-based naming. |
| Backup file not found | `Backup file not found: backup_xxx.db` | Check the available backups in `data/backups/`. |
| 🚫 Engine-level SQL guard | Runtime error raised from SQLAlchemy: `SAFETY BLOCKED: ... UPDATE/DELETE without WHERE clause is not allowed.` | This fires only if a raw SQL bypasses application-layer validation. All supported tools (`customer_update`, `customer_delete`, `customer_batch_update`, `email_record_update`, `email_record_delete`, `email_record_batch_update`) already reject calls without ids. Use the documented tools with proper ids. |

### Workflow for AI Agents

1. Before creating a customer: call `system_list_rejected_brands` to avoid brand rejections.
2. Choose `country` from the `send_window_mapping` table in `config/default.yaml`, or use `system_get_send_window` to check.
3. After customers exist, call `system_get_email_limits` to understand capacity (5 emails / customer, 3 sends / email, 7-day cooldown).
4. Before creating emails, call `system_validate_email` to make sure the address passes format + MX.
5. To schedule, call `system_get_next_sendable_email` for a sendable record. The return includes the send window and minutes to wait.

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

## Changelog

### v0.5.2 (2026-06-18)
- **sender_account guard strengthened**: email_record_create now requires sender_account and validates it as a proper email address format before writing. Empty, malformed, or placeholder values (e.g. "default", "sender@domain") will be rejected with a clear error. The sender account itself is managed by your business system — the MCP layer only enforces that it is a valid email format.

### v0.5.1 (2026-06-18)
- **email_status enum enforcement**: email_record_create, email_record_update, and email_record_batch_update now validate that email_status is one of: active | bounced | done | replied. Invalid values are rejected with a clear error listing the valid options.
- **send_window format enforcement**: all three email write methods now validate the send_window format (HH:MM-HH:MM, leading zeros required, start ≠ end). Invalid formats are rejected before touching the database.
- **MCP tool descriptions updated**: email_record_create/update/batch_update tool descriptions in mcp_server.py now list all enforced constraints (email_status enum, send_window format, sender_account format) so AI agents understand the rules before calling.

### v0.5.0 (2026-06-18)
- **Error messages standardised**: every business-rule failure now returns a clear, AI-parseable message that includes the violation reason, the valid options (where applicable), and a "How to fix:" guidance block.
- **Country validation strengthened**: customer_create and customer_update now reject invalid country values with a full list of the valid send_window_mapping keys and a pointer to system_get_send_window.
- **email_record_increment_send now validates email_status and min interval**: active, under-max-send-count, and past the 7-day cooldown are all checked before the count is incremented.
- **RED LINE branding on update/delete without id**: customer_update / customer_delete / email_record_update / email_record_delete / customer_batch_update / email_record_batch_update explicitly return `"🚫 RED LINE: ... is NOT allowed"` when the required id or ids list is missing.
- **MCP tool descriptions expanded**: every tool now documents the enforced constraints, accepted statuses, and safety guards so that AI agents read them before calling.

### v0.4.16 (2026-06-17)
- Added send_window_mapping country validation to customer_create and customer_update.
- Introduced config_loader.get_valid_countries() for AI-parsable lookups.

### v0.4.15 (2026-06-17)
- send_window auto-populates from country on email_record_create when caller omits the field.

### v0.4.14 (2026-06-17)
- Reworked send_window_mapping to 100+ countries/regions from UTC-12 to UTC+12.

### v0.4.10 (2026-06-17)
- NullPool + session cleanup fixes rapid-request connection exhaustion.

### v0.4.9 (2026-06-17)
- import validate_email_format missing bug fixed.

### v0.4.2 (2026-06-16)
- **MCP Protocol Compliance**: All tool responses now follow MCP standard format `{"content": [{"type": "text", "text": "..."}]}`
- **business_category updated**: Changed to foreign-trade roles: `importer`, `distributor`, `wholesaler`, `retailer`, `brand_owner`, `oem_manufacturer`, `trading_company`
- **customer_query fixed**: Now uses case-insensitive matching for country/company_name filters
- **MX record validation fixed**: Properly validates email domain MX records
- **State transition errors**: Now returns clear error messages for invalid transitions (e.g., same state)
- **New tool**: `system_list_rejected_brands()` - lists all brands in the rejection list
- **Database timestamps**: All customer records now include `created_at` and `updated_at` fields

### v0.4.1 (2026-06-16)
- trade-source / trade-runtime split
- One-line installer
- Manifest-based versioning

### v0.4.0 (2026-06-16)
- Security: Engine-level BLOCK of UPDATE/DELETE without WHERE
- Backup/restore/cleanup tools
- Email send limits and windows
- State machine for customer status
