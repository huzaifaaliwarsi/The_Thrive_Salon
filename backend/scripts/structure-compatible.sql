--
-- PostgreSQL database dump
--

-- \restrict XjZokesH8J6drFNQe6hK6LU4Hq0eulaJUnX2ZYAmHT31uuSU0VF0qSQif09ACB3

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
-- SET transaction_timeout = 0; -- Not supported in PostgreSQL 10
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET search_path TO public, pg_catalog;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

-- Native UUID generator without external server dependencies (works on any PostgreSQL 10)
CREATE OR REPLACE FUNCTION public.gen_random_uuid() RETURNS uuid AS $$
BEGIN
    RETURN md5(random()::text || clock_timestamp()::text)::uuid;
END;
$$ LANGUAGE plpgsql;

-- Clean drop of existing tables and types for idempotent execution
DROP TABLE IF EXISTS public._sys_config CASCADE;
DROP TABLE IF EXISTS public.appointments CASCADE;
DROP TABLE IF EXISTS public.attendance CASCADE;
DROP TABLE IF EXISTS public.attendance_locks CASCADE;
DROP TABLE IF EXISTS public.clients CASCADE;
DROP TABLE IF EXISTS public.expenses CASCADE;
DROP TABLE IF EXISTS public.inventory_items CASCADE;
DROP TABLE IF EXISTS public.inventory_transactions CASCADE;
DROP TABLE IF EXISTS public.ledger_entries CASCADE;
DROP TABLE IF EXISTS public.purchases CASCADE;
DROP TABLE IF EXISTS public.salary_deductions CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.salons CASCADE;
DROP TABLE IF EXISTS public.service_package_items CASCADE;
DROP TABLE IF EXISTS public.services CASCADE;
DROP TABLE IF EXISTS public.staff CASCADE;
DROP TABLE IF EXISTS public.staff_salary_history CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;
DROP TABLE IF EXISTS public.vendors CASCADE;

DROP TYPE IF EXISTS public.appointment_status CASCADE;
DROP TYPE IF EXISTS public.approval_status CASCADE;
DROP TYPE IF EXISTS public.attendance_status CASCADE;
DROP TYPE IF EXISTS public.salary_type CASCADE;
DROP TYPE IF EXISTS public.user_role CASCADE;

--
-- Name: appointment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.appointment_status AS ENUM (
    'PENDING',
    'CONFIRMED',
    'COMPLETED',
    'CANCELLED',
    'PENDING_CHECKOUT'
);


--
-- Name: approval_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.approval_status AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED'
);


--
-- Name: attendance_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.attendance_status AS ENUM (
    'PRESENT',
    'ABSENT',
    'LEAVE',
    'LATE',
    'SUNDAY',
    'HOLIDAY'
);


--
-- Name: salary_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.salary_type AS ENUM (
    'MONTHLY',
    'DAILY',
    'COMMISSION',
    'MONTHLY_PLUS_COMMISSION',
    'DAILY_PLUS_COMMISSION'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'SUPER_ADMIN',
    'OWNER',
    'STAFF'
);


SET default_tablespace = '';

-- SET default_table_access_method = heap; -- Not supported in PostgreSQL 10

--
-- Name: _sys_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._sys_config (
    key text NOT NULL,
    value text NOT NULL
);


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    service_id uuid,
    service_ids text,
    service_details text,
    staff_id uuid,
    customer_name text NOT NULL,
    customer_phone text,
    appointment_time timestamp without time zone NOT NULL,
    status public.appointment_status DEFAULT 'PENDING'::public.appointment_status,
    notes text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid,
    salon_id uuid,
    status public.attendance_status NOT NULL,
    approval_status public.approval_status DEFAULT 'PENDING'::public.approval_status NOT NULL,
    check_in timestamp without time zone,
    check_out timestamp without time zone,
    early_exit boolean DEFAULT false,
    date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT now(),
    source text DEFAULT 'MANUAL'::text,
    device_sn text
);


--
-- Name: attendance_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_locks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    date date NOT NULL,
    locked_by uuid,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    name text NOT NULL,
    phone text,
    email text,
    notes text,
    source text DEFAULT 'WALK_IN'::text,
    total_spent numeric(10,2) DEFAULT '0'::numeric,
    balance numeric(10,2) DEFAULT '0'::numeric,
    last_visit timestamp without time zone,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expenses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    name text NOT NULL,
    category text NOT NULL,
    amount numeric(10,2) NOT NULL,
    date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: inventory_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    vendor_id uuid,
    name text NOT NULL,
    sku text,
    stock_quantity numeric(10,2) DEFAULT '0'::numeric,
    unit text NOT NULL,
    unit_price numeric(10,2) DEFAULT '0'::numeric,
    selling_price numeric(10,2) DEFAULT '0'::numeric,
    can_be_sold text DEFAULT 'false'::text,
    expiry_date date,
    low_stock_threshold numeric(10,2) DEFAULT '5'::numeric,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: inventory_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    item_id uuid,
    salon_id uuid,
    type text NOT NULL,
    quantity numeric(10,2) NOT NULL,
    date timestamp without time zone DEFAULT now(),
    notes text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    client_id uuid,
    vendor_id uuid,
    staff_id uuid,
    sale_id uuid,
    purchase_id uuid,
    salary_deduction_id uuid,
    expense_id uuid,
    type text NOT NULL,
    amount numeric(10,2) NOT NULL,
    category text NOT NULL,
    notes text,
    person_name text,
    date timestamp without time zone DEFAULT now(),
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: purchases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    vendor_id uuid,
    total numeric(10,2) NOT NULL,
    amount_paid numeric(10,2) DEFAULT '0'::numeric,
    payment_method text NOT NULL,
    date timestamp without time zone DEFAULT now(),
    notes text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: salary_deductions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_deductions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid,
    salon_id uuid,
    type text NOT NULL,
    amount numeric(10,2) NOT NULL,
    reason text,
    date date DEFAULT CURRENT_DATE,
    noted_by uuid,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: sale_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sale_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sale_id uuid,
    service_id uuid,
    product_id uuid,
    staff_id uuid,
    quantity numeric DEFAULT '1'::numeric,
    price numeric(10,2) NOT NULL,
    discount_amount numeric(10,2) DEFAULT '0'::numeric,
    tax_amount numeric(10,2) DEFAULT '0'::numeric,
    commission_amount numeric(10,2) DEFAULT '0'::numeric,
    is_internal boolean DEFAULT false
);


--
-- Name: sales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    staff_id uuid,
    customer_phone text,
    customer_name text,
    customer_source text,
    subtotal numeric(10,2) NOT NULL,
    discount numeric(10,2) DEFAULT '0'::numeric,
    total numeric(10,2) NOT NULL,
    commission_rate numeric(5,2) DEFAULT '0'::numeric,
    tax_rate numeric(5,2) DEFAULT '0'::numeric,
    tax_amount numeric(10,2) DEFAULT '0'::numeric,
    status text DEFAULT 'ACTIVE'::text,
    void_reason text,
    payment_method text NOT NULL,
    amount_paid numeric(10,2),
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: salons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    logo text,
    address text,
    subscription_end timestamp without time zone DEFAULT (now() + '30 days'::interval),
    is_suspended text DEFAULT 'false'::text,
    cash_balance numeric(12,2) DEFAULT '0'::numeric,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    late_time_limit text DEFAULT '09:00'::text,
    timezone text DEFAULT 'Asia/Karachi'::text,
    in_time_limit text DEFAULT '09:00'::text,
    out_time_limit text DEFAULT '18:00'::text,
    early_exit_time_limit text DEFAULT '17:45'::text,
    late_deduction_rate numeric(10,2) DEFAULT '10'::numeric,
    early_exit_deduction_rate numeric(10,2) DEFAULT '10'::numeric,
    vat_number text,
    qr_domain text DEFAULT 'salonpro.app'::text,
    zkteco_device_sn text,
    zkteco_device_name text,
    zkteco_push_token text,
    zkteco_last_sync timestamp without time zone,
    zkteco_enabled boolean DEFAULT false
);


--
-- Name: service_package_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_package_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    package_id uuid,
    service_id uuid,
    price numeric(10,2) DEFAULT '0'::numeric
);


--
-- Name: services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.services (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    name text NOT NULL,
    price numeric(10,2) NOT NULL,
    category text NOT NULL,
    is_active text DEFAULT 'true'::text,
    is_package text DEFAULT 'false'::text,
    description text,
    arabic_name text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    salon_id uuid,
    name text NOT NULL,
    phone text,
    salary_type public.salary_type NOT NULL,
    salary_value numeric(10,2),
    commission_percentage numeric(5,2) DEFAULT '0'::numeric,
    in_time_limit text DEFAULT '09:00'::text,
    out_time_limit text DEFAULT '18:00'::text,
    late_time_limit text DEFAULT '09:15'::text,
    early_exit_time_limit text DEFAULT '17:45'::text,
    late_deduction_rate numeric(10,2) DEFAULT '0'::numeric,
    early_exit_deduction_rate numeric(10,2) DEFAULT '0'::numeric,
    allowed_leaves integer DEFAULT 0,
    joining_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT now(),
    biometric_pin text
);


--
-- Name: staff_salary_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_salary_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    staff_id uuid,
    salon_id uuid,
    salary_type public.salary_type NOT NULL,
    salary_value numeric(10,2),
    commission_percentage numeric(5,2) DEFAULT '0'::numeric,
    effective_date date NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    phone text,
    password text NOT NULL,
    plain_password text,
    role public.user_role NOT NULL,
    salon_id uuid,
    name text,
    is_active text DEFAULT 'true'::text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: vendors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vendors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salon_id uuid,
    name text NOT NULL,
    contact_person text,
    phone text,
    email text,
    address text,
    balance numeric(10,2) DEFAULT '0'::numeric,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: _sys_config _sys_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._sys_config
    ADD CONSTRAINT _sys_config_pkey PRIMARY KEY (key);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: attendance_locks attendance_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_locks
    ADD CONSTRAINT attendance_locks_pkey PRIMARY KEY (id);


--
-- Name: attendance_locks attendance_locks_salon_date_idx; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_locks
    ADD CONSTRAINT attendance_locks_salon_date_idx UNIQUE (salon_id, date);


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- Name: inventory_items inventory_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_items
    ADD CONSTRAINT inventory_items_pkey PRIMARY KEY (id);


--
-- Name: inventory_transactions inventory_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_pkey PRIMARY KEY (id);


--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: purchases purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_pkey PRIMARY KEY (id);


--
-- Name: salary_deductions salary_deductions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_deductions
    ADD CONSTRAINT salary_deductions_pkey PRIMARY KEY (id);


--
-- Name: sale_items sale_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_pkey PRIMARY KEY (id);


--
-- Name: sales sales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_pkey PRIMARY KEY (id);


--
-- Name: salons salons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salons
    ADD CONSTRAINT salons_pkey PRIMARY KEY (id);


--
-- Name: service_package_items service_package_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_package_items
    ADD CONSTRAINT service_package_items_pkey PRIMARY KEY (id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


--
-- Name: staff_salary_history staff_salary_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salary_history
    ADD CONSTRAINT staff_salary_history_pkey PRIMARY KEY (id);


--
-- Name: users users_email_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_unique UNIQUE (email);


--
-- Name: users users_phone_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_unique UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vendors vendors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_pkey PRIMARY KEY (id);


--
-- Name: attendance_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_date_idx ON public.attendance USING btree (date);


--
-- Name: attendance_salon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_salon_idx ON public.attendance USING btree (salon_id);


--
-- Name: attendance_staff_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX attendance_staff_idx ON public.attendance USING btree (staff_id);


--
-- Name: expenses_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expenses_date_idx ON public.expenses USING btree (date);


--
-- Name: expenses_salon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expenses_salon_idx ON public.expenses USING btree (salon_id);


--
-- Name: inv_trans_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inv_trans_date_idx ON public.inventory_transactions USING btree (date);


--
-- Name: inv_trans_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inv_trans_item_idx ON public.inventory_transactions USING btree (item_id);


--
-- Name: inv_trans_salon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inv_trans_salon_idx ON public.inventory_transactions USING btree (salon_id);


--
-- Name: ledger_client_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ledger_client_idx ON public.ledger_entries USING btree (client_id);


--
-- Name: ledger_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ledger_date_idx ON public.ledger_entries USING btree (date);


--
-- Name: ledger_salon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ledger_salon_idx ON public.ledger_entries USING btree (salon_id);


--
-- Name: ledger_staff_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ledger_staff_idx ON public.ledger_entries USING btree (staff_id);


--
-- Name: ledger_vendor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ledger_vendor_idx ON public.ledger_entries USING btree (vendor_id);


--
-- Name: sale_items_internal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_items_internal_idx ON public.sale_items USING btree (is_internal);


--
-- Name: sale_items_sale_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_items_sale_idx ON public.sale_items USING btree (sale_id);


--
-- Name: sale_items_staff_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sale_items_staff_idx ON public.sale_items USING btree (staff_id);


--
-- Name: sales_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_created_at_idx ON public.sales USING btree (created_at);


--
-- Name: sales_customer_phone_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_customer_phone_idx ON public.sales USING btree (customer_phone);


--
-- Name: sales_salon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_salon_idx ON public.sales USING btree (salon_id);


--
-- Name: appointments appointments_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: appointments appointments_service_id_services_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_service_id_services_id_fk FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE SET NULL;


--
-- Name: appointments appointments_staff_id_staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_staff_id_staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: attendance_locks attendance_locks_locked_by_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_locks
    ADD CONSTRAINT attendance_locks_locked_by_users_id_fk FOREIGN KEY (locked_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: attendance_locks attendance_locks_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_locks
    ADD CONSTRAINT attendance_locks_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: attendance attendance_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: attendance attendance_staff_id_staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_staff_id_staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: clients clients_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: expenses expenses_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: inventory_items inventory_items_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_items
    ADD CONSTRAINT inventory_items_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: inventory_items inventory_items_vendor_id_vendors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_items
    ADD CONSTRAINT inventory_items_vendor_id_vendors_id_fk FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE SET NULL;


--
-- Name: inventory_transactions inventory_transactions_item_id_inventory_items_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_item_id_inventory_items_id_fk FOREIGN KEY (item_id) REFERENCES public.inventory_items(id) ON DELETE CASCADE;


--
-- Name: inventory_transactions inventory_transactions_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_expense_id_expenses_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_expense_id_expenses_id_fk FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_purchase_id_purchases_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_purchase_id_purchases_id_fk FOREIGN KEY (purchase_id) REFERENCES public.purchases(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_salary_deduction_id_salary_deductions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_salary_deduction_id_salary_deductions_id_fk FOREIGN KEY (salary_deduction_id) REFERENCES public.salary_deductions(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_sale_id_sales_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_sale_id_sales_id_fk FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_staff_id_staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_staff_id_staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: ledger_entries ledger_entries_vendor_id_vendors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_vendor_id_vendors_id_fk FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE CASCADE;


--
-- Name: purchases purchases_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: purchases purchases_vendor_id_vendors_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_vendor_id_vendors_id_fk FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE SET NULL;


--
-- Name: salary_deductions salary_deductions_noted_by_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_deductions
    ADD CONSTRAINT salary_deductions_noted_by_users_id_fk FOREIGN KEY (noted_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: salary_deductions salary_deductions_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_deductions
    ADD CONSTRAINT salary_deductions_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: salary_deductions salary_deductions_staff_id_staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_deductions
    ADD CONSTRAINT salary_deductions_staff_id_staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: sale_items sale_items_product_id_inventory_items_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_product_id_inventory_items_id_fk FOREIGN KEY (product_id) REFERENCES public.inventory_items(id) ON DELETE SET NULL;


--
-- Name: sale_items sale_items_sale_id_sales_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_sale_id_sales_id_fk FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE;


--
-- Name: sale_items sale_items_service_id_services_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_service_id_services_id_fk FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE SET NULL;


--
-- Name: sale_items sale_items_staff_id_staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sale_items
    ADD CONSTRAINT sale_items_staff_id_staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: sales sales_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: sales sales_staff_id_staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_staff_id_staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: service_package_items service_package_items_package_id_services_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_package_items
    ADD CONSTRAINT service_package_items_package_id_services_id_fk FOREIGN KEY (package_id) REFERENCES public.services(id) ON DELETE CASCADE;


--
-- Name: service_package_items service_package_items_service_id_services_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_package_items
    ADD CONSTRAINT service_package_items_service_id_services_id_fk FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE CASCADE;


--
-- Name: services services_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: staff_salary_history staff_salary_history_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salary_history
    ADD CONSTRAINT staff_salary_history_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: staff_salary_history staff_salary_history_staff_id_staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_salary_history
    ADD CONSTRAINT staff_salary_history_staff_id_staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff staff_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: staff staff_user_id_users_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_user_id_users_id_fk FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- Name: vendors vendors_salon_id_salons_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_salon_id_salons_id_fk FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

-- \unrestrict XjZokesH8J6drFNQe6hK6LU4Hq0eulaJUnX2ZYAmHT31uuSU0VF0qSQif09ACB3

