#!/usr/bin/env python3
"""
Independent export -- the "cheap now, expensive to retrofit" backup leg
from the antifail doctrine (build-doctrine-consolidated.md §5.6), separate
from and in addition to Supabase's own point-in-time recovery.

What this is NOT: a restore tool, a migration tool, or a substitute for
Supabase PITR (which still covers minute-by-minute recovery from an
in-flight mistake far better than a nightly snapshot ever could). What
this IS: a periodic, human-readable, platform-independent copy of every
table, in a format anyone -- not just someone who knows Supabase -- could
open and read. The actual antifail value is that this survives even if
the Supabase project itself is deleted, lapses on billing, or becomes
unreachable for any reason.

Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY as environment
variables -- the service-role key, not the public anon key, since RLS
would otherwise silently truncate this to whatever the anon role can see.
NEVER commit that key, hardcode it here, or run this anywhere the key
could leak into a public repo's history -- see run_nightly.md in this
same directory for where this is (and isn't yet) safe to actually run on
a schedule.

Usage:
    SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... python3 export_backup.py
"""

import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# Every table in the live schema, as of migrations 0001-0013. Update this
# list every time a migration adds a table -- an export script that
# silently misses a new table is worse than no export script, because it
# looks complete when it isn't.
TABLES = [
    "terms",
    "classes",
    "students",
    "subjects",
    "class_subjects",
    "scores",
    "remarks",
    "staff",
    "alumni_archive",
]

OUTPUT_DIR = Path(__file__).parent / "exports"


def fetch_table(base_url: str, service_key: str, table: str) -> list:
    url = f"{base_url}/rest/v1/{table}?select=*"
    req = urllib.request.Request(
        url,
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def main() -> None:
    base_url = os.environ.get("SUPABASE_URL")
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not base_url or not service_key:
        print(
            "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY. "
            "The service-role key is required -- the anon key would have "
            "RLS applied and silently export an incomplete copy.",
            file=sys.stderr,
        )
        sys.exit(1)

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    dest = OUTPUT_DIR / timestamp
    dest.mkdir(parents=True, exist_ok=True)

    manifest = {"exported_at": timestamp, "tables": {}}

    for table in TABLES:
        try:
            rows = fetch_table(base_url, service_key, table)
        except Exception as exc:  # noqa: BLE001 -- report and keep going
            print(f"FAILED: {table} -- {exc}", file=sys.stderr)
            manifest["tables"][table] = {"status": "failed", "error": str(exc)}
            continue

        out_path = dest / f"{table}.json"
        out_path.write_text(json.dumps(rows, indent=2, default=str))
        manifest["tables"][table] = {"status": "ok", "row_count": len(rows)}
        print(f"{table}: {len(rows)} rows")

    (dest / "manifest.json").write_text(json.dumps(manifest, indent=2))

    failed = [t for t, v in manifest["tables"].items() if v["status"] == "failed"]
    if failed:
        print(f"\nExport incomplete -- failed tables: {', '.join(failed)}", file=sys.stderr)
        sys.exit(1)

    print(f"\nExport complete: {dest}")


if __name__ == "__main__":
    main()
