# Martial Arts Academy CRM

A custom, role-secured CRM I designed and built to run a martial arts academy —
then turned into a multi-tenant template I can deploy for other schools. It is
live and used by staff across two locations.

> **Why this repo exists:** it's a case study, not the production source. The
> live system handles real students' personal information (including minors'),
> so this repo contains the architecture, the design decisions, the data-free
> schema, and anonymized screenshots — no real data, no credentials.

---

## TL;DR

I own and operate a martial arts academy (Brazilian Jiu-Jitsu + Machida Karate)
with roughly 250 students and 8 staff across two locations. We ran on an
off-the-shelf gym-management SaaS that didn't fit how we actually work, so I
built our own: a Postgres/Supabase backend with role-based row-level security,
a promotion-eligibility and retention engine, audit-logged rank promotions, and
a single-file web app the staff use on their phones. Once it was running, I
generalized it into a **multi-tenant kit** so a new academy can be stood up as
its own fully-isolated instance.

**My role:** sole designer, developer, and operator — data modeling, security,
app, deployment, and the staff rollout.

---

## The problem

Running the academy meant juggling rank progress, attendance, and retention
across two programs and three age groups, on a generic SaaS plus spreadsheets.
Three things were missing:

- **No promotion logic that matched our curriculum.** Eligibility (classes +
  time-in-rank, with different rules per belt and age ladder) lived in
  instructors' heads and a spreadsheet.
- **No retention signal.** Students quietly went inactive with no structured
  outreach trigger.
- **No real access control.** Everyone with the login could see everything,
  including families' contact details.

## What I built

A focused CRM the front desk and coaches actually use:

- **Promotion board** — every active student scored against their belt's real
  thresholds: *Eligible / Approaching / Building*, with the specific next step.
- **Attendance by class** — one-tap check-in from a phone or tablet at the desk.
- **Audit-logged promotions** — promoting a student records the rank change *and*
  who signed off and when. The database makes the approver a required field, so
  no promotion can exist without accountability.
- **Coach notes** — a running, attributed log per student, separate from the
  owner's private notes.
- **Retention flags** — active students surfaced by time since last class, mapped
  to an outreach stage.
- **Role-based views** — owner, instructor, and front desk each see only what
  their job needs.

<!-- Screenshot suggestions (add to docs/screenshots/ and the images render):
![Promotion board](docs/screenshots/owner-dashboard.png)
-->

## Architecture

A deliberately lightweight stack — no framework, no build step, one HTML file
talking to a managed Postgres. Full detail in [ARCHITECTURE.md](ARCHITECTURE.md)
and the data-free [schema.sql](schema.sql).

- **Database:** PostgreSQL (Supabase), 16 tables, 4 reporting views, and SQL
  functions for the privileged actions.
- **Security:** PostgreSQL Row-Level Security on every table, driven by a `staff`
  role table and `SECURITY DEFINER` helper functions.
- **App:** a single self-contained HTML/JS file (no framework), deployed as a
  static site.
- **Automation:** n8n workflows for newsletters and lapsed-student follow-ups,
  reading from the same database as the single source of truth.

## Security & data governance (the part I'm most deliberate about)

The system holds minors' personal information, so access control is the design
center, not an afterthought:

- **Row-Level Security on every table.** The database denies by default; a user
  sees nothing until a role grants it. The access rules live in Postgres, so a
  bug in the front-end can't expose data the database won't release.
- **Least privilege by role.** Front-desk staff can record attendance but cannot
  see contact information or billing notes. Instructors can promote and add coach
  notes but not see private records. Only the owner sees everything.
- **Privileged actions go through audited functions.** Promotions and notes are
  written by `SECURITY DEFINER` functions that verify the caller's role and stamp
  their identity from the login — the approver can't be forged or left blank.
- **Tenant isolation by design.** In the multi-tenant kit, every client academy
  gets its *own* database. No two businesses ever share storage, so there is no
  cross-tenant query path to get wrong.

## From internal tool to product

After it was running for my own academy, I separated the reusable structure from
my data and built a **replication kit**: a from-scratch schema install,
configurable rank ladders, a roster importer, a config-driven app (branding +
credentials in one block), and an onboarding spec. A new academy becomes its own
isolated instance — its own database, its own deployment — rather than a tenant
in a shared one. That decision trades a little setup effort for the strongest
possible data isolation, which is the right call when the data is children's.

## What I'd build next

- An in-app analytics overview (active students per program, promotions due,
  at-risk counts, growth over time).
- A trial/prospect pipeline feeding the same retention engine.
- Scripted provisioning (Supabase + hosting APIs) to make new-client setup
  near one-command.

## Tech stack

PostgreSQL · Supabase · Row-Level Security · SQL (views + `SECURITY DEFINER`
functions) · vanilla JavaScript/HTML · static hosting · n8n · Python (data import).

## About

Built solo by **William Sandoval** — M.S. in Artificial Intelligence in Business, Arizona State University (W. P. Carey). [LinkedIn](https://www.linkedin.com/in/william-sandoval-ms-654a75162)

> Screenshots in this repo use anonymized sample data. The production system is
> access-controlled and is not publicly demoable, by design.
