/*
# Seed Demo Data for All New Domains

## Overview
Populates banking, hospital, HR, IT, and procurement tables with realistic
demo data linked to existing customers (CUST-1001, CUST-1002, CUST-1003).

## Banking Data
- 3 bank accounts (checking, savings, credit) for Acme, Globex, Initech
- 10 transactions across accounts
- 3 cards linked to accounts
- 2 disputes
- 2 loans

## Hospital Data
- 3 patients linked to customers
- 4 appointments (scheduled, completed, cancelled)
- 3 prescriptions
- 3 lab results (completed, pending)
- 2 medical records

## HR Data
- 3 HR employee profiles
- 3 leave requests (pending, approved, rejected)
- 3 pay stubs

## IT Data
- 3 IT tickets (open, in_progress, resolved)

## Procurement Data
- 3 purchase orders (draft, approved, delivered)
*/

-- ============================================================
-- BANKING DATA
-- ============================================================
INSERT INTO bank_accounts (account_id, customer_id, account_type, balance, currency, status) VALUES
('ACC-2001', 'CUST-1001', 'checking', 45800.50, 'USD', 'active'),
('ACC-2002', 'CUST-1001', 'savings', 125000.00, 'USD', 'active'),
('ACC-2003', 'CUST-1002', 'checking', 23150.75, 'USD', 'active'),
('ACC-2004', 'CUST-1003', 'checking', 8900.20, 'USD', 'active'),
('ACC-2005', 'CUST-1002', 'credit', -3200.00, 'USD', 'active')
ON CONFLICT (account_id) DO NOTHING;

INSERT INTO transactions (transaction_id, account_id, customer_id, amount, type, description, merchant, status) VALUES
('TXN-3001', 'ACC-2001', 'CUST-1001', 1250.00, 'credit', 'Payment received', 'Wire Transfer', 'posted'),
('TXN-3002', 'ACC-2001', 'CUST-1001', 89.99, 'debit', 'Office supplies', 'Staples', 'posted'),
('TXN-3003', 'ACC-2001', 'CUST-1001', 450.00, 'debit', 'Software subscription', 'Adobe', 'posted'),
('TXN-3004', 'ACC-2002', 'CUST-1001', 5000.00, 'credit', 'Interest payment', 'Bank', 'posted'),
('TXN-3005', 'ACC-2003', 'CUST-1002', 2300.00, 'debit', 'Equipment purchase', 'Dell', 'posted'),
('TXN-3006', 'ACC-2003', 'CUST-1002', 15.50, 'debit', 'Coffee', 'Starbucks', 'posted'),
('TXN-3007', 'ACC-2004', 'CUST-1003', 1200.00, 'debit', 'Consulting fee', 'Acme Corp', 'posted'),
('TXN-3008', 'ACC-2005', 'CUST-1002', 320.00, 'debit', 'Online purchase', 'Amazon', 'posted'),
('TXN-3009', 'ACC-2001', 'CUST-1001', 25.00, 'debit', 'Monthly fee', 'Bank', 'posted'),
('TXN-3010', 'ACC-2003', 'CUST-1002', 5000.00, 'credit', 'Deposit', 'Wire Transfer', 'posted')
ON CONFLICT (transaction_id) DO NOTHING;

INSERT INTO cards (card_id, account_id, customer_id, card_type, last4, status, expiry_month, expiry_year) VALUES
('CRD-4001', 'ACC-2001', 'CUST-1001', 'debit', '4521', 'active', 12, 2027),
('CRD-4002', 'ACC-2005', 'CUST-1002', 'credit', '8830', 'active', 8, 2026),
('CRD-4003', 'ACC-2003', 'CUST-1002', 'debit', '1093', 'active', 3, 2028)
ON CONFLICT (card_id) DO NOTHING;

INSERT INTO disputes (dispute_id, transaction_id, customer_id, reason, status) VALUES
('DSP-5001', 'TXN-3005', 'CUST-1002', 'Equipment never delivered', 'open'),
('DSP-5002', 'TXN-3008', 'CUST-1002', 'Unauthorized charge', 'investigating')
ON CONFLICT (dispute_id) DO NOTHING;

INSERT INTO loans (loan_id, customer_id, loan_type, principal, interest_rate, remaining_balance, monthly_payment, status, term_months) VALUES
('LOAN-6001', 'CUST-1001', 'business', 50000.00, 6.50, 38500.00, 1850.00, 'active', 36),
('LOAN-6002', 'CUST-1003', 'personal', 15000.00, 8.20, 9200.00, 480.00, 'active', 36)
ON CONFLICT (loan_id) DO NOTHING;

-- ============================================================
-- HOSPITAL DATA
-- ============================================================
INSERT INTO patients (patient_id, user_id, customer_id, full_name, date_of_birth, phone, email, insurance_provider, insurance_id) VALUES
('PAT-7001', null, 'CUST-1001', 'Alice Chen', '1985-03-15', '+1-555-0101', 'alice@acme.example', 'BlueCross', 'BC-5551234'),
('PAT-7002', null, 'CUST-1002', 'Bob Smith', '1972-08-22', '+1-555-0202', 'bob@globex.example', 'Aetna', 'AE-9988776'),
('PAT-7003', null, 'CUST-1003', 'Carol Johnson', '1990-11-30', '+1-555-0303', 'carol@initech.example', 'Cigna', 'CG-4455667')
ON CONFLICT (patient_id) DO NOTHING;

INSERT INTO appointments (appointment_id, patient_id, department, doctor_name, scheduled_at, status, reason) VALUES
('APT-8001', 'PAT-7001', 'Cardiology', 'Dr. Martinez', '2026-09-05 10:00:00-07', 'scheduled', 'Annual checkup'),
('APT-8002', 'PAT-7002', 'General Medicine', 'Dr. Lee', '2026-08-20 14:00:00-07', 'completed', 'Follow-up consultation'),
('APT-8003', 'PAT-7003', 'Orthopedics', 'Dr. Patel', '2026-09-10 09:30:00-07', 'scheduled', 'Knee pain assessment'),
('APT-8004', 'PAT-7001', 'Dermatology', 'Dr. Nguyen', '2026-08-15 11:00:00-07', 'cancelled', 'Skin consultation')
ON CONFLICT (appointment_id) DO NOTHING;

INSERT INTO prescriptions (prescription_id, patient_id, medication, dosage, refills_remaining, status, prescribed_by) VALUES
('RX-9001', 'PAT-7001', 'Lisinopril', '10mg daily', 3, 'active', 'Dr. Martinez'),
('RX-9002', 'PAT-7002', 'Metformin', '500mg twice daily', 2, 'active', 'Dr. Lee'),
('RX-9003', 'PAT-7003', 'Ibuprofen', '400mg as needed', 1, 'active', 'Dr. Patel')
ON CONFLICT (prescription_id) DO NOTHING;

INSERT INTO lab_results (result_id, patient_id, test_name, result_value, result_unit, status, notes, ordered_at, result_at) VALUES
('LAB-10001', 'PAT-7001', 'Complete Blood Count', 'Normal', '', 'completed', 'All values within normal range', '2026-08-10', '2026-08-12'),
('LAB-10002', 'PAT-7002', 'HbA1c', '7.2', '%', 'completed', 'Slightly elevated, discuss with Dr. Lee', '2026-08-08', '2026-08-10'),
('LAB-10003', 'PAT-7003', 'X-Ray Knee', 'Pending', '', 'pending', 'Results expected in 2-3 days', '2026-08-27', null)
ON CONFLICT (result_id) DO NOTHING;

INSERT INTO medical_records (record_id, patient_id, diagnosis, notes, access_level, created_by, created_at) VALUES
('MED-11001', 'PAT-7001', 'Hypertension', 'Stage 1 hypertension, managed with Lisinopril 10mg. BP monitored monthly.', 'internal', null, '2026-08-01'),
('MED-11002', 'PAT-7002', 'Type 2 Diabetes', 'HbA1c slightly elevated at 7.2%. Continue Metformin and lifestyle modifications.', 'internal', null, '2026-08-10')
ON CONFLICT (record_id) DO NOTHING;

-- ============================================================
-- HR DATA
-- ============================================================
INSERT INTO hr_employees (employee_id, user_id, department, hire_date, leave_balance, manager_name) VALUES
('EMP-12001', (SELECT id FROM auth.users WHERE email = 'admin@demo.co'), 'Operations', '2023-01-15', 18.5, 'CEO'),
('EMP-12002', (SELECT id FROM auth.users WHERE email = 'support@demo.co'), 'Customer Support', '2023-06-01', 15.0, 'VP Operations'),
('EMP-12003', (SELECT id FROM auth.users WHERE email = 'employee@demo.co'), 'Engineering', '2024-03-20', 20.0, 'CTO')
ON CONFLICT (employee_id) DO NOTHING;

INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, status, reason) VALUES
('EMP-12001', 'annual', '2026-09-15', '2026-09-20', 5.0, 'approved', 'Family vacation'),
('EMP-12002', 'sick', '2026-08-25', '2026-08-26', 2.0, 'pending', 'Medical appointment'),
('EMP-12003', 'annual', '2026-10-10', '2026-10-14', 4.0, 'pending', 'Personal travel')
ON CONFLICT (request_id) DO NOTHING;

INSERT INTO pay_stubs (stub_id, employee_id, pay_period_start, pay_period_end, gross_amount, net_amount, deductions, pay_date) VALUES
('PAY-13001', 'EMP-12001', '2026-08-01', '2026-08-15', 6500.00, 4850.00, 1650.00, '2026-08-15'),
('PAY-13002', 'EMP-12002', '2026-08-01', '2026-08-15', 4200.00, 3150.00, 1050.00, '2026-08-15'),
('PAY-13003', 'EMP-12003', '2026-08-01', '2026-08-15', 3800.00, 2850.00, 950.00, '2026-08-15')
ON CONFLICT (stub_id) DO NOTHING;

-- ============================================================
-- IT DATA
-- ============================================================
INSERT INTO it_tickets (ticket_id, requested_by, category, priority, status, subject, description, assigned_to) VALUES
('ITK-14001', (SELECT id FROM auth.users WHERE email = 'employee@demo.co'), 'hardware', 'medium', 'open', 'Laptop screen flickering', 'Screen flickers when connected to external monitor via HDMI.', 'IT Team'),
('ITK-14002', (SELECT id FROM auth.users WHERE email = 'support@demo.co'), 'software', 'high', 'in_progress', 'VPN connection drops', 'VPN disconnects every 15 minutes since the latest update.', 'John Doe'),
('ITK-14003', (SELECT id FROM auth.users WHERE email = 'admin@demo.co'), 'access', 'low', 'resolved', 'Need access to finance dashboard', 'Requesting read access to the finance reporting dashboard.', 'IT Team')
ON CONFLICT (ticket_id) DO NOTHING;

-- ============================================================
-- PROCUREMENT DATA
-- ============================================================
INSERT INTO purchase_orders (po_id, requested_by, vendor, item_description, quantity, unit_price, total_amount, status) VALUES
('PO-15001', (SELECT id FROM auth.users WHERE email = 'admin@demo.co'), 'Dell Technologies', 'Latitude 7440 Laptops', 10, 1450.00, 14500.00, 'approved'),
('PO-15002', (SELECT id FROM auth.users WHERE email = 'support@demo.co'), 'Staples', 'Office chairs (ergonomic)', 5, 320.00, 1600.00, 'draft'),
('PO-15003', (SELECT id FROM auth.users WHERE email = 'admin@demo.co'), 'Adobe', 'Creative Cloud annual license', 3, 599.00, 1797.00, 'delivered')
ON CONFLICT (po_id) DO NOTHING;