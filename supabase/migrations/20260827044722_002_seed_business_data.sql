/*
# Seed Demo Data — Business Records + Knowledge Documents

## Purpose
Populates the database with realistic demo records so all demo scenarios work
out of the box: customers, orders, order items, invoices, support tickets,
and knowledge documents (HR policies, refund policy, product docs, billing docs).

## Data Inserted
- 3 customers (CUST-1001, CUST-1002, CUST-1003)
- 4 orders (ORD-1001..ORD-1004) with varying statuses
- 6 order items
- 4 invoices (INV-1001..INV-1004) with varying statuses
- 3 support tickets (TKT-1001..TKT-1003)
- 5 knowledge documents (employee leave policy, refund policy, remote work policy,
  billing & payment terms, product overview)

## Notes
- Uses ON CONFLICT DO NOTHING so re-running is safe.
- Knowledge chunks/embeddings are inserted in a separate migration because
  they require generating embeddings via the edge function (the embedding model
  is called from the ingestion edge function, not SQL).
- For the initial seed, we insert chunk text WITHOUT embeddings; a one-time
  backfill edge function (`backfill-embeddings`) generates and stores the
  vectors. The chat function falls back to keyword search when embeddings are
  missing, so RAG still works before backfill.
*/

-- Customers
INSERT INTO customers (customer_id, company_name, contact_name, contact_email, phone, address) VALUES
  ('CUST-1001', 'Acme Corporation', 'Alice Chen', 'alice@acme.example', '+1-555-0101', '100 Market St, San Francisco, CA'),
  ('CUST-1002', 'Globex Industries', 'Bob Martinez', 'bob@globex.example', '+1-555-0102', '200 Industrial Blvd, Austin, TX'),
  ('CUST-1003', 'Initech Solutions', 'Carol Johnson', 'carol@initech.example', '+1-555-0103', '300 Tech Park, Seattle, WA')
ON CONFLICT (customer_id) DO NOTHING;

-- Orders
INSERT INTO orders (order_id, customer_id, status, total_amount, placed_at, shipped_at, delivered_at) VALUES
  ('ORD-1001', 'CUST-1001', 'shipped', 1250.00, '2025-08-15 09:00:00+00', '2025-08-17 14:00:00+00', NULL),
  ('ORD-1002', 'CUST-1002', 'delivered', 875.50, '2025-08-10 10:00:00+00', '2025-08-12 08:00:00+00', '2025-08-14 16:00:00+00'),
  ('ORD-1003', 'CUST-1003', 'processing', 3400.00, '2025-08-25 11:00:00+00', NULL, NULL),
  ('ORD-1004', 'CUST-1001', 'pending', 520.00, '2025-08-26 15:00:00+00', NULL, NULL)
ON CONFLICT (order_id) DO NOTHING;

-- Order items
INSERT INTO order_items (order_id, product_name, quantity, unit_price) VALUES
  ('ORD-1001', 'Wireless Headphones Pro', 2, 250.00),
  ('ORD-1001', 'USB-C Hub', 5, 150.00),
  ('ORD-1002', 'Mechanical Keyboard', 1, 175.50),
  ('ORD-1002', '4K Monitor', 2, 350.00),
  ('ORD-1003', 'Enterprise Server Rack', 1, 3000.00),
  ('ORD-1003', 'Cable Management Kit', 4, 100.00),
  ('ORD-1004', 'Webcam HD', 2, 130.00),
  ('ORD-1004', 'Desk Lamp', 2, 130.00)
ON CONFLICT DO NOTHING;

-- Invoices
INSERT INTO invoices (invoice_id, order_id, customer_id, status, amount, issued_at, due_at, paid_at) VALUES
  ('INV-1001', 'ORD-1001', 'CUST-1001', 'paid', 1250.00, '2025-08-15', '2025-09-15', '2025-08-20'),
  ('INV-1002', 'ORD-1002', 'CUST-1002', 'overdue', 875.50, '2025-08-10', '2025-09-10', NULL),
  ('INV-1003', 'ORD-1003', 'CUST-1003', 'sent', 3400.00, '2025-08-25', '2025-09-25', NULL),
  ('INV-1004', 'ORD-1004', 'CUST-1001', 'draft', 520.00, '2025-08-26', '2025-09-26', NULL)
ON CONFLICT (invoice_id) DO NOTHING;

-- Support tickets
INSERT INTO support_tickets (ticket_id, customer_id, subject, description, priority, status) VALUES
  ('TKT-1001', 'CUST-1002', 'Invoice INV-1002 overdue', 'Customer reports invoice INV-1002 is overdue and requests payment arrangement.', 'high', 'open'),
  ('TKT-1002', 'CUST-1001', 'Order ORD-1001 shipping delay', 'Customer asks about expected delivery date for shipped order.', 'medium', 'in_progress'),
  ('TKT-1003', 'CUST-1003', 'Product compatibility question', 'Customer wants to confirm server rack compatibility with their existing infrastructure.', 'low', 'open')
ON CONFLICT (ticket_id) DO NOTHING;

-- Knowledge documents
INSERT INTO knowledge_documents (document_id, title, document_type, department, access_level, source) VALUES
  ('DOC-HR-001', 'Employee Leave Policy', 'hr_policy', 'Human Resources', 'internal', 'employee_handbook.pdf'),
  ('DOC-POL-001', 'Refund and Return Policy', 'company_policy', 'Operations', 'public', 'refund_policy.pdf'),
  ('DOC-HR-002', 'Remote Work Policy', 'hr_policy', 'Human Resources', 'internal', 'remote_work_guide.md'),
  ('DOC-FIN-001', 'Billing and Payment Terms', 'billing_policy', 'Finance', 'finance', 'billing_terms.pdf'),
  ('DOC-PROD-001', 'Product Overview and Specifications', 'product_documentation', 'Product', 'public', 'product_catalog.pdf')
ON CONFLICT (document_id) DO NOTHING;

-- Knowledge chunks (text only; embeddings backfilled by edge function)
INSERT INTO knowledge_chunks (document_id, chunk_index, content, document_type, department, access_level, source) VALUES
  ('DOC-HR-001', 0, 'Employee Leave Policy: Full-time employees are entitled to 20 days of paid annual leave per calendar year. Leave accrues monthly at a rate of 1.67 days. Unused leave of up to 5 days may be carried over to the next calendar year. Leave requests must be submitted at least 5 business days in advance through the HR portal and approved by the direct manager.', 'hr_policy', 'Human Resources', 'internal', 'employee_handbook.pdf'),
  ('DOC-HR-001', 1, 'Sick Leave: Employees are entitled to 10 days of paid sick leave per calendar year. A medical certificate is required for absences of 3 or more consecutive days. Sick leave does not carry over and resets each calendar year. Extended medical leave beyond 10 days may qualify for short-term disability benefits.', 'hr_policy', 'Human Resources', 'internal', 'employee_handbook.pdf'),
  ('DOC-HR-001', 2, 'Parental Leave: Eligible employees are entitled to 12 weeks of paid parental leave following the birth or adoption of a child. This leave must be taken within the first 12 months after the event. Employees should notify HR at least 30 days in advance when possible. Parental leave runs concurrently with any applicable statutory leave.', 'hr_policy', 'Human Resources', 'internal', 'employee_handbook.pdf'),
  ('DOC-POL-001', 0, 'Refund and Return Policy: Customers may request a full refund within 30 days of purchase for physical products in original condition. Digital products are eligible for refund within 14 days if not downloaded or activated. Refunds are processed within 5-7 business days to the original payment method. Custom or personalized orders are non-refundable unless the product is defective.', 'company_policy', 'Operations', 'public', 'refund_policy.pdf'),
  ('DOC-POL-001', 1, 'Return Process: To initiate a return, customers should submit a return request through the customer portal or contact support with the order number. Returned items must include all original packaging and accessories. The company covers return shipping for defective products; the customer covers return shipping for change-of-mind returns. Exchange requests follow the same process as returns.', 'company_policy', 'Operations', 'public', 'refund_policy.pdf'),
  ('DOC-HR-002', 0, 'Remote Work Policy: Employees may work remotely up to 3 days per week with manager approval. Remote employees must maintain a dedicated workspace with reliable internet connectivity and be available during core hours of 10:00 AM to 3:00 PM in their local time zone. Equipment is provided by the company. Remote work arrangements are reviewed quarterly.', 'hr_policy', 'Human Resources', 'internal', 'remote_work_guide.md'),
  ('DOC-HR-002', 1, 'Remote Work Security: Remote employees must use the company VPN when accessing internal systems. Personal devices used for work must have current antivirus software and disk encryption enabled. Confidential information must not be stored on personal devices. Video calls should be conducted in a private space to prevent incidental disclosure of confidential information.', 'hr_policy', 'Human Resources', 'internal', 'remote_work_guide.md'),
  ('DOC-FIN-001', 0, 'Billing and Payment Terms: Invoices are issued upon order confirmation and are due within 30 days of the invoice date (Net 30). A 1.5% late payment fee is applied monthly for overdue invoices. Accepted payment methods include bank transfer, corporate credit card, and ACH. Payment plans can be arranged by contacting the finance department before the due date.', 'billing_policy', 'Finance', 'finance', 'billing_terms.pdf'),
  ('DOC-FIN-001', 1, 'Invoice Disputes: Customers may dispute an invoice within 10 days of receipt by submitting a dispute through the finance portal with supporting documentation. Disputed invoices are placed on hold and no late fees are applied during the dispute resolution period. Finance aims to resolve disputes within 5 business days. If the dispute is denied, the original payment terms apply from the resolution date.', 'billing_policy', 'Finance', 'finance', 'billing_terms.pdf'),
  ('DOC-PROD-001', 0, 'Product Overview: The company offers enterprise hardware and software solutions including server infrastructure, networking equipment, workstations, and productivity software. All products include a standard 1-year warranty extendable to 3 years with a support plan. Enterprise customers receive priority support with a 4-hour response time SLA for critical issues.', 'product_documentation', 'Product', 'public', 'product_catalog.pdf'),
  ('DOC-PROD-001', 1, 'Support Plans: Standard support is included with all purchases and provides email support with 24-hour response time. Premium support adds phone support and 4-hour response time for critical issues. Enterprise support includes a dedicated account manager, quarterly reviews, and on-site support when needed. Support plans can be upgraded at any time.', 'product_documentation', 'Product', 'public', 'product_catalog.pdf')
ON CONFLICT DO NOTHING;
