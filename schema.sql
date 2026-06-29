-- ============================================================
-- MARTIAL ARTS CRM — SCHEMA + SECURITY (data-free, current)
-- Full structure of the production database: tables, RLS policies,
-- SECURITY DEFINER functions, reporting views, the audit log, the
-- promotion-approval workflow, and attendance-integrity rules.
-- NO client data, NO belt seed, NO credentials. Structure only.
--
-- Objects: 17 tables, 4 reporting views, 8 functions, 40 RLS policies.
-- ============================================================


-- ===================== CORE: tables, RLS, base functions, reporting views =====================
-- ============================================================
-- MARTIAL ARTS CRM — FRESH INSTALL: SCHEMA + SECURITY
-- Builds an EMPTY, fully-secured CRM (tables, RLS, views,
-- promote/coach-note functions). NO client data.
-- Run 1st. Then 02_starter_belts.sql. Then seed owner + import.
-- Generated from the validated Patriot chain (data excluded) 2026-06-13.
-- ============================================================

--
--


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--



--
-- Name: add_student_note(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_student_note(p_student uuid, p_enrollment uuid, p_body text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare v_who text;
begin
  if not public.can_promote() then
    raise exception 'Not authorized to add notes';
  end if;
  if coalesce(btrim(p_body),'') = '' then
    raise exception 'Note is empty';
  end if;
  select coalesce(s.full_name, inv.full_name, auth.jwt() ->> 'email', 'staff')
    into v_who
    from (select 1) z
    left join staff         s   on s.id = auth.uid()
    left join staff_invites inv on lower(inv.email) = lower(auth.jwt() ->> 'email');
  insert into student_notes (student_id, enrollment_id, body, author)
  values (p_student, p_enrollment, btrim(p_body), coalesce(v_who,'staff'));
end;
$$;


--
-- Name: business_days_since(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.business_days_since(d date) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
  select count(*)::int
  from generate_series(d + 1, current_date, interval '1 day') g
  where extract(dow from g) not in (0, 6)
$$;


--
-- Name: can_promote(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_promote() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$ select exists (select 1 from public.staff where id = auth.uid() and role in ('owner','instructor'))
        or exists (select 1 from public.staff_invites where lower(email) = lower(auth.jwt() ->> 'email') and role in ('owner','instructor')) $$;


--
-- Name: is_owner(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_owner() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$ select exists (select 1 from public.staff where id = auth.uid() and role = 'owner')
        or exists (select 1 from public.staff_invites where lower(email) = lower(auth.jwt() ->> 'email') and role = 'owner') $$;


--
-- Name: is_staff(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_staff() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$ select exists (select 1 from public.staff where id = auth.uid())
        or exists (select 1 from public.staff_invites where lower(email) = lower(auth.jwt() ->> 'email')) $$;


--
-- Name: promote_enrollment(uuid, text, integer, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.promote_enrollment(p_enrollment uuid, p_to_belt text, p_to_stripes integer DEFAULT 0, p_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare
  v_from_belt    text;
  v_from_stripes int;
  v_who          text;
begin
  if not public.can_promote() then
    raise exception 'Not authorized to promote';
  end if;

  select belt, stripes
    into v_from_belt, v_from_stripes
    from enrollments
   where id = p_enrollment;

  if not found then
    raise exception 'Enrollment % not found', p_enrollment;
  end if;

  -- approver name: staff login first, then email-invite, then raw email
  select coalesce(s.full_name, inv.full_name, auth.jwt() ->> 'email', 'staff')
    into v_who
    from (select 1) z
    left join staff         s   on s.id = auth.uid()
    left join staff_invites inv on lower(inv.email) = lower(auth.jwt() ->> 'email');

  update enrollments
     set belt                = p_to_belt,
         stripes             = coalesce(p_to_stripes, 0),
         last_promotion_date = coalesce(p_date, current_date),
         classes_baseline    = 0,
         baseline_date       = coalesce(p_date, current_date)
   where id = p_enrollment;

  insert into promotions
    (enrollment_id, from_belt, from_stripes, to_belt, to_stripes,
     promotion_date, approved_by, notes)
  values
    (p_enrollment, v_from_belt, v_from_stripes, p_to_belt, coalesce(p_to_stripes,0),
     coalesce(p_date, current_date), coalesce(v_who,'staff'), p_notes);
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    class_date date DEFAULT CURRENT_DATE NOT NULL,
    class_label text,
    recorded_by text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: belts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.belts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    program text NOT NULL,
    ladder text NOT NULL,
    belt_name text NOT NULL,
    rank_order integer NOT NULL,
    uses_stripes boolean DEFAULT false NOT NULL,
    classes_required integer,
    months_required integer,
    weeks_required integer,
    years_required integer,
    requires_active_months boolean DEFAULT false NOT NULL,
    promotion_rule text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT belts_program_check CHECK ((program = ANY (ARRAY['BJJ'::text, 'Karate'::text])))
);


--
-- Name: curriculum_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.curriculum_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    module_id uuid NOT NULL,
    category text,
    title text NOT NULL,
    description text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: curriculum_modules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.curriculum_modules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    program text NOT NULL,
    age_track text,
    tier text,
    label text NOT NULL,
    target_belt_id uuid,
    lesson_plan text,
    stated_classes_required integer,
    stated_months_required integer,
    source_file text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT curriculum_modules_program_check CHECK ((program = ANY (ARRAY['BJJ'::text, 'Karate'::text])))
);


--
-- Name: enrollment_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.enrollment_pauses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    pause_start date DEFAULT CURRENT_DATE NOT NULL,
    pause_end date,
    reason text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pause_end_after_start CHECK (((pause_end IS NULL) OR (pause_end >= pause_start)))
);


--
-- Name: enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    student_id uuid NOT NULL,
    program text NOT NULL,
    class_group text,
    belt text DEFAULT 'White'::text NOT NULL,
    stripes integer DEFAULT 0 NOT NULL,
    last_promotion_date date,
    status text DEFAULT 'active'::text NOT NULL,
    joined_on date DEFAULT CURRENT_DATE,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    classes_baseline integer DEFAULT 0 NOT NULL,
    last_attended_baseline date,
    baseline_date date DEFAULT CURRENT_DATE,
    CONSTRAINT enrollments_class_group_check CHECK ((class_group = ANY (ARRAY['Adult'::text, 'Teen'::text, 'Youth'::text, 'Kids'::text, 'Little Dragon'::text]))),
    CONSTRAINT enrollments_program_check CHECK ((program = ANY (ARRAY['BJJ'::text, 'Karate'::text]))),
    CONSTRAINT enrollments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'frozen'::text, 'inactive'::text]))),
    CONSTRAINT enrollments_stripes_check CHECK (((stripes >= 0) AND
CASE
    WHEN (belt = 'Black'::text) THEN (stripes <= 9)
    ELSE (stripes <= 4)
END))
);


--
-- Name: households; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.households (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: lesson_classes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lesson_classes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    track_id uuid NOT NULL,
    class_no integer NOT NULL,
    belt_tag text,
    notes text
);


--
-- Name: lesson_components; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lesson_components (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    class_id uuid NOT NULL,
    category text NOT NULL,
    content text NOT NULL,
    sort_order integer DEFAULT 0
);


--
-- Name: lesson_tracks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lesson_tracks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    program text NOT NULL,
    name text NOT NULL,
    age_label text,
    field_order text[],
    unit_label text DEFAULT 'Class'::text,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: promotions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promotions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    from_belt text,
    from_stripes integer,
    to_belt text NOT NULL,
    to_stripes integer DEFAULT 0 NOT NULL,
    promotion_date date DEFAULT CURRENT_DATE NOT NULL,
    approved_by text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: schedule_calendar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schedule_calendar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    track_id uuid NOT NULL,
    session_date date NOT NULL,
    class_no integer,
    start_time text,
    label text
);


--
-- Name: staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff (
    id uuid NOT NULL,
    full_name text,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT staff_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'instructor'::text, 'front_desk'::text])))
);


--
-- Name: staff_invites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_invites (
    email text NOT NULL,
    role text NOT NULL,
    full_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT staff_invites_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'instructor'::text, 'front_desk'::text])))
);


--
-- Name: student_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    student_id uuid NOT NULL,
    enrollment_id uuid,
    body text NOT NULL,
    author text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: students; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.students (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text,
    phone text,
    guardian_name text,
    date_of_birth date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    household_id uuid,
    notes text
);


--
-- Name: v_checkin_roster; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_checkin_roster WITH (security_invoker='false') AS
 SELECT e.id AS enrollment_id,
    e.student_id,
    s.first_name,
    s.last_name,
    e.program,
    e.class_group,
    e.belt,
    e.stripes
   FROM (public.enrollments e
     JOIN public.students s ON ((s.id = e.student_id)))
  WHERE ((e.status = 'active'::text) AND public.is_staff());


--
-- Name: v_enrollment_overview; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_enrollment_overview WITH (security_invoker='on') AS
 SELECT e.id AS enrollment_id,
    s.first_name,
    s.last_name,
    e.program,
    e.class_group,
    e.belt,
    e.stripes,
    e.status,
    e.last_promotion_date,
    max(a.class_date) AS last_class_date,
    (CURRENT_DATE - max(a.class_date)) AS days_since_last_class,
    ((CURRENT_DATE - max(a.class_date)) >= 10) AS is_inactive,
    count(a.id) AS total_classes,
    count(a.id) FILTER (WHERE ((e.last_promotion_date IS NULL) OR (a.class_date > e.last_promotion_date))) AS classes_since_promo
   FROM ((public.enrollments e
     JOIN public.students s ON ((s.id = e.student_id)))
     LEFT JOIN public.attendance a ON ((a.enrollment_id = e.id)))
  GROUP BY e.id, s.first_name, s.last_name, e.program, e.class_group, e.belt, e.stripes, e.status, e.last_promotion_date;


--
-- Name: v_promotion_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_promotion_status WITH (security_invoker='on') AS
 WITH base AS (
         SELECT e.id AS enrollment_id,
            e.student_id,
            s.first_name,
            s.last_name,
            e.program,
            e.class_group,
            e.belt,
            e.stripes,
            e.status,
            e.last_promotion_date,
                CASE
                    WHEN (e.class_group = 'Adult'::text) THEN 'adult'::text
                    ELSE 'kids_youth'::text
                END AS ladder,
            (COALESCE(e.classes_baseline, 0) + count(a.id) FILTER (WHERE (a.class_date > COALESCE(e.baseline_date, e.last_promotion_date, '1900-01-01'::date)))) AS classes_since_promo,
            GREATEST(max(a.class_date), e.last_attended_baseline) AS last_class_date
           FROM ((public.enrollments e
             JOIN public.students s ON ((s.id = e.student_id)))
             LEFT JOIN public.attendance a ON ((a.enrollment_id = e.id)))
          GROUP BY e.id, e.student_id, s.first_name, s.last_name, e.program, e.class_group, e.belt, e.stripes, e.status, e.last_promotion_date, e.classes_baseline, e.baseline_date, e.last_attended_baseline
        ), paused AS (
         SELECT p.enrollment_id,
            (sum(GREATEST(0, (LEAST(COALESCE(p.pause_end, CURRENT_DATE), CURRENT_DATE) - GREATEST(p.pause_start, COALESCE(e.last_promotion_date, p.pause_start))))))::integer AS paused_days
           FROM (public.enrollment_pauses p
             JOIN public.enrollments e ON ((e.id = p.enrollment_id)))
          GROUP BY p.enrollment_id
        ), cur_pause AS (
         SELECT DISTINCT ON (enrollment_pauses.enrollment_id) enrollment_pauses.enrollment_id,
            enrollment_pauses.pause_start AS paused_since
           FROM public.enrollment_pauses
          WHERE ((enrollment_pauses.pause_start <= CURRENT_DATE) AND ((enrollment_pauses.pause_end IS NULL) OR (enrollment_pauses.pause_end >= CURRENT_DATE)))
          ORDER BY enrollment_pauses.enrollment_id, enrollment_pauses.pause_start DESC
        ), active AS (
         SELECT e.id AS enrollment_id,
            count(*) FILTER (WHERE (m.cnt >= 4)) AS active_month_count
           FROM (public.enrollments e
             LEFT JOIN ( SELECT a.enrollment_id,
                    date_trunc('month'::text, (a.class_date)::timestamp with time zone) AS mo,
                    count(*) AS cnt
                   FROM (public.attendance a
                     JOIN public.enrollments e2 ON ((e2.id = a.enrollment_id)))
                  WHERE ((e2.last_promotion_date IS NULL) OR (a.class_date > e2.last_promotion_date))
                  GROUP BY a.enrollment_id, (date_trunc('month'::text, (a.class_date)::timestamp with time zone))) m ON ((m.enrollment_id = e.id)))
          GROUP BY e.id
        ), j AS (
         SELECT b.enrollment_id,
            b.student_id,
            b.first_name,
            b.last_name,
            b.program,
            b.class_group,
            b.belt,
            b.stripes,
            b.status,
            b.last_promotion_date,
            b.ladder,
            b.classes_since_promo,
            b.last_class_date,
            COALESCE(pd.paused_days, 0) AS paused_days,
            (cp.enrollment_id IS NOT NULL) AS is_paused,
            cp.paused_since,
            ac.active_month_count,
            cur.belt_name AS cur_belt,
            cur.rank_order,
            cur.uses_stripes,
            cur.classes_required,
            cur.months_required,
            cur.weeks_required,
            cur.years_required,
            cur.requires_active_months,
            nb.belt_name AS next_belt,
                CASE
                    WHEN (b.last_class_date IS NULL) THEN NULL::integer
                    ELSE (CURRENT_DATE - b.last_class_date)
                END AS days_since_last_class,
            ((cp.enrollment_id IS NULL) AND (((b.last_class_date IS NOT NULL) AND ((CURRENT_DATE - b.last_class_date) >= 30)) OR ((b.last_class_date IS NULL) AND (b.last_promotion_date IS NOT NULL) AND ((CURRENT_DATE - b.last_promotion_date) >= 30)))) AS is_auto_hold,
                CASE
                    WHEN (b.last_promotion_date IS NULL) THEN 0
                    WHEN (cp.enrollment_id IS NOT NULL) THEN 0
                    WHEN ((b.last_class_date IS NOT NULL) AND ((CURRENT_DATE - b.last_class_date) >= 30)) THEN GREATEST(0, (CURRENT_DATE - GREATEST((b.last_class_date + 30), b.last_promotion_date)))
                    WHEN ((b.last_class_date IS NULL) AND ((CURRENT_DATE - b.last_promotion_date) >= 30)) THEN GREATEST(0, ((CURRENT_DATE - b.last_promotion_date) - 30))
                    ELSE 0
                END AS auto_hold_days
           FROM (((((base b
             LEFT JOIN paused pd ON ((pd.enrollment_id = b.enrollment_id)))
             LEFT JOIN cur_pause cp ON ((cp.enrollment_id = b.enrollment_id)))
             LEFT JOIN active ac ON ((ac.enrollment_id = b.enrollment_id)))
             LEFT JOIN public.belts cur ON (((cur.program = b.program) AND (cur.ladder = b.ladder) AND (cur.belt_name = b.belt))))
             LEFT JOIN public.belts nb ON (((nb.program = b.program) AND (nb.ladder = b.ladder) AND (nb.rank_order = (cur.rank_order + 1)))))
        ), scored AS (
         SELECT j.enrollment_id,
            j.student_id,
            j.first_name,
            j.last_name,
            j.program,
            j.class_group,
            j.belt,
            j.stripes,
            j.status,
            j.last_promotion_date,
            j.ladder,
            j.classes_since_promo,
            j.last_class_date,
            j.paused_days,
            j.is_paused,
            j.paused_since,
            j.active_month_count,
            j.cur_belt,
            j.rank_order,
            j.uses_stripes,
            j.classes_required,
            j.months_required,
            j.weeks_required,
            j.years_required,
            j.requires_active_months,
            j.next_belt,
            j.days_since_last_class,
            j.is_auto_hold,
            j.auto_hold_days,
                CASE
                    WHEN (j.last_promotion_date IS NULL) THEN NULL::integer
                    ELSE (((CURRENT_DATE - j.last_promotion_date) - j.paused_days) - j.auto_hold_days)
                END AS eff_days
           FROM j
        ), flagged AS (
         SELECT s.enrollment_id,
            s.student_id,
            s.first_name,
            s.last_name,
            s.program,
            s.class_group,
            s.belt,
            s.stripes,
            s.status,
            s.last_promotion_date,
            s.ladder,
            s.classes_since_promo,
            s.last_class_date,
            s.paused_days,
            s.is_paused,
            s.paused_since,
            s.active_month_count,
            s.cur_belt,
            s.rank_order,
            s.uses_stripes,
            s.classes_required,
            s.months_required,
            s.weeks_required,
            s.years_required,
            s.requires_active_months,
            s.next_belt,
            s.days_since_last_class,
            s.is_auto_hold,
            s.auto_hold_days,
            s.eff_days,
            ((s.classes_required IS NULL) OR (s.classes_since_promo >= s.classes_required)) AS classes_met,
                CASE
                    WHEN ((s.weeks_required IS NULL) AND (s.years_required IS NULL) AND (s.months_required IS NULL)) THEN true
                    WHEN (s.last_promotion_date IS NULL) THEN false
                    WHEN (s.weeks_required IS NOT NULL) THEN (s.eff_days >= (s.weeks_required * 7))
                    WHEN (s.years_required IS NOT NULL) THEN (s.eff_days >= (s.years_required * 365))
                    WHEN (s.months_required IS NOT NULL) THEN ((s.eff_days)::numeric >= round(((s.months_required)::numeric * 30.44)))
                    ELSE true
                END AS time_met,
            ((NOT COALESCE(s.requires_active_months, false)) OR (s.active_month_count >= COALESCE(s.months_required, 0))) AS active_months_met
           FROM scored s
        )
 SELECT enrollment_id,
    student_id,
    first_name,
    last_name,
    program,
    class_group,
    belt,
    stripes,
    ladder,
    status,
    last_promotion_date,
    eff_days AS days_since_promo,
        CASE
            WHEN (eff_days IS NULL) THEN NULL::integer
            ELSE (round(((eff_days)::numeric / 30.44)))::integer
        END AS months_since_promo,
    paused_days,
    is_paused,
    paused_since,
    is_auto_hold,
    days_since_last_class,
    auto_hold_days,
    classes_since_promo,
    classes_required,
    months_required,
    weeks_required,
    years_required,
    requires_active_months,
    active_month_count,
        CASE
            WHEN ((program = 'Karate'::text) AND (ladder = 'kids_youth'::text) AND (belt = 'Brown-White'::text) AND (stripes < 3)) THEN ('Stripe '::text || (stripes + 1))
            WHEN ((program = 'Karate'::text) AND (ladder = 'kids_youth'::text) AND (belt = 'Brown-White'::text)) THEN 'Test for solid Blue (adult ladder, age 15.5+)'::text
            WHEN ((belt = 'Black'::text) AND (stripes < 9)) THEN ('Degree '::text || (stripes + 1))
            WHEN (belt = 'Black'::text) THEN 'Max degree (9th)'::text
            WHEN (uses_stripes AND (years_required IS NULL) AND (stripes < 4)) THEN ('Stripe '::text || (stripes + 1))
            ELSE ('Promote to '::text || COALESCE(next_belt, '(top rank)'::text))
        END AS next_step,
    classes_met,
    time_met,
    active_months_met,
        CASE
            WHEN (cur_belt IS NULL) THEN 'Unmapped belt'::text
            WHEN is_paused THEN 'Paused'::text
            WHEN is_auto_hold THEN 'Hold (inactive 30d+)'::text
            WHEN (classes_met AND time_met AND active_months_met) THEN 'Eligible'::text
            WHEN (classes_met OR time_met) THEN 'Approaching'::text
            ELSE 'Building'::text
        END AS promotion_status
   FROM flagged;


--
-- Name: v_retention_flags; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_retention_flags WITH (security_invoker='on') AS
 WITH last_class AS (
         SELECT e.id AS enrollment_id,
            e.student_id,
            s.first_name,
            s.last_name,
            e.program,
            e.class_group,
            e.belt,
            s.email,
            s.phone,
            GREATEST(max(a.class_date), e.last_attended_baseline) AS last_class_date
           FROM ((public.enrollments e
             JOIN public.students s ON ((s.id = e.student_id)))
             LEFT JOIN public.attendance a ON ((a.enrollment_id = e.id)))
          WHERE (e.status = 'active'::text)
          GROUP BY e.id, e.student_id, s.first_name, s.last_name, e.program, e.class_group, e.belt, s.email, s.phone, e.last_attended_baseline
        ), paused_now AS (
         SELECT DISTINCT enrollment_pauses.enrollment_id
           FROM public.enrollment_pauses
          WHERE ((enrollment_pauses.pause_start <= CURRENT_DATE) AND ((enrollment_pauses.pause_end IS NULL) OR (enrollment_pauses.pause_end >= CURRENT_DATE)))
        )
 SELECT lc.enrollment_id,
    lc.student_id,
    lc.first_name,
    lc.last_name,
    lc.program,
    lc.class_group,
    lc.belt,
    lc.email,
    lc.phone,
    lc.last_class_date,
    (CURRENT_DATE - lc.last_class_date) AS days_since_last_class,
    public.business_days_since(lc.last_class_date) AS business_days_out,
    (pn.enrollment_id IS NOT NULL) AS is_paused,
        CASE
            WHEN (pn.enrollment_id IS NOT NULL) THEN 'Paused'::text
            WHEN (lc.last_class_date IS NULL) THEN 'No attendance on record'::text
            WHEN (public.business_days_since(lc.last_class_date) >= 20) THEN 'Phone call (~4 wks out)'::text
            WHEN (public.business_days_since(lc.last_class_date) >= 15) THEN 'Second email (~3 wks out)'::text
            WHEN (public.business_days_since(lc.last_class_date) >= 10) THEN 'First email (~2 wks out)'::text
            ELSE 'Active'::text
        END AS outreach_stage
   FROM (last_class lc
     LEFT JOIN paused_now pn ON ((pn.enrollment_id = lc.enrollment_id)));


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: belts belts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.belts
    ADD CONSTRAINT belts_pkey PRIMARY KEY (id);


--
-- Name: belts belts_program_ladder_belt_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.belts
    ADD CONSTRAINT belts_program_ladder_belt_name_key UNIQUE (program, ladder, belt_name);


--
-- Name: curriculum_items curriculum_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_items
    ADD CONSTRAINT curriculum_items_pkey PRIMARY KEY (id);


--
-- Name: curriculum_modules curriculum_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_modules
    ADD CONSTRAINT curriculum_modules_pkey PRIMARY KEY (id);


--
-- Name: enrollment_pauses enrollment_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_pauses
    ADD CONSTRAINT enrollment_pauses_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_student_id_program_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_student_id_program_key UNIQUE (student_id, program);


--
-- Name: households households_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.households
    ADD CONSTRAINT households_pkey PRIMARY KEY (id);


--
-- Name: lesson_classes lesson_classes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_classes
    ADD CONSTRAINT lesson_classes_pkey PRIMARY KEY (id);


--
-- Name: lesson_classes lesson_classes_track_id_class_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_classes
    ADD CONSTRAINT lesson_classes_track_id_class_no_key UNIQUE (track_id, class_no);


--
-- Name: lesson_components lesson_components_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_components
    ADD CONSTRAINT lesson_components_pkey PRIMARY KEY (id);


--
-- Name: lesson_tracks lesson_tracks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_tracks
    ADD CONSTRAINT lesson_tracks_pkey PRIMARY KEY (id);


--
-- Name: lesson_tracks lesson_tracks_program_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_tracks
    ADD CONSTRAINT lesson_tracks_program_name_key UNIQUE (program, name);


--
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- Name: schedule_calendar schedule_calendar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_calendar
    ADD CONSTRAINT schedule_calendar_pkey PRIMARY KEY (id);


--
-- Name: schedule_calendar schedule_calendar_track_id_session_date_start_time_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_calendar
    ADD CONSTRAINT schedule_calendar_track_id_session_date_start_time_key UNIQUE (track_id, session_date, start_time);


--
-- Name: staff_invites staff_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_invites
    ADD CONSTRAINT staff_invites_pkey PRIMARY KEY (email);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


--
-- Name: student_notes student_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_notes
    ADD CONSTRAINT student_notes_pkey PRIMARY KEY (id);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (id);


--
-- Name: idx_attendance_enrollment_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_enrollment_date ON public.attendance USING btree (enrollment_id, class_date);


--
-- Name: idx_belts_program_ladder; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_belts_program_ladder ON public.belts USING btree (program, ladder, rank_order);


--
-- Name: idx_calendar_track; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_track ON public.schedule_calendar USING btree (track_id, session_date);


--
-- Name: idx_classes_track; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_classes_track ON public.lesson_classes USING btree (track_id, class_no);


--
-- Name: idx_components_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_components_class ON public.lesson_components USING btree (class_id);


--
-- Name: idx_enrollments_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_enrollments_student ON public.enrollments USING btree (student_id);


--
-- Name: idx_items_module; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_module ON public.curriculum_items USING btree (module_id);


--
-- Name: idx_modules_target_belt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_modules_target_belt ON public.curriculum_modules USING btree (target_belt_id);


--
-- Name: idx_pauses_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pauses_active ON public.enrollment_pauses USING btree (enrollment_id, pause_start, pause_end);


--
-- Name: idx_pauses_enrollment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pauses_enrollment ON public.enrollment_pauses USING btree (enrollment_id);


--
-- Name: idx_promotions_enrollment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promotions_enrollment ON public.promotions USING btree (enrollment_id);


--
-- Name: idx_student_notes_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_student_notes_student ON public.student_notes USING btree (student_id, created_at DESC);


--
-- Name: idx_students_household; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_household ON public.students USING btree (household_id);


--
-- Name: idx_students_last_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_students_last_name ON public.students USING btree (last_name);


--
-- Name: attendance attendance_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;


--
-- Name: curriculum_items curriculum_items_module_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_items
    ADD CONSTRAINT curriculum_items_module_id_fkey FOREIGN KEY (module_id) REFERENCES public.curriculum_modules(id) ON DELETE CASCADE;


--
-- Name: curriculum_modules curriculum_modules_target_belt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.curriculum_modules
    ADD CONSTRAINT curriculum_modules_target_belt_id_fkey FOREIGN KEY (target_belt_id) REFERENCES public.belts(id);


--
-- Name: enrollment_pauses enrollment_pauses_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_pauses
    ADD CONSTRAINT enrollment_pauses_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.staff(id);


--
-- Name: enrollment_pauses enrollment_pauses_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollment_pauses
    ADD CONSTRAINT enrollment_pauses_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;


--
-- Name: enrollments enrollments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE CASCADE;


--
-- Name: lesson_classes lesson_classes_track_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_classes
    ADD CONSTRAINT lesson_classes_track_id_fkey FOREIGN KEY (track_id) REFERENCES public.lesson_tracks(id) ON DELETE CASCADE;


--
-- Name: lesson_components lesson_components_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lesson_components
    ADD CONSTRAINT lesson_components_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.lesson_classes(id) ON DELETE CASCADE;


--
-- Name: promotions promotions_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;


--
-- Name: schedule_calendar schedule_calendar_track_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_calendar
    ADD CONSTRAINT schedule_calendar_track_id_fkey FOREIGN KEY (track_id) REFERENCES public.lesson_tracks(id) ON DELETE CASCADE;


--
-- Name: staff staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: student_notes student_notes_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_notes
    ADD CONSTRAINT student_notes_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE SET NULL;


--
-- Name: student_notes student_notes_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_notes
    ADD CONSTRAINT student_notes_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE CASCADE;


--
-- Name: students students_household_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_household_id_fkey FOREIGN KEY (household_id) REFERENCES public.households(id) ON DELETE SET NULL;


--
-- Name: attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: belts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.belts ENABLE ROW LEVEL SECURITY;

--
-- Name: student_notes coach read notes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "coach read notes" ON public.student_notes FOR SELECT TO authenticated USING (public.can_promote());


--
-- Name: curriculum_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.curriculum_items ENABLE ROW LEVEL SECURITY;

--
-- Name: curriculum_modules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.curriculum_modules ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollment_pauses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.enrollment_pauses ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

--
-- Name: households; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;

--
-- Name: lesson_classes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lesson_classes ENABLE ROW LEVEL SECURITY;

--
-- Name: lesson_classes lesson_classes_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_classes_read ON public.lesson_classes FOR SELECT USING (public.is_staff());


--
-- Name: lesson_classes lesson_classes_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_classes_write ON public.lesson_classes USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: lesson_components; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lesson_components ENABLE ROW LEVEL SECURITY;

--
-- Name: lesson_components lesson_components_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_components_read ON public.lesson_components FOR SELECT USING (public.is_staff());


--
-- Name: lesson_components lesson_components_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_components_write ON public.lesson_components USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: lesson_tracks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lesson_tracks ENABLE ROW LEVEL SECURITY;

--
-- Name: lesson_tracks lesson_tracks_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_tracks_read ON public.lesson_tracks FOR SELECT USING (public.is_staff());


--
-- Name: lesson_tracks lesson_tracks_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lesson_tracks_write ON public.lesson_tracks USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: attendance owner delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff delete" ON public.attendance FOR DELETE TO authenticated USING (public.is_staff());


--
-- Name: enrollment_pauses owner delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner delete" ON public.enrollment_pauses FOR DELETE TO authenticated USING (public.is_owner());


--
-- Name: promotions owner delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner delete" ON public.promotions FOR DELETE TO authenticated USING (public.is_owner());


--
-- Name: student_notes owner delete notes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner delete notes" ON public.student_notes FOR DELETE TO authenticated USING (public.is_owner());


--
-- Name: staff_invites owner manages invites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner manages invites" ON public.staff_invites TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: staff owner manages staff; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner manages staff" ON public.staff TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: households owner read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner read" ON public.households FOR SELECT TO authenticated USING (public.is_owner());


--
-- Name: students owner read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner read" ON public.students FOR SELECT TO authenticated USING (public.is_owner());


--
-- Name: belts owner write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner write" ON public.belts TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: curriculum_items owner write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner write" ON public.curriculum_items TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: curriculum_modules owner write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner write" ON public.curriculum_modules TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: enrollments owner write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner write" ON public.enrollments TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: households owner write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner write" ON public.households TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: students owner write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner write" ON public.students TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: promotions promote insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "promote insert" ON public.promotions FOR INSERT TO authenticated WITH CHECK (public.can_promote());


--
-- Name: promotions promote update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "promote update" ON public.promotions FOR UPDATE TO authenticated USING (public.can_promote()) WITH CHECK (public.can_promote());


--
-- Name: promotions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_invites read own invite; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own invite" ON public.staff_invites FOR SELECT TO authenticated USING (((lower(email) = lower((auth.jwt() ->> 'email'::text))) OR public.is_owner()));


--
-- Name: staff read own staff row; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read own staff row" ON public.staff FOR SELECT TO authenticated USING (((id = auth.uid()) OR public.is_owner()));


--
-- Name: schedule_calendar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.schedule_calendar ENABLE ROW LEVEL SECURITY;

--
-- Name: schedule_calendar schedule_calendar_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedule_calendar_read ON public.schedule_calendar FOR SELECT USING (public.is_staff());


--
-- Name: schedule_calendar schedule_calendar_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedule_calendar_write ON public.schedule_calendar USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: staff; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollment_pauses staff add; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff add" ON public.enrollment_pauses FOR INSERT TO authenticated WITH CHECK (public.is_staff());


--
-- Name: attendance staff read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff read" ON public.attendance FOR SELECT TO authenticated USING (public.is_staff());


--
-- Name: belts staff read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff read" ON public.belts FOR SELECT TO authenticated USING (public.is_staff());


--
-- Name: curriculum_items staff read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff read" ON public.curriculum_items FOR SELECT TO authenticated USING (public.is_staff());


--
-- Name: curriculum_modules staff read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff read" ON public.curriculum_modules FOR SELECT TO authenticated USING (public.is_staff());


--
-- Name: enrollment_pauses staff read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff read" ON public.enrollment_pauses FOR SELECT TO authenticated USING (public.is_staff());


--
-- Name: enrollments staff read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff read" ON public.enrollments FOR SELECT TO authenticated USING (public.is_staff());


--
-- Name: promotions staff read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff read" ON public.promotions FOR SELECT TO authenticated USING (public.is_staff());


--
-- Name: attendance staff record; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff record" ON public.attendance FOR INSERT TO authenticated WITH CHECK (public.is_staff());


--
-- Name: attendance staff update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff update" ON public.attendance FOR UPDATE TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: enrollment_pauses staff update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff update" ON public.enrollment_pauses FOR UPDATE TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: staff_invites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: student_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.student_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: students; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

--
--

CREATE INDEX IF NOT EXISTS idx_attendance_class_date ON public.attendance USING btree (class_date);


-- ===================== AUDIT LOG: audit_log table + fn_audit trigger (who changed what) =====================
-- 032_audit_log.sql
-- Activity log for the owner: every insert/update/delete on the key tables is
-- recorded with who did it, what, and when. Triggers catch changes no matter
-- where they come from (the app, the SQL editor, anything).
--
-- Read access: owner only. Writes happen only through the SECURITY DEFINER
-- trigger function, so staff never touch the table directly.

create table if not exists audit_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  actor_uid  uuid,
  actor      text,
  action     text not null,   -- INSERT | UPDATE | DELETE
  entity     text not null,   -- table name
  entity_id  text,
  summary    text,
  subject_student_id uuid
);
create index if not exists idx_audit_at on audit_log (at desc);

alter table audit_log enable row level security;
drop policy if exists "owner read audit" on audit_log;
create policy "owner read audit" on audit_log
  for select to authenticated using (public.is_owner());
grant select on audit_log to authenticated;

create or replace function public.fn_audit() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare j jsonb; v_actor text; v_id text; v_sum text;
begin
  if TG_OP = 'DELETE' then j := to_jsonb(OLD); else j := to_jsonb(NEW); end if;

  v_actor := coalesce(
    (select full_name from staff where id = auth.uid()),
    (select full_name from staff_invites where lower(email) = lower(auth.jwt() ->> 'email')),
    nullif(auth.jwt() ->> 'email',''),
    'system');

  v_id := coalesce(j ->> 'id', '');

  v_sum := case TG_TABLE_NAME
    when 'students'         then trim(coalesce(j->>'first_name','')||' '||coalesce(j->>'last_name',''))
    when 'enrollments'      then trim(coalesce(j->>'program','')||' '||coalesce(j->>'belt',''))
    when 'promotions'       then 'to '||coalesce(j->>'to_belt','')
    when 'student_notes'    then 'coach note'
    when 'trials'           then trim(coalesce(j->>'first_name','')||' '||coalesce(j->>'last_name',''))||' ('||coalesce(j->>'status','')||')'
    when 'enrollment_pauses' then 'hold'
    when 'staff_invites'    then trim(coalesce(j->>'email','')||' '||coalesce(j->>'role',''))
    else '' end;

  insert into audit_log(actor_uid, actor, action, entity, entity_id, summary)
  values (auth.uid(), v_actor, TG_OP, TG_TABLE_NAME, v_id, v_sum);
  return null;  -- AFTER trigger; return value ignored
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['students','enrollments','promotions','student_notes',
                           'trials','enrollment_pauses','staff_invites'] loop
    execute format('drop trigger if exists trg_audit on public.%I', t);
    execute format('create trigger trg_audit after insert or update or delete on public.%I '
                   'for each row execute function public.fn_audit()', t);
  end loop;
end $$;

-- enhanced summary (resolves student name + subject id)
create or replace function public.fn_audit() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare j jsonb; v_actor text; v_id text; v_sum text; v_name text; v_sid uuid; v_enr uuid;
begin
  if TG_OP = 'DELETE' then j := to_jsonb(OLD); else j := to_jsonb(NEW); end if;

  v_actor := coalesce(
    (select full_name from staff where id = auth.uid()),
    (select full_name from staff_invites where lower(email) = lower(auth.jwt() ->> 'email')),
    nullif(auth.jwt() ->> 'email',''),
    'system');

  v_id := coalesce(j ->> 'id', '');

  -- Resolve the student this row concerns (directly, or via its enrollment).
  v_sid := nullif(j ->> 'student_id','')::uuid;
  v_enr := nullif(j ->> 'enrollment_id','')::uuid;
  if v_sid is null and v_enr is not null then
    select student_id into v_sid from enrollments where id = v_enr;
  end if;
  if v_sid is null and TG_TABLE_NAME = 'students' then
    v_sid := nullif(j ->> 'id','')::uuid;
  end if;
  if v_sid is not null then
    select nullif(trim(coalesce(first_name,'')||' '||coalesce(last_name,'')),'')
      into v_name from students where id = v_sid;
  end if;

  v_sum := case TG_TABLE_NAME
    when 'students'          then trim(coalesce(j->>'first_name','')||' '||coalesce(j->>'last_name',''))
    when 'enrollments'       then coalesce(v_name,'student '||left(coalesce(j->>'student_id','?'),8))||' — '||trim(coalesce(j->>'program','')||' '||coalesce(j->>'belt',''))
    when 'promotions'        then coalesce(v_name,'?')||' — to '||coalesce(j->>'to_belt','')||case when coalesce(j->>'to_stripes','0')<>'0' then ' · '||(j->>'to_stripes')||' stripe(s)' else '' end
    when 'student_notes'     then coalesce(v_name,'?')||' — coach note'
    when 'trials'            then trim(coalesce(j->>'first_name','')||' '||coalesce(j->>'last_name',''))||' ('||coalesce(j->>'status','')||')'
    when 'enrollment_pauses' then coalesce(v_name,'?')||' — hold'
    when 'staff_invites'     then trim(coalesce(j->>'email','')||' '||coalesce(j->>'role',''))
    else '' end;

  insert into audit_log(actor_uid, actor, action, entity, entity_id, summary, subject_student_id)
  values (auth.uid(), v_actor, TG_OP, TG_TABLE_NAME, v_id, v_sum, v_sid);
  return null;
end;
$$;

-- ===== single-entry promotions + skip flag (from 034) =====
-- 1) Audit trigger honors a skip flag.
create or replace function public.fn_audit() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare j jsonb; v_actor text; v_id text; v_sum text; v_name text; v_sid uuid; v_enr uuid;
begin
  if coalesce(current_setting('app.skip_audit', true),'') = 'on' then
    return null;  -- this change is captured by a higher-level action
  end if;

  if TG_OP = 'DELETE' then j := to_jsonb(OLD); else j := to_jsonb(NEW); end if;

  v_actor := coalesce(
    (select full_name from staff where id = auth.uid()),
    (select full_name from staff_invites where lower(email) = lower(auth.jwt() ->> 'email')),
    nullif(auth.jwt() ->> 'email',''),
    'system');

  v_id := coalesce(j ->> 'id', '');

  v_sid := nullif(j ->> 'student_id','')::uuid;
  v_enr := nullif(j ->> 'enrollment_id','')::uuid;
  if v_sid is null and v_enr is not null then
    select student_id into v_sid from enrollments where id = v_enr;
  end if;
  if v_sid is null and TG_TABLE_NAME = 'students' then
    v_sid := nullif(j ->> 'id','')::uuid;
  end if;
  if v_sid is not null then
    select nullif(trim(coalesce(first_name,'')||' '||coalesce(last_name,'')),'')
      into v_name from students where id = v_sid;
  end if;

  v_sum := case TG_TABLE_NAME
    when 'students'          then trim(coalesce(j->>'first_name','')||' '||coalesce(j->>'last_name',''))
    when 'enrollments'       then coalesce(v_name,'student '||left(coalesce(j->>'student_id','?'),8))||' — '||trim(coalesce(j->>'program','')||' '||coalesce(j->>'belt',''))
    when 'promotions'        then coalesce(v_name,'?')||' — to '||coalesce(j->>'to_belt','')||case when coalesce(j->>'to_stripes','0')<>'0' then ' · '||(j->>'to_stripes')||' stripe(s)' else '' end
    when 'student_notes'     then coalesce(v_name,'?')||' — coach note'
    when 'trials'            then trim(coalesce(j->>'first_name','')||' '||coalesce(j->>'last_name',''))||' ('||coalesce(j->>'status','')||')'
    when 'enrollment_pauses' then coalesce(v_name,'?')||' — hold'
    when 'staff_invites'     then trim(coalesce(j->>'email','')||' '||coalesce(j->>'role',''))
    else '' end;

  insert into audit_log(actor_uid, actor, action, entity, entity_id, summary, subject_student_id)
  values (auth.uid(), v_actor, TG_OP, TG_TABLE_NAME, v_id, v_sum, v_sid);
  return null;
end;
$$;

-- 2) promote_enrollment silences the audit on its enrollment update, so the only
--    log entry is the promotion itself.
create or replace function public.promote_enrollment(
  p_enrollment uuid,
  p_to_belt    text,
  p_to_stripes int  default 0,
  p_date       date default current_date,
  p_notes      text default null
) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_from_belt text; v_from_stripes int; v_who text;
begin
  if not public.can_promote() then
    raise exception 'Not authorized to promote';
  end if;
  select belt, stripes into v_from_belt, v_from_stripes from enrollments where id = p_enrollment;
  if not found then raise exception 'Enrollment % not found', p_enrollment; end if;

  select coalesce(s.full_name, inv.full_name, auth.jwt() ->> 'email', 'staff')
    into v_who
    from (select 1) z
    left join staff         s   on s.id = auth.uid()
    left join staff_invites inv on lower(inv.email) = lower(auth.jwt() ->> 'email');

  perform set_config('app.skip_audit', 'on', true);   -- don't log the raw enrollment update
  update enrollments
     set belt = p_to_belt,
         stripes = coalesce(p_to_stripes, 0),
         last_promotion_date = coalesce(p_date, current_date),
         classes_baseline = 0,
         baseline_date = coalesce(p_date, current_date)
   where id = p_enrollment;
  perform set_config('app.skip_audit', 'off', true);  -- log the promotion below

  insert into promotions
    (enrollment_id, from_belt, from_stripes, to_belt, to_stripes, promotion_date, approved_by, notes)
  values
    (p_enrollment, v_from_belt, v_from_stripes, p_to_belt, coalesce(p_to_stripes,0),
     coalesce(p_date, current_date), coalesce(v_who,'staff'), p_notes);
end;
$$;


-- ===================== PROMOTION APPROVAL: owner clear-to-promote flag + setter + roster =====================
-- 037_promotion_approval.sql
-- Owner can flag an enrollment as "cleared to promote". Instructors see the flag
-- on the check-in roster. The flag is consumed (cleared) when the student is
-- actually promoted.

alter table enrollments add column if not exists promo_approved    boolean not null default false;
alter table enrollments add column if not exists promo_approved_at  date;

-- Surface the flag to instructors via the check-in roster (keep the is_staff guard from 036).
drop view if exists public.v_checkin_roster;
create view public.v_checkin_roster with (security_invoker = false) as
  select e.id as enrollment_id, e.student_id, s.first_name, s.last_name,
         e.program, e.class_group, e.belt, e.stripes, e.promo_approved
  from enrollments e
  join students s on s.id = e.student_id
  where e.status = 'active' and public.is_staff();
grant select on v_checkin_roster to authenticated;

-- Owner-only setter. No audit entry (it's a transient workflow flag; the actual
-- promotion is what gets logged).
create or replace function public.set_promo_approval(p_enrollment uuid, p_approved boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_owner() then
    raise exception 'Only the owner can approve promotions';
  end if;
  perform set_config('app.skip_audit', 'on', true);
  update enrollments
     set promo_approved    = coalesce(p_approved, false),
         promo_approved_at = case when coalesce(p_approved, false) then current_date else null end
   where id = p_enrollment;
  perform set_config('app.skip_audit', 'off', true);
end $$;
grant execute on function public.set_promo_approval(uuid, boolean) to authenticated;

-- Promotions consume the approval: clear the flag as part of the promotion.
create or replace function public.promote_enrollment(
  p_enrollment uuid,
  p_to_belt    text,
  p_to_stripes int  default 0,
  p_date       date default current_date,
  p_notes      text default null
) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_from_belt text; v_from_stripes int; v_who text;
begin
  if not public.can_promote() then
    raise exception 'Not authorized to promote';
  end if;
  select belt, stripes into v_from_belt, v_from_stripes from enrollments where id = p_enrollment;
  if not found then raise exception 'Enrollment % not found', p_enrollment; end if;

  select coalesce(s.full_name, inv.full_name, auth.jwt() ->> 'email', 'staff')
    into v_who
    from (select 1) z
    left join staff         s   on s.id = auth.uid()
    left join staff_invites inv on lower(inv.email) = lower(auth.jwt() ->> 'email');

  perform set_config('app.skip_audit', 'on', true);
  update enrollments
     set belt = p_to_belt,
         stripes = coalesce(p_to_stripes, 0),
         last_promotion_date = coalesce(p_date, current_date),
         classes_baseline = 0,
         baseline_date = coalesce(p_date, current_date),
         promo_approved = false,
         promo_approved_at = null
   where id = p_enrollment;
  perform set_config('app.skip_audit', 'off', true);

  insert into promotions
    (enrollment_id, from_belt, from_stripes, to_belt, to_stripes, promotion_date, approved_by, notes)
  values
    (p_enrollment, v_from_belt, v_from_stripes, p_to_belt, coalesce(p_to_stripes,0),
     coalesce(p_date, current_date), coalesce(v_who,'staff'), p_notes);
end;
$$;


-- ===================== ATTENDANCE INTEGRITY: one check-in per enrollment per day =====================
-- 038_attendance_unique.sql
-- Attendance had no uniqueness rule, so a student could be recorded twice for the
-- same day (two devices, a re-check after a failed load, a back-dated log of a day
-- already recorded). Duplicates inflate classes_since_promo — the number that drives
-- promotion eligibility. De-dupe existing rows (keep the earliest per student+date),
-- then enforce one attendance row per enrollment per day. (attendance has no audit
-- trigger, so no skip needed.)

delete from attendance a
using attendance b
where a.enrollment_id = b.enrollment_id
  and a.class_date    = b.class_date
  and a.id > b.id;

create unique index if not exists uq_attendance_enrollment_date
  on attendance (enrollment_id, class_date);

-- The old non-unique index on the same columns is now redundant.
drop index if exists idx_attendance_enrollment_date;


-- ===================== ATTENDANCE: staff may remove a mistaken check-in =====================
-- 039_attendance_staff_delete.sql
-- Allow instructors / front-desk (any staff) to remove an attendance entry — e.g.
-- when a check-in was recorded under the wrong date — not just the owner.
-- Recording attendance was already staff-level; removing a mistake should be too.

drop policy if exists "owner delete" on public.attendance;
create policy "staff delete" on public.attendance
  for delete to authenticated using (public.is_staff());


-- ===================== STAFF CARD: last-promotion on the privacy-safe roster view =====================
-- 040_checkin_roster_lastpromo.sql
-- Add last_promotion_date to the staff-facing roster view so staff can see a
-- student's rank history (last promotion + time in belt) without access to the
-- owner-only students table or contact PII. Keeps the is_staff() guard.

drop view if exists public.v_checkin_roster;
create view public.v_checkin_roster with (security_invoker = false) as
  select e.id as enrollment_id, e.student_id, s.first_name, s.last_name,
         e.program, e.class_group, e.belt, e.stripes, e.promo_approved,
         e.last_promotion_date
  from enrollments e
  join students s on s.id = e.student_id
  where e.status = 'active' and public.is_staff();
grant select on v_checkin_roster to authenticated;
