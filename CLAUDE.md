# ROI CRM

## Overview
Hebrew RTL CRM system for ROI business. Single-page app in `ROI CRM.html` with vanilla JS, localStorage persistence, and WhatsApp OTP authentication via Green API.

## Architecture
- **Frontend**: Single HTML file with inline CSS + JS (~886 lines)
- **Backend**: Python static file server (`serve.py`) for Railway deployment
- **Storage**: Browser localStorage (`roicrm_data` key)
- **Auth**: WhatsApp OTP via Green API, session stored in `sessionStorage`
- **Deployment**: Railway via Dockerfile

## Modules
| Module | DB Key | Hebrew |
|--------|--------|--------|
| Leads | `leads` | מתעניינים |
| Deals | `deals` | עסקאות |
| Clients | `clients` | לקוחות |
| Payments | `payments` | תשלומים |
| Products | `products` | מוצרים |
| Meetings | `meetings` | פגישות |
| Tasks | `tasks` | משימות |

## Users (hardcoded)
- **roi** (admin): רועי עובדיה - ID 318686540
- **natan** (agent): נתן - ID 211870100
- **ben** (agent): בן - ID 322230731

## Key Functions
- `renderLeadFields(r, container)` / `renderDealFields(r, container)` etc. — Record detail views
- `fv(key, label, val, opts)` — Universal field value renderer with types: text, select, date, phone, email, link, checkbox, textarea
- `saveRecord()` / `saveRS()` — Persist record changes to localStorage
- `openRecord(type, id, push)` — Open record detail panel with breadcrumb navigation
- `relSec(...)` — Render related records section with add button

## Permissions
- **admin**: Full CRUD, export, user management
- **agent**: Create leads/deals/clients/payments/meetings/tasks, no delete/export/user management

## Running Locally
```bash
python3 serve.py  # Serves on port 8080
```

## Known Issues
- `renderRight()` calls field renderers (e.g., `renderLeadFields(r)`) without passing container element — some renderers expect a `container` parameter but it's not used in `renderRight()` return pattern
- `updateField(key, val)` doesn't use DOM selectors matching the `fv()` generated IDs (`fld_*`)
- `renderPage_silent` returns HTML but `renderPage` sets innerHTML directly — the auto-refresh override is incomplete
- No backend database — all data is in browser localStorage (lost on clear)
