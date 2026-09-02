/*
# Add Domain Tables for Banking, Hospital, HR, IT, and Procurement

## Overview
Extends the system from a general support copilot into a multi-industry platform.
Adds new user roles, domain-specific tables with RLS, and SECURITY DEFINER
access-control functions following the same pattern as the existing schema.

## New Roles (added to user_role enum)
- bank_teller — banking staff, can access bank accounts and transactions
- doctor — healthcare staff, can access patient records and appointments
- hr_admin — HR staff, can access employee data and leave requests
- it_admin — IT staff, can access IT tickets and procurement

## New Tables — Banking
- bank_accounts: customer bank accounts (checking, savings, credit)
- transactions: account transactions (debit, credit, transfer, fee)
- cards: debit/credit cards linked to accounts
- disputes: transaction disputes
- loans: customer loans with balance and payment info

## New Tables — Hospital
- patients: patient records linked to app_users or customers
- appointments: scheduled appointments with department and doctor
- prescriptions: patient prescriptions with refill tracking
- lab_results: lab test results with status tracking
- medical_records: patient diagnoses and notes with access-level control

## New Tables — HR
- hr_employees: employee HR profiles linked to app_users
- leave_requests: time-off requests with approval workflow
- pay_stubs: payroll records with gross/net/deductions

## New Tables — IT
- it_tickets: IT support tickets with category and assignment

## New Tables — Procurement
- purchase_orders: purchase orders with vendor and approval workflow

## Security
- RLS enabled on every new table
- SECURITY DEFINER functions for each domain's access control
- All functions follow existing pattern: admin → all, staff roles → all,
  employee → own data only
- 4 policies per table (SELECT, INSERT, UPDATE, DELETE) using the
  access-control functions

## Important Notes
1. The user_role enum is extended with ALTER TYPE ADD VALUE IF NOT EXISTS
2. Existing can_access_customer function is replaced to handle new roles
3. All new tables use text primary keys for domain IDs (matching existing
   pattern of ORD-XXXX, INV-XXXX, etc.)
4. Foreign keys reference existing customers and auth.users tables
*/

-- ============================================================
-- EXTEND USER_ROLE ENUM
-- ============================================================
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'bank_teller';
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'doctor';
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'hr_admin';
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'it_admin';

-- ============================================================
-- HELPER: is_staff_role — true for any non-employee role
-- ============================================================
CREATE OR REPLACE FUNCTION is_staff_role(p_role text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p_role IN ('admin', 'support_agent', 'finance_user',
    'bank_teller', 'doctor', 'hr_admin', 'it_admin');
$$;

-- ============================================================
-- UPDATE EXISTING can_access_customer to handle new roles
-- ============================================================
CREATE OR REPLACE FUNCTION can_access_customer(p_customer_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN get_current_role() = 'admin' THEN true
    WHEN is_staff_role(get_current_role()) THEN true
    WHEN get_current_role() = 'employee' THEN
      EXISTS (SELECT 1 FROM app_users WHERE id = auth.uid() AND customer_id = p_customer_id)
    ELSE false
  END;
$$;

-- ============================================================
-- BANKING TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS bank_accounts (
  account_id text PRIMARY KEY,
  customer_id text NOT NULL REFERENCES customers(customer_id),
  account_type text NOT NULL DEFAULT 'checking',
  balance numeric(12,2) NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'USD',
  status text NOT NULL DEFAULT 'active',
  opened_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transactions (
  transaction_id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES bank_accounts(account_id),
  customer_id text NOT NULL REFERENCES customers(customer_id),
  amount numeric(12,2) NOT NULL,
  type text NOT NULL DEFAULT 'debit',
  description text,
  merchant text,
  status text NOT NULL DEFAULT 'posted',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cards (
  card_id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES bank_accounts(account_id),
  customer_id text NOT NULL REFERENCES customers(customer_id),
  card_type text NOT NULL DEFAULT 'debit',
  last4 text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  expiry_month int NOT NULL,
  expiry_year int NOT NULL,
  issued_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS disputes (
  dispute_id text PRIMARY KEY,
  transaction_id text NOT NULL REFERENCES transactions(transaction_id),
  customer_id text NOT NULL REFERENCES customers(customer_id),
  reason text,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS loans (
  loan_id text PRIMARY KEY,
  customer_id text NOT NULL REFERENCES customers(customer_id),
  loan_type text NOT NULL,
  principal numeric(12,2) NOT NULL,
  interest_rate numeric(5,2) NOT NULL,
  remaining_balance numeric(12,2) NOT NULL,
  monthly_payment numeric(12,2) NOT NULL,
  status text NOT NULL DEFAULT 'active',
  term_months int NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Banking indexes
CREATE INDEX IF NOT EXISTS idx_bank_accounts_customer ON bank_accounts(customer_id);
CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_transactions_customer ON transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_cards_account ON cards(account_id);
CREATE INDEX IF NOT EXISTS idx_cards_customer ON cards(customer_id);
CREATE INDEX IF NOT EXISTS idx_disputes_customer ON disputes(customer_id);
CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id);

-- Banking RLS
ALTER TABLE bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE loans ENABLE ROW LEVEL SECURITY;

-- Access functions
CREATE OR REPLACE FUNCTION can_access_bank_account(p_account_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM bank_accounts ba
    WHERE ba.account_id = p_account_id
    AND CASE
      WHEN get_current_role() = 'admin' THEN true
      WHEN is_staff_role(get_current_role()) THEN true
      WHEN get_current_role() = 'employee' THEN
        EXISTS (SELECT 1 FROM app_users WHERE id = auth.uid() AND customer_id = ba.customer_id)
      ELSE false
    END
  );
$$;

CREATE OR REPLACE FUNCTION can_access_bank_customer(p_customer_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT can_access_customer(p_customer_id);
$$;

-- bank_accounts policies
DROP POLICY IF EXISTS "select_bank_accounts" ON bank_accounts;
CREATE POLICY "select_bank_accounts" ON bank_accounts FOR SELECT
  TO authenticated USING (can_access_customer(customer_id));
DROP POLICY IF EXISTS "insert_bank_accounts" ON bank_accounts;
CREATE POLICY "insert_bank_accounts" ON bank_accounts FOR INSERT
  TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "update_bank_accounts" ON bank_accounts;
CREATE POLICY "update_bank_accounts" ON bank_accounts FOR UPDATE
  TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_bank_accounts" ON bank_accounts;
CREATE POLICY "delete_bank_accounts" ON bank_accounts FOR DELETE
  TO authenticated USING (is_admin());

-- transactions policies
DROP POLICY IF EXISTS "select_transactions" ON transactions;
CREATE POLICY "select_transactions" ON transactions FOR SELECT
  TO authenticated USING (can_access_customer(customer_id));
DROP POLICY IF EXISTS "insert_transactions" ON transactions;
CREATE POLICY "insert_transactions" ON transactions FOR INSERT
  TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "update_transactions" ON transactions;
CREATE POLICY "update_transactions" ON transactions FOR UPDATE
  TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_transactions" ON transactions;
CREATE POLICY "delete_transactions" ON transactions FOR DELETE
  TO authenticated USING (is_admin());

-- cards policies
DROP POLICY IF EXISTS "select_cards" ON cards;
CREATE POLICY "select_cards" ON cards FOR SELECT
  TO authenticated USING (can_access_customer(customer_id));
DROP POLICY IF EXISTS "insert_cards" ON cards;
CREATE POLICY "insert_cards" ON cards FOR INSERT
  TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "update_cards" ON cards;
CREATE POLICY "update_cards" ON cards FOR UPDATE
  TO authenticated USING (can_access_customer(customer_id)) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_cards" ON cards;
CREATE POLICY "delete_cards" ON cards FOR DELETE
  TO authenticated USING (is_admin());

-- disputes policies
DROP POLICY IF EXISTS "select_disputes" ON disputes;
CREATE POLICY "select_disputes" ON disputes FOR SELECT
  TO authenticated USING (can_access_customer(customer_id));
DROP POLICY IF EXISTS "insert_disputes" ON disputes;
CREATE POLICY "insert_disputes" ON disputes FOR INSERT
  TO authenticated WITH CHECK (can_access_customer(customer_id));
DROP POLICY IF EXISTS "update_disputes" ON disputes;
CREATE POLICY "update_disputes" ON disputes FOR UPDATE
  TO authenticated USING (can_access_customer(customer_id)) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_disputes" ON disputes;
CREATE POLICY "delete_disputes" ON disputes FOR DELETE
  TO authenticated USING (is_admin());

-- loans policies
DROP POLICY IF EXISTS "select_loans" ON loans;
CREATE POLICY "select_loans" ON loans FOR SELECT
  TO authenticated USING (can_access_customer(customer_id));
DROP POLICY IF EXISTS "insert_loans" ON loans;
CREATE POLICY "insert_loans" ON loans FOR INSERT
  TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "update_loans" ON loans;
CREATE POLICY "update_loans" ON loans FOR UPDATE
  TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_loans" ON loans;
CREATE POLICY "delete_loans" ON loans FOR DELETE
  TO authenticated USING (is_admin());

-- ============================================================
-- HOSPITAL TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS patients (
  patient_id text PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id),
  customer_id text REFERENCES customers(customer_id),
  full_name text NOT NULL,
  date_of_birth date,
  phone text,
  email text,
  insurance_provider text,
  insurance_id text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS appointments (
  appointment_id text PRIMARY KEY,
  patient_id text NOT NULL REFERENCES patients(patient_id),
  department text NOT NULL,
  doctor_name text,
  scheduled_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'scheduled',
  reason text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS prescriptions (
  prescription_id text PRIMARY KEY,
  patient_id text NOT NULL REFERENCES patients(patient_id),
  medication text NOT NULL,
  dosage text NOT NULL,
  refills_remaining int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'active',
  prescribed_by text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lab_results (
  result_id text PRIMARY KEY,
  patient_id text NOT NULL REFERENCES patients(patient_id),
  test_name text NOT NULL,
  result_value text,
  result_unit text,
  status text NOT NULL DEFAULT 'pending',
  notes text,
  ordered_at timestamptz DEFAULT now(),
  result_at timestamptz
);

CREATE TABLE IF NOT EXISTS medical_records (
  record_id text PRIMARY KEY,
  patient_id text NOT NULL REFERENCES patients(patient_id),
  diagnosis text NOT NULL,
  notes text,
  access_level doc_access_level NOT NULL DEFAULT 'internal',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- Hospital indexes
CREATE INDEX IF NOT EXISTS idx_patients_user ON patients(user_id);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON appointments(patient_id);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON appointments(status);
CREATE INDEX IF NOT EXISTS idx_prescriptions_patient ON prescriptions(patient_id);
CREATE INDEX IF NOT EXISTS idx_lab_results_patient ON lab_results(patient_id);
CREATE INDEX IF NOT EXISTS idx_medical_records_patient ON medical_records(patient_id);

-- Hospital RLS
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_records ENABLE ROW LEVEL SECURITY;

-- Access function
CREATE OR REPLACE FUNCTION can_access_patient(p_patient_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM patients p
    WHERE p.patient_id = p_patient_id
    AND CASE
      WHEN get_current_role() = 'admin' THEN true
      WHEN get_current_role() = 'doctor' THEN true
      WHEN get_current_role() = 'support_agent' THEN true
      WHEN get_current_role() = 'employee' THEN
        p.user_id = auth.uid()
        OR EXISTS (SELECT 1 FROM app_users WHERE id = auth.uid() AND customer_id = p.customer_id)
      ELSE false
    END
  );
$$;

-- patients policies
DROP POLICY IF EXISTS "select_patients" ON patients;
CREATE POLICY "select_patients" ON patients FOR SELECT
  TO authenticated USING (
    get_current_role() IN ('admin', 'doctor', 'support_agent')
    OR user_id = auth.uid()
  );
DROP POLICY IF EXISTS "insert_patients" ON patients;
CREATE POLICY "insert_patients" ON patients FOR INSERT
  TO authenticated WITH CHECK (is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "update_patients" ON patients;
CREATE POLICY "update_patients" ON patients FOR UPDATE
  TO authenticated USING (is_staff_role(get_current_role())) WITH CHECK (is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "delete_patients" ON patients;
CREATE POLICY "delete_patients" ON patients FOR DELETE
  TO authenticated USING (is_admin());

-- appointments policies
DROP POLICY IF EXISTS "select_appointments" ON appointments;
CREATE POLICY "select_appointments" ON appointments FOR SELECT
  TO authenticated USING (can_access_patient(patient_id));
DROP POLICY IF EXISTS "insert_appointments" ON appointments;
CREATE POLICY "insert_appointments" ON appointments FOR INSERT
  TO authenticated WITH CHECK (is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "update_appointments" ON appointments;
CREATE POLICY "update_appointments" ON appointments FOR UPDATE
  TO authenticated USING (can_access_patient(patient_id)) WITH CHECK (is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "delete_appointments" ON appointments;
CREATE POLICY "delete_appointments" ON appointments FOR DELETE
  TO authenticated USING (is_admin());

-- prescriptions policies
DROP POLICY IF EXISTS "select_prescriptions" ON prescriptions;
CREATE POLICY "select_prescriptions" ON prescriptions FOR SELECT
  TO authenticated USING (can_access_patient(patient_id));
DROP POLICY IF EXISTS "insert_prescriptions" ON prescriptions;
CREATE POLICY "insert_prescriptions" ON prescriptions FOR INSERT
  TO authenticated WITH CHECK (get_current_role() IN ('admin', 'doctor'));
DROP POLICY IF EXISTS "update_prescriptions" ON prescriptions;
CREATE POLICY "update_prescriptions" ON prescriptions FOR UPDATE
  TO authenticated USING (can_access_patient(patient_id)) WITH CHECK (get_current_role() IN ('admin', 'doctor'));
DROP POLICY IF EXISTS "delete_prescriptions" ON prescriptions;
CREATE POLICY "delete_prescriptions" ON prescriptions FOR DELETE
  TO authenticated USING (is_admin());

-- lab_results policies
DROP POLICY IF EXISTS "select_lab_results" ON lab_results;
CREATE POLICY "select_lab_results" ON lab_results FOR SELECT
  TO authenticated USING (can_access_patient(patient_id));
DROP POLICY IF EXISTS "insert_lab_results" ON lab_results;
CREATE POLICY "insert_lab_results" ON lab_results FOR INSERT
  TO authenticated WITH CHECK (get_current_role() IN ('admin', 'doctor'));
DROP POLICY IF EXISTS "update_lab_results" ON lab_results;
CREATE POLICY "update_lab_results" ON lab_results FOR UPDATE
  TO authenticated USING (can_access_patient(patient_id)) WITH CHECK (get_current_role() IN ('admin', 'doctor'));
DROP POLICY IF EXISTS "delete_lab_results" ON lab_results;
CREATE POLICY "delete_lab_results" ON lab_results FOR DELETE
  TO authenticated USING (is_admin());

-- medical_records policies
DROP POLICY IF EXISTS "select_medical_records" ON medical_records;
CREATE POLICY "select_medical_records" ON medical_records FOR SELECT
  TO authenticated USING (can_access_patient(patient_id));
DROP POLICY IF EXISTS "insert_medical_records" ON medical_records;
CREATE POLICY "insert_medical_records" ON medical_records FOR INSERT
  TO authenticated WITH CHECK (get_current_role() IN ('admin', 'doctor'));
DROP POLICY IF EXISTS "update_medical_records" ON medical_records;
CREATE POLICY "update_medical_records" ON medical_records FOR UPDATE
  TO authenticated USING (can_access_patient(patient_id)) WITH CHECK (get_current_role() IN ('admin', 'doctor'));
DROP POLICY IF EXISTS "delete_medical_records" ON medical_records;
CREATE POLICY "delete_medical_records" ON medical_records FOR DELETE
  TO authenticated USING (is_admin());

-- ============================================================
-- HR TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_employees (
  employee_id text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  department text NOT NULL,
  hire_date date NOT NULL,
  leave_balance numeric(5,1) NOT NULL DEFAULT 20.0,
  manager_name text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS leave_requests (
  request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id text NOT NULL REFERENCES hr_employees(employee_id),
  leave_type text NOT NULL DEFAULT 'annual',
  start_date date NOT NULL,
  end_date date NOT NULL,
  days numeric(5,1) NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  reason text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pay_stubs (
  stub_id text PRIMARY KEY,
  employee_id text NOT NULL REFERENCES hr_employees(employee_id),
  pay_period_start date NOT NULL,
  pay_period_end date NOT NULL,
  gross_amount numeric(12,2) NOT NULL,
  net_amount numeric(12,2) NOT NULL,
  deductions numeric(12,2) NOT NULL DEFAULT 0,
  pay_date date NOT NULL
);

-- HR indexes
CREATE INDEX IF NOT EXISTS idx_hr_employees_user ON hr_employees(user_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_pay_stubs_employee ON pay_stubs(employee_id);

-- HR RLS
ALTER TABLE hr_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_stubs ENABLE ROW LEVEL SECURITY;

-- Access function
CREATE OR REPLACE FUNCTION can_access_hr_employee(p_employee_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM hr_employees e
    WHERE e.employee_id = p_employee_id
    AND CASE
      WHEN get_current_role() = 'admin' THEN true
      WHEN get_current_role() = 'hr_admin' THEN true
      WHEN get_current_role() = 'support_agent' THEN true
      WHEN get_current_role() = 'employee' THEN e.user_id = auth.uid()
      ELSE false
    END
  );
$$;

-- hr_employees policies
DROP POLICY IF EXISTS "select_hr_employees" ON hr_employees;
CREATE POLICY "select_hr_employees" ON hr_employees FOR SELECT
  TO authenticated USING (can_access_hr_employee(employee_id));
DROP POLICY IF EXISTS "insert_hr_employees" ON hr_employees;
CREATE POLICY "insert_hr_employees" ON hr_employees FOR INSERT
  TO authenticated WITH CHECK (get_current_role() IN ('admin', 'hr_admin'));
DROP POLICY IF EXISTS "update_hr_employees" ON hr_employees;
CREATE POLICY "update_hr_employees" ON hr_employees FOR UPDATE
  TO authenticated USING (get_current_role() IN ('admin', 'hr_admin')) WITH CHECK (get_current_role() IN ('admin', 'hr_admin'));
DROP POLICY IF EXISTS "delete_hr_employees" ON hr_employees;
CREATE POLICY "delete_hr_employees" ON hr_employees FOR DELETE
  TO authenticated USING (is_admin());

-- leave_requests policies
DROP POLICY IF EXISTS "select_leave_requests" ON leave_requests;
CREATE POLICY "select_leave_requests" ON leave_requests FOR SELECT
  TO authenticated USING (can_access_hr_employee(employee_id));
DROP POLICY IF EXISTS "insert_leave_requests" ON leave_requests;
CREATE POLICY "insert_leave_requests" ON leave_requests FOR INSERT
  TO authenticated WITH CHECK (can_access_hr_employee(employee_id));
DROP POLICY IF EXISTS "update_leave_requests" ON leave_requests;
CREATE POLICY "update_leave_requests" ON leave_requests FOR UPDATE
  TO authenticated USING (get_current_role() IN ('admin', 'hr_admin')) WITH CHECK (get_current_role() IN ('admin', 'hr_admin'));
DROP POLICY IF EXISTS "delete_leave_requests" ON leave_requests;
CREATE POLICY "delete_leave_requests" ON leave_requests FOR DELETE
  TO authenticated USING (is_admin());

-- pay_stubs policies
DROP POLICY IF EXISTS "select_pay_stubs" ON pay_stubs;
CREATE POLICY "select_pay_stubs" ON pay_stubs FOR SELECT
  TO authenticated USING (can_access_hr_employee(employee_id));
DROP POLICY IF EXISTS "insert_pay_stubs" ON pay_stubs;
CREATE POLICY "insert_pay_stubs" ON pay_stubs FOR INSERT
  TO authenticated WITH CHECK (get_current_role() IN ('admin', 'hr_admin'));
DROP POLICY IF EXISTS "update_pay_stubs" ON pay_stubs;
CREATE POLICY "update_pay_stubs" ON pay_stubs FOR UPDATE
  TO authenticated USING (get_current_role() IN ('admin', 'hr_admin')) WITH CHECK (get_current_role() IN ('admin', 'hr_admin'));
DROP POLICY IF EXISTS "delete_pay_stubs" ON pay_stubs;
CREATE POLICY "delete_pay_stubs" ON pay_stubs FOR DELETE
  TO authenticated USING (is_admin());

-- ============================================================
-- IT TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS it_tickets (
  ticket_id text PRIMARY KEY,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  category text NOT NULL DEFAULT 'other',
  priority text NOT NULL DEFAULT 'medium',
  status text NOT NULL DEFAULT 'open',
  subject text NOT NULL,
  description text,
  assigned_to text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- IT indexes
CREATE INDEX IF NOT EXISTS idx_it_tickets_requested_by ON it_tickets(requested_by);
CREATE INDEX IF NOT EXISTS idx_it_tickets_status ON it_tickets(status);

-- IT RLS
ALTER TABLE it_tickets ENABLE ROW LEVEL SECURITY;

-- Access function
CREATE OR REPLACE FUNCTION can_access_it_ticket(p_ticket_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM it_tickets t
    WHERE t.ticket_id = p_ticket_id
    AND CASE
      WHEN get_current_role() = 'admin' THEN true
      WHEN get_current_role() = 'it_admin' THEN true
      WHEN get_current_role() = 'support_agent' THEN true
      WHEN get_current_role() = 'employee' THEN t.requested_by = auth.uid()
      ELSE false
    END
  );
$$;

-- it_tickets policies
DROP POLICY IF EXISTS "select_it_tickets" ON it_tickets;
CREATE POLICY "select_it_tickets" ON it_tickets FOR SELECT
  TO authenticated USING (can_access_it_ticket(ticket_id));
DROP POLICY IF EXISTS "insert_it_tickets" ON it_tickets;
CREATE POLICY "insert_it_tickets" ON it_tickets FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = requested_by OR is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "update_it_tickets" ON it_tickets;
CREATE POLICY "update_it_tickets" ON it_tickets FOR UPDATE
  TO authenticated USING (is_staff_role(get_current_role())) WITH CHECK (is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "delete_it_tickets" ON it_tickets;
CREATE POLICY "delete_it_tickets" ON it_tickets FOR DELETE
  TO authenticated USING (is_admin());

-- ============================================================
-- PROCUREMENT TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS purchase_orders (
  po_id text PRIMARY KEY,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  vendor text NOT NULL,
  item_description text NOT NULL,
  quantity int NOT NULL DEFAULT 1,
  unit_price numeric(12,2) NOT NULL,
  total_amount numeric(12,2) NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  created_at timestamptz DEFAULT now()
);

-- Procurement indexes
CREATE INDEX IF NOT EXISTS idx_purchase_orders_requested_by ON purchase_orders(requested_by);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON purchase_orders(status);

-- Procurement RLS
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;

-- Access function
CREATE OR REPLACE FUNCTION can_access_purchase_order(p_po_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM purchase_orders po
    WHERE po.po_id = p_po_id
    AND CASE
      WHEN get_current_role() = 'admin' THEN true
      WHEN get_current_role() = 'it_admin' THEN true
      WHEN get_current_role() = 'support_agent' THEN true
      WHEN get_current_role() = 'employee' THEN po.requested_by = auth.uid()
      ELSE false
    END
  );
$$;

-- purchase_orders policies
DROP POLICY IF EXISTS "select_purchase_orders" ON purchase_orders;
CREATE POLICY "select_purchase_orders" ON purchase_orders FOR SELECT
  TO authenticated USING (can_access_purchase_order(po_id));
DROP POLICY IF EXISTS "insert_purchase_orders" ON purchase_orders;
CREATE POLICY "insert_purchase_orders" ON purchase_orders FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = requested_by OR is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "update_purchase_orders" ON purchase_orders;
CREATE POLICY "update_purchase_orders" ON purchase_orders FOR UPDATE
  TO authenticated USING (is_staff_role(get_current_role())) WITH CHECK (is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "delete_purchase_orders" ON purchase_orders;
CREATE POLICY "delete_purchase_orders" ON purchase_orders FOR DELETE
  TO authenticated USING (is_admin());