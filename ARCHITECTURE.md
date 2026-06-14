# Architecture

A technical companion to the [README](README.md). It explains the data model,
the security model, and the reasoning behind the choices.

## Design goals

1. **Access control that can't be bypassed from the client.** Rules belong in the
   database, not the UI.
2. **Promotion accountability baked into the schema**, not enforced by convention.
3. **Low operational overhead** — something a solo owner can run and extend.
4. **Replicable per client with hard data isolation.**

## Stack and why

| Layer | Choice | Why |
|---|---|---|
| Database | PostgreSQL (Supabase) | Managed Postgres with built-in auth + Row-Level Security; real relational modeling. |
| Access control | RLS + role table | Enforced at the data layer, independent of the front-end. |
| App | Single-file HTML/JS, no framework | Zero build step; trivial to host, hand off, and reason about. |
| Hosting | Static host | The app is one file; the database does the work. |
| Automation | n8n | Newsletters and lapsed-student outreach off the same database. |
| Import | Python (pandas + psycopg2) | Per-client roster loading from messy spreadsheets. |

## Data model

The core insight: a **person** and an **enrollment** are different things. A
single student can be White-belt-2-stripes in BJJ and Orange in Karate at the
same time — two enrollments, one person. Belt, stripes, and promotion date live
on the enrollment, not the student.

- `students` — the person (name, contact, guardian, DOB). Contact details are the
  most sensitive field group and are locked to the owner.
- `enrollments` — a student in a program: belt, stripes, last promotion date,
  status, and an attendance baseline so historical class counts carry over.
- `attendance` — one row per check-in, against an enrollment.
- `promotions` — rank-change history. `approved_by` is `NOT NULL` — the schema
  itself refuses an unsigned promotion.
- `belts` — the rank ladders and promotion thresholds (per program, per age
  ladder), so eligibility is data-driven, not hard-coded.
- Supporting: `households` (family grouping), `enrollment_pauses` (holds/freezes),
  `staff` + `staff_invites` (roles), `student_notes` (attributed coach notes),
  and a `lesson_*` / `schedule_calendar` set for curriculum and scheduling.

### Reporting views

- `v_promotion_status` — each enrollment scored against its belt's thresholds
  (classes met, time met, active-months met) → an eligibility status and next step.
- `v_retention_flags` — active enrollments by time since last class, mapped to an
  outreach stage.
- `v_checkin_roster` — names + belts only (no contact info) for the attendance
  screen, so non-owners can take attendance without seeing PII.
- `v_enrollment_overview` — a flattened per-enrollment summary.

## Security model

Three roles: **owner**, **instructor**, **front_desk**, mapped by a `staff` table
keyed to the auth user (plus an email-based `staff_invites` path so the owner can
grant access without touching SQL).

- Every table has RLS enabled — **deny by default**.
- Helper functions (`is_owner`, `is_staff`, `can_promote`) are `SECURITY DEFINER`
  so policies can check a user's role without recursive permission problems.
- `students` and `households` are **owner-read only**. Because the reporting views
  run with the caller's permissions (`security_invoker`), non-owners
  automatically get no PII — the lockdown propagates without extra code.
- Privileged writes are funneled through `SECURITY DEFINER` functions:
  - `promote_enrollment(...)` — verifies `can_promote()`, applies the rank change,
    resets the class count toward the next rank, and writes the `promotions` row
    with the approver stamped from the login.
  - `add_student_note(...)` — verifies role and stamps the author; there is no
    direct INSERT path, so authorship can't be spoofed.

The effect: an instructor can promote a student and log a note from the
attendance screen, but cannot pull up a family's phone number. Front desk can
check students in but sees no ranks or contacts. That separation is enforced by
the database.

## Multi-tenant strategy

Clone-per-client, not shared-tenant. Each academy gets its own database and its
own deployment. The trade-off is per-client setup vs. a single shared system —
chosen deliberately, because with minors' data the value of *physical* isolation
(no shared query surface to misconfigure) outweighs the convenience of one
database with tenant-scoped rules.

## Known limitations / honest notes

- Promotion thresholds currently cover BJJ and Machida Karate ladders; other
  styles need their ladder data adjusted.
- Retention timing uses business days and does not yet exclude public holidays.
- The single-file app favors simplicity over componentization; a larger feature
  set would justify a framework.
