# Security & privacy

This is a **case-study repository**. It contains architecture, design decisions,
and a data-free database schema — never production data or credentials.

## What must never be committed here
- Real student, parent, or staff information (names, emails, phone numbers,
  birthdays, addresses, billing or attendance records).
- Screenshots showing any real personal data — anonymize or blur first.
- API keys, database passwords, connection strings, or `service_role`/secret keys.
- Production URLs or project identifiers.

The `.gitignore` blocks the common offenders (`.env`, key files, `*.xlsx`/`*.csv`,
roster exports), but the final check is manual — especially for screenshots.

## The production system
The live system handles personal information, including minors', and is
access-controlled by design: PostgreSQL Row-Level Security on every table,
least-privilege roles (owner / instructor / front desk), audited privileged
actions, and one isolated database per client. It is intentionally not publicly
demoable.

## Reporting a concern
If you believe something in this repository exposes sensitive data, please open
an issue (without including the sensitive detail itself) or contact the
maintainer directly, and it will be addressed promptly.
