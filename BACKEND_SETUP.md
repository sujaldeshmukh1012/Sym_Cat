# CAT Inspect Backend Setup

This file shows exactly where to put API endpoints and keys for the current app backend integration.

## 1) Supabase URL + Keys (required)

Do not hardcode secrets in Swift files.

Create:
- `.env` in repo root (`/Users/sujalbhakare/Projects/Sym_Cat/.env`)

Template:
- copy `.env.example` to `.env`

Add these keys in `.env`:

```dotenv
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_KEY=YOUR_SUPABASE_KEY
PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
SUPABASE_BUCKET_NAME=inspection_key
SUPABASE_S3_ENDPOINT=https://YOUR_PROJECT.storage.supabase.co/storage/v1/s3
SUPABASE_S3_ACCESS_KEY=YOUR_S3_ACCESS_KEY
SUPABASE_S3_SECRET_KEY=YOUR_S3_SECRET_KEY
SUPABASE_S3_REGION=us-west-2
CAT_BACKEND_API_URL=http://127.0.0.1:8000
```

Code reads keys from:
1. Process environment variables
2. `.env` file (root/bundle/documents fallback)

Loader location:
- `CAT Inspect/CAT Inspect/Services/InspectionAPI.swift`
- `SupabaseConfig` + `DotEnv`

Where each key is used:
- `SUPABASE_URL`, `SUPABASE_KEY`: iOS app REST calls + storage uploads
- `SUPABASE_BUCKET_NAME`: iOS task-image uploads path target
- `CAT_BACKEND_API_URL`: iOS report submit calls `POST /reports/generate/{inspection_id}?run_async=false`
- `SUPABASE_S3_*`: Python API router uploads generated PDF to Supabase S3 endpoint

## 2) Which endpoints are being called right now

The app builds endpoints automatically from `baseURL`:
- `GET/POST/PATCH {baseURL}/rest/v1/fleet`
- `GET/POST/PATCH {baseURL}/rest/v1/inspection`
- `GET/POST/PATCH {baseURL}/rest/v1/todo`
- `GET/POST/PATCH {baseURL}/rest/v1/task`
- `GET/POST/PATCH {baseURL}/rest/v1/report`
- `POST {baseURL}/storage/v1/object/{bucket}/{objectPath}` (task image upload)
- `POST {CAT_BACKEND_API_URL}/reports/generate/{inspection_id}?run_async=false` (PDF generation using template)

You do not need to hardcode each table endpoint separately.

## 3) Where request logs are printed

All API logs are printed from:
- `CAT Inspect/CAT Inspect/Services/InspectionAPI.swift`
- `final class SupabaseInspectionBackend`

Log prefix:
- `[SupabaseAPI]`

Logged data includes:
- method, full URL, full query string
- prefer header
- request body (truncated)
- response status + response body (truncated)
- workflow step logs (fleet resolve, inspection insert, task insert, report request)

## 4) Future integrations (S3 + AI endpoint)

Not wired yet in code. When you share details, add them in:
- `CAT Inspect/CAT Inspect/Services/InspectionAPI.swift`

Recommended location:
- add a new config enum below `SupabaseConfig`, for example:

```swift
enum IntegrationConfig {
    static let s3UploadURL = "https://..."
    static let s3AccessKey = "..."
    static let s3SecretKey = "..."

    static let aiEndpoint = "https://..."
    static let aiAPIKey = "..."
}
```

Then call those from:
- `InspectionDatabase.saveTaskFeedbackAndSync(...)` for per-task AI call
- a new upload service for image upload before submitting task feedback

## 4.1) Report generation uses Python template now

Python files used:
- `api/pdf_generator.py`
- `api/templates/report_template.html`
- `api/routers/reports.py`

Ensure API includes reports router:
- `api/main.py` -> `app.include_router(reports_router)`

## 5) Security note

Do not keep production keys hardcoded for release builds.
Use one of:
- `.xcconfig` + `Info.plist` indirection
- build-time environment injection
- secret manager / CI variable injection

## 6) Required Supabase RLS Policies (fix for 401 / code 42501)

If you see:
- `new row violates row-level security policy for table "inspection"`

your anon key is valid, but table RLS policies are blocking insert/update/select.

Run this in Supabase SQL editor for development:

```sql
-- Enable RLS (if not already enabled)
alter table public.fleet enable row level security;
alter table public.inspection enable row level security;
alter table public.todo enable row level security;
alter table public.task enable row level security;
alter table public.report enable row level security;

-- fleet: app reads fleet by id/serial
create policy "fleet_select_anon"
on public.fleet
for select
to anon
using (true);

-- todo: app reads todo by fleet_serial
create policy "todo_select_anon"
on public.todo
for select
to anon
using (true);

-- inspection: app creates and updates inspection rows
create policy "inspection_insert_anon"
on public.inspection
for insert
to anon
with check (true);

create policy "inspection_select_anon"
on public.inspection
for select
to anon
using (true);

create policy "inspection_update_anon"
on public.inspection
for update
to anon
using (true)
with check (true);

-- task: app inserts copied todos + updates task state/feedback
create policy "task_insert_anon"
on public.task
for insert
to anon
with check (true);

create policy "task_select_anon"
on public.task
for select
to anon
using (true);

create policy "task_update_anon"
on public.task
for update
to anon
using (true)
with check (true);

-- report: app inserts report request row
create policy "report_insert_anon"
on public.report
for insert
to anon
with check (true);

create policy "report_select_anon"
on public.report
for select
to anon
using (true);
```

Production note:
- Replace `using (true)` with real access rules (user/tenant based).
- Do not keep wide-open anon policies in production.
