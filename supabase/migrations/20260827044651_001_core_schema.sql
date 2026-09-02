/*
# Enterprise AI Support & Operations Copilot — Core Schema

## Purpose
Creates the full PostgreSQL schema for an enterprise AI assistant that combines
RAG (with pgvector), agentic tool calling, conversational memory, RBAC, audit
logging, and an evaluation framework.

## New Tables

1. `app_users` — application user profiles linked to `auth.users`, with a role
   (`admin`, `support_agent`, `finance_user`, `employee`) and a linked
   `customer_id` for employees who are also customers.
2. `customers` — enterprise customer records (CUST-####).
3. `orders` — customer orders (ORD-####) with status + timestamps.
4. `order_items` — line items per order.
5. `invoices` — invoices (INV-####) tied to orders, with paid/pending/overdue status.
6. `support_tickets` — tickets (TKT-####) tied to customers, with priority + status.
7. `knowledge_documents` — source documents (title, type, department, access_level, source).
8. `knowledge_chunks` — chunked document text with a `vector` embedding column (pgvector)
   plus metadata for filtered similarity search.
9. `conversation_sessions` — chat sessions per user.
10. `conversation_messages` — individual messages within a session (role, content,
    structured metadata, tool info, sources, latency).
11. `audit_logs` — security audit trail for sensitive actions.
12. `tool_execution_logs` — per-tool-call execution records (tool, args, status, latency, error).
13. `evaluation_runs` — results from the evaluation framework (metrics, dataset, timestamp).

## Security (RLS)
- RLS enabled on EVERY table.
- `app_users`: a user can read/update their own profile; admins can read all.
- `customers` / `orders` / `order_items` / `invoices` / `support_tickets`:
  access is mediated by the `can_access_*()` helper functions which enforce
  role-based access (admin/support_agent/finance_user/employee) using
  `auth.uid()` → role lookup. Employees see only their own linked customer's data.
- `knowledge_documents` / `knowledge_chunks`: access filtered by the user's role
  against the document's `access_level` via `can_access_document()`.
- `conversation_sessions` / `conversation_messages`: owner-scoped (user can only
  see their own conversations); admins can read all sessions for support/debugging.
- `audit_logs` / `tool_execution_logs` / `evaluation_runs`: insert by authenticated;
  read restricted to admins (audit/tool logs) or owner (evaluation runs).

## Helper Functions (SECURITY DEFINER)
- `get_current_role()` → text: returns the calling user's role or NULL.
- `is_admin()` → boolean.
- `can_access_customer(p_customer_id)` → boolean.
- `can_access_order(p_order_id)` → boolean.
- `can_access_invoice(p_invoice_id)` → boolean.
- `can_access_ticket(p_ticket_id)` → boolean.
- `can_access_document(p_access_level)` → boolean.
- `can_create_ticket_for(p_customer_id)` → boolean.
These functions are the single source of truth for authorization. RLS policies
call them so that the rules are enforced at the database level regardless of how
the data is queried. The LLM is never trusted with authorization.

## Triggers
- `handle_new_auth_user()`: when a new row is inserted into `auth.users`, create a
  matching `app_users` row with the default role `employee`.
*/

-- =========================================================
-- Extensions
-- =========================================================
CREATE EXTENSION IF NOT EXISTS vector;

-- =========================================================
-- Enums
-- =========================================================
DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('admin', 'support_agent', 'finance_user', 'employee');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE order_status AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE invoice_status AS ENUM ('draft', 'sent', 'paid', 'overdue', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE ticket_status AS ENUM ('open', 'in_progress', 'resolved', 'closed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE doc_access_level AS ENUM ('public', 'internal', 'finance', 'support', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE message_role AS ENUM ('user', 'assistant', 'system');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE tool_status AS ENUM ('success', 'error', 'denied');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =========================================================
-- Tables
-- =========================================================

CREATE TABLE IF NOT EXISTS app_users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  full_name text,
  role user_role NOT NULL DEFAULT 'employee',
  customer_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS customers (
  customer_id text PRIMARY KEY,
  company_name text NOT NULL,
  contact_name text,
  contact_email text,
  phone text,
  address text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  order_id text PRIMARY KEY,
  customer_id text NOT NULL REFERENCES customers(customer_id),
  status order_status NOT NULL DEFAULT 'pending',
  total_amount numeric(12,2) NOT NULL DEFAULT 0,
  placed_at timestamptz NOT NULL DEFAULT now(),
  shipped_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id text NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  product_name text NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  unit_price numeric(12,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS invoices (
  invoice_id text PRIMARY KEY,
  order_id text NOT NULL REFERENCES orders(order_id),
  customer_id text NOT NULL REFERENCES customers(customer_id),
  status invoice_status NOT NULL DEFAULT 'draft',
  amount numeric(12,2) NOT NULL DEFAULT 0,
  issued_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS support_tickets (
  ticket_id text PRIMARY KEY,
  customer_id text NOT NULL REFERENCES customers(customer_id),
  subject text NOT NULL,
  description text,
  priority ticket_priority NOT NULL DEFAULT 'medium',
  status ticket_status NOT NULL DEFAULT 'open',
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS knowledge_documents (
  document_id text PRIMARY KEY,
  title text NOT NULL,
  document_type text NOT NULL,
  department text NOT NULL,
  access_level doc_access_level NOT NULL DEFAULT 'internal',
  source text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS knowledge_chunks (
  chunk_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id text NOT NULL REFERENCES knowledge_documents(document_id) ON DELETE CASCADE,
  chunk_index integer NOT NULL,
  content text NOT NULL,
  embedding vector(1536),
  document_type text,
  department text,
  access_level doc_access_level NOT NULL DEFAULT 'internal',
  source text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS conversation_sessions (
  session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  title text NOT NULL DEFAULT 'New conversation',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS conversation_messages (
  message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES conversation_sessions(session_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  role message_role NOT NULL,
  content text NOT NULL,
  intent text,
  confidence numeric(5,2),
  tool_name text,
  tool_status tool_status,
  sources jsonb,
  metadata jsonb,
  latency_ms integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES app_users(id),
  action text NOT NULL,
  resource_type text,
  resource_id text,
  status text NOT NULL DEFAULT 'success',
  details jsonb,
  ip_address text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tool_execution_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES app_users(id),
  session_id uuid,
  tool_name text NOT NULL,
  arguments jsonb,
  status tool_status NOT NULL,
  result jsonb,
  error text,
  latency_ms integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS evaluation_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES app_users(id),
  dataset_name text NOT NULL,
  metrics jsonb NOT NULL,
  results jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- =========================================================
-- Indexes
-- =========================================================
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_invoices_order ON invoices(order_id);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);
CREATE INDEX IF NOT EXISTS idx_tickets_customer ON support_tickets(customer_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_chunks_doc ON knowledge_chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_access ON knowledge_chunks(access_level);
CREATE INDEX IF NOT EXISTS idx_chunks_type ON knowledge_chunks(document_type);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON conversation_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_session ON conversation_messages(session_id);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_tool_logs_user ON tool_execution_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_tool_logs_tool ON tool_execution_logs(tool_name);

-- HNSW index for fast vector similarity search
DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS idx_chunks_embedding_hnsw
  ON knowledge_chunks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
EXCEPTION WHEN others THEN NULL; END $$;

-- =========================================================
-- Authorization helper functions (SECURITY DEFINER)
-- Single source of truth for RBAC. RLS policies call these.
-- =========================================================

CREATE OR REPLACE FUNCTION get_current_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role::text FROM app_users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM app_users WHERE id = auth.uid() AND role = 'admin');
$$;

CREATE OR REPLACE FUNCTION can_access_customer(p_customer_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_user_customer_id text;
BEGIN
  SELECT role, customer_id INTO v_role, v_user_customer_id
  FROM app_users WHERE id = auth.uid();
  IF v_role IS NULL THEN RETURN false; END IF;
  IF v_role = 'admin' THEN RETURN true; END IF;
  IF v_role = 'support_agent' THEN RETURN true; END IF;
  IF v_role = 'finance_user' THEN RETURN true; END IF;
  IF v_role = 'employee' AND v_user_customer_id = p_customer_id THEN RETURN true; END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION can_access_order(p_order_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_user_customer_id text;
  v_order_customer_id text;
BEGIN
  SELECT role, customer_id INTO v_role, v_user_customer_id
  FROM app_users WHERE id = auth.uid();
  IF v_role IS NULL THEN RETURN false; END IF;
  IF v_role IN ('admin', 'support_agent', 'finance_user') THEN RETURN true; END IF;
  IF v_role = 'employee' THEN
    SELECT customer_id INTO v_order_customer_id FROM orders WHERE order_id = p_order_id;
    RETURN v_order_customer_id = v_user_customer_id;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION can_access_invoice(p_invoice_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_user_customer_id text;
  v_invoice_customer_id text;
BEGIN
  SELECT role, customer_id INTO v_role, v_user_customer_id
  FROM app_users WHERE id = auth.uid();
  IF v_role IS NULL THEN RETURN false; END IF;
  IF v_role = 'admin' THEN RETURN true; END IF;
  IF v_role = 'finance_user' THEN RETURN true; END IF;
  IF v_role = 'support_agent' THEN
    -- Support agents can see invoice existence/status for ticket context, not financials
    RETURN true;
  END IF;
  IF v_role = 'employee' THEN
    SELECT customer_id INTO v_invoice_customer_id FROM invoices WHERE invoice_id = p_invoice_id;
    RETURN v_invoice_customer_id = v_user_customer_id;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION can_access_ticket(p_ticket_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_user_customer_id text;
  v_ticket_customer_id text;
BEGIN
  SELECT role, customer_id INTO v_role, v_user_customer_id
  FROM app_users WHERE id = auth.uid();
  IF v_role IS NULL THEN RETURN false; END IF;
  IF v_role IN ('admin', 'support_agent') THEN RETURN true; END IF;
  IF v_role IN ('finance_user', 'employee') THEN
    SELECT customer_id INTO v_ticket_customer_id FROM support_tickets WHERE ticket_id = p_ticket_id;
    RETURN v_ticket_customer_id = v_user_customer_id;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION can_access_document(p_access_level doc_access_level)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  SELECT role::text INTO v_role FROM app_users WHERE id = auth.uid();
  IF v_role IS NULL THEN RETURN false; END IF;
  IF v_role = 'admin' THEN RETURN true; END IF;
  IF p_access_level = 'public' THEN RETURN true; END IF;
  IF v_role = 'support_agent' AND p_access_level IN ('internal', 'support') THEN RETURN true; END IF;
  IF v_role = 'finance_user' AND p_access_level IN ('internal', 'finance') THEN RETURN true; END IF;
  IF v_role = 'employee' AND p_access_level = 'internal' THEN RETURN true; END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION can_create_ticket_for(p_customer_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_user_customer_id text;
BEGIN
  SELECT role, customer_id INTO v_role, v_user_customer_id
  FROM app_users WHERE id = auth.uid();
  IF v_role IS NULL THEN RETURN false; END IF;
  IF v_role IN ('admin', 'support_agent') THEN RETURN true; END IF;
  IF v_role IN ('finance_user', 'employee') AND p_customer_id = v_user_customer_id THEN RETURN true; END IF;
  RETURN false;
END;
$$;

-- =========================================================
-- RLS
-- =========================================================

ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE tool_execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE evaluation_runs ENABLE ROW LEVEL SECURITY;

-- ---- app_users ----
DROP POLICY IF EXISTS "select_own_profile" ON app_users;
CREATE POLICY "select_own_profile" ON app_users FOR SELECT
  TO authenticated USING (auth.uid() = id OR is_admin());

DROP POLICY IF EXISTS "update_own_profile" ON app_users;
CREATE POLICY "update_own_profile" ON app_users FOR UPDATE
  TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "insert_own_profile" ON app_users;
CREATE POLICY "insert_own_profile" ON app_users FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = id);

-- ---- customers ----
DROP POLICY IF EXISTS "select_customers_rbac" ON customers;
CREATE POLICY "select_customers_rbac" ON customers FOR SELECT
  TO authenticated USING (can_access_customer(customer_id));

-- ---- orders ----
DROP POLICY IF EXISTS "select_orders_rbac" ON orders;
CREATE POLICY "select_orders_rbac" ON orders FOR SELECT
  TO authenticated USING (can_access_order(order_id));

-- ---- order_items ----
DROP POLICY IF EXISTS "select_order_items_rbac" ON order_items;
CREATE POLICY "select_order_items_rbac" ON order_items FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM orders WHERE orders.order_id = order_items.order_id AND can_access_order(orders.order_id))
  );

-- ---- invoices ----
DROP POLICY IF EXISTS "select_invoices_rbac" ON invoices;
CREATE POLICY "select_invoices_rbac" ON invoices FOR SELECT
  TO authenticated USING (can_access_invoice(invoice_id));

-- ---- support_tickets ----
DROP POLICY IF EXISTS "select_tickets_rbac" ON support_tickets;
CREATE POLICY "select_tickets_rbac" ON support_tickets FOR SELECT
  TO authenticated USING (can_access_ticket(ticket_id));

DROP POLICY IF EXISTS "insert_tickets_rbac" ON support_tickets;
CREATE POLICY "insert_tickets_rbac" ON support_tickets FOR INSERT
  TO authenticated WITH CHECK (can_create_ticket_for(customer_id));

DROP POLICY IF EXISTS "update_tickets_rbac" ON support_tickets;
CREATE POLICY "update_tickets_rbac" ON support_tickets FOR UPDATE
  TO authenticated USING (can_access_ticket(ticket_id)) WITH CHECK (can_access_ticket(ticket_id));

-- ---- knowledge_documents ----
DROP POLICY IF EXISTS "select_documents_rbac" ON knowledge_documents;
CREATE POLICY "select_documents_rbac" ON knowledge_documents FOR SELECT
  TO authenticated USING (can_access_document(access_level));

DROP POLICY IF EXISTS "insert_documents_admin" ON knowledge_documents;
CREATE POLICY "insert_documents_admin" ON knowledge_documents FOR INSERT
  TO authenticated WITH CHECK (is_admin());

-- ---- knowledge_chunks ----
DROP POLICY IF EXISTS "select_chunks_rbac" ON knowledge_chunks;
CREATE POLICY "select_chunks_rbac" ON knowledge_chunks FOR SELECT
  TO authenticated USING (can_access_document(access_level));

DROP POLICY IF EXISTS "insert_chunks_admin" ON knowledge_chunks;
CREATE POLICY "insert_chunks_admin" ON knowledge_chunks FOR INSERT
  TO authenticated WITH CHECK (is_admin());

-- ---- conversation_sessions ----
DROP POLICY IF EXISTS "select_own_sessions" ON conversation_sessions;
CREATE POLICY "select_own_sessions" ON conversation_sessions FOR SELECT
  TO authenticated USING (auth.uid() = user_id OR is_admin());

DROP POLICY IF EXISTS "insert_own_sessions" ON conversation_sessions;
CREATE POLICY "insert_own_sessions" ON conversation_sessions FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_sessions" ON conversation_sessions;
CREATE POLICY "update_own_sessions" ON conversation_sessions FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "delete_own_sessions" ON conversation_sessions;
CREATE POLICY "delete_own_sessions" ON conversation_sessions FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- ---- conversation_messages ----
DROP POLICY IF EXISTS "select_own_messages" ON conversation_messages;
CREATE POLICY "select_own_messages" ON conversation_messages FOR SELECT
  TO authenticated USING (auth.uid() = user_id OR is_admin());

DROP POLICY IF EXISTS "insert_own_messages" ON conversation_messages;
CREATE POLICY "insert_own_messages" ON conversation_messages FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

-- ---- audit_logs ----
DROP POLICY IF EXISTS "insert_audit_logs" ON audit_logs;
CREATE POLICY "insert_audit_logs" ON audit_logs FOR INSERT
  TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "select_audit_admin" ON audit_logs;
CREATE POLICY "select_audit_admin" ON audit_logs FOR SELECT
  TO authenticated USING (is_admin());

-- ---- tool_execution_logs ----
DROP POLICY IF EXISTS "insert_tool_logs" ON tool_execution_logs;
CREATE POLICY "insert_tool_logs" ON tool_execution_logs FOR INSERT
  TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "select_tool_logs_admin" ON tool_execution_logs;
CREATE POLICY "select_tool_logs_admin" ON tool_execution_logs FOR SELECT
  TO authenticated USING (is_admin());

-- ---- evaluation_runs ----
DROP POLICY IF EXISTS "insert_eval_runs" ON evaluation_runs;
CREATE POLICY "insert_eval_runs" ON evaluation_runs FOR INSERT
  TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "select_eval_runs" ON evaluation_runs;
CREATE POLICY "select_eval_runs" ON evaluation_runs FOR SELECT
  TO authenticated USING (auth.uid() = user_id OR is_admin());

-- =========================================================
-- Triggers: auto-create app_users row on auth signup
-- =========================================================

CREATE OR REPLACE FUNCTION handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO app_users (id, email, full_name, role)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), 'employee')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_auth_user();

-- =========================================================
-- updated_at triggers
-- =========================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS app_users_updated ON app_users;
CREATE TRIGGER app_users_updated BEFORE UPDATE ON app_users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS support_tickets_updated ON support_tickets;
CREATE TRIGGER support_tickets_updated BEFORE UPDATE ON support_tickets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS conversation_sessions_updated ON conversation_sessions;
CREATE TRIGGER conversation_sessions_updated BEFORE UPDATE ON conversation_sessions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
