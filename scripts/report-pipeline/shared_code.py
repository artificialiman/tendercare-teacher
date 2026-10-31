"""
The ONE access code every generated transcript uses.

Source, in order:
  1. STUDENT_LOGIN_PASSWORD       -- the same setting the result portal reads, so
                                     the portal login and the standalone
                                     transcripts can never disagree
  2. STUDENT_PASSWORD_FILE        -- path to a text file whose first non-empty
                                     line is the password (surrounding spaces and
                                     the trailing newline are ignored)
  3. the long-standing default    -- only when neither is set; a notice is printed

A file that is named but missing or empty is an error, never a silent fall
back to the default: that is exactly how a "password file that doesn't work"
would otherwise go unnoticed.

Per-student "access_code_hint" values in students/*.json are ignored on purpose.
"""
import os
import sys
from pathlib import Path

DEFAULT_ACCESS_CODE = "12345678"


def shared_access_code() -> str:
    value = os.environ.get("STUDENT_LOGIN_PASSWORD", "").strip()
    if value:
        return value

    file_path = os.environ.get("STUDENT_PASSWORD_FILE", "").strip()
    if file_path:
        p = Path(file_path).expanduser()
        if not p.is_file():
            sys.exit(f"STUDENT_PASSWORD_FILE points at {p}, which does not exist.")
        for line in p.read_text(encoding="utf-8-sig").splitlines():
            if line.strip():
                return line.strip()
        sys.exit(f"STUDENT_PASSWORD_FILE {p} is empty.")

    print(
        f"note: no STUDENT_LOGIN_PASSWORD / STUDENT_PASSWORD_FILE set -- using the default {DEFAULT_ACCESS_CODE!r}",
        file=sys.stderr,
    )
    return DEFAULT_ACCESS_CODE
