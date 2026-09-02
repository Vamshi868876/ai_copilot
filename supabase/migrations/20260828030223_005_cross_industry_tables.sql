/*
# Add Cross-Industry Tables: Feedback, Escalations, Webhooks, Rate Limiting, Document Uploads, Analytics

## Overview
Adds tables that make the system production-ready across all industries:
feedback collection, human handoff/escalation, webhook integrations, rate limiting,
document upload tracking, and analytics aggregation.

## New Tables
- message_feedback: thumbs up/down on assistant messages with optional comment
- escalations: human handoff requests with conversation context and status tracking
- webhook_endpoints: configured webhook targets (Slack, Teams, Salesforce, etc.)
- webhook_deliveries: delivery attempts with status and retry tracking
- rate_limit_buckets: per-user request counters for abuse prevention
- document_uploads: metadata for admin-uploaded documents (auto-chunked + embedded)
- analytics_events: structured event log for analytics dashboard

## Security
- RLS on all tables
- Feedback: users can read/create own; admin can read all
- Escalations: users can read own; staff can read/update all in their domain
- Webhooks: admin-only management
- Rate limits: service-role only (edge function manages)
- Document uploads: admin-only
- Analytics: admin-only read; any authenticated can insert
*/

-- ============================================================
-- MESSAGE FEEDBACK
-- ============================================================
CREATE TABLE IF NOT EXISTS message_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid REFERENCES conversation_messages(message_id) ON DELETE CASCADE,
  session_id uuid REFERENCES conversation_sessions(session_id) ON DELETE CASCADE,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  rating text NOT NULL CHECK (rating IN ('positive', 'negative')),
  comment text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feedback_message ON message_feedback(message_id);
CREATE INDEX IF NOT EXISTS idx_feedback_user ON message_feedback(user_id);

ALTER TABLE message_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_own_feedback" ON message_feedback;
CREATE POLICY "select_own_feedback" ON message_feedback FOR SELECT
  TO authenticated USING (user_id = auth.uid() OR is_admin());
DROP POLICY IF EXISTS "insert_own_feedback" ON message_feedback;
CREATE POLICY "insert_own_feedback" ON message_feedback FOR INSERT
  TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "update_own_feedback" ON message_feedback;
CREATE POLICY "update_own_feedback" ON message_feedback FOR UPDATE
  TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "delete_own_feedback" ON message_feedback;
CREATE POLICY "delete_own_feedback" ON message_feedback FOR DELETE
  TO authenticated USING (user_id = auth.uid());

-- ============================================================
-- ESCALATIONS (Human Handoff)
-- ============================================================
CREATE TABLE IF NOT EXISTS escalations (
  escalation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES conversation_sessions(session_id) ON DELETE CASCADE,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL,
  priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','assigned','resolved','closed')),
  assigned_to text,
  conversation_summary text,
  created_at timestamptz DEFAULT now(),
  resolved_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_escalations_session ON escalations(session_id);
CREATE INDEX IF NOT EXISTS idx_escalations_user ON escalations(user_id);
CREATE INDEX IF NOT EXISTS idx_escalations_status ON escalations(status);

ALTER TABLE escalations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_escalations" ON escalations;
CREATE POLICY "select_escalations" ON escalations FOR SELECT
  TO authenticated USING (user_id = auth.uid() OR is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "insert_escalations" ON escalations;
CREATE POLICY "insert_escalations" ON escalations FOR INSERT
  TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "update_escalations" ON escalations;
CREATE POLICY "update_escalations" ON escalations FOR UPDATE
  TO authenticated USING (is_staff_role(get_current_role())) WITH CHECK (is_staff_role(get_current_role()));
DROP POLICY IF EXISTS "delete_escalations" ON escalations;
CREATE POLICY "delete_escalations" ON escalations FOR DELETE
  TO authenticated USING (is_admin());

-- ============================================================
-- WEBHOOK ENDPOINTS
-- ============================================================
CREATE TABLE IF NOT EXISTS webhook_endpoints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  url text NOT NULL,
  event_types text[] NOT NULL DEFAULT '{}',
  secret text,
  active boolean NOT NULL DEFAULT true,
  created_by uuid DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS webhook_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_id uuid NOT NULL REFERENCES webhook_endpoints(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  response_code int,
  response_body text,
  attempts int NOT NULL DEFAULT 0,
  next_retry_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_endpoint ON webhook_deliveries(endpoint_id);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_status ON webhook_deliveries(status);

ALTER TABLE webhook_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_webhook_endpoints" ON webhook_endpoints;
CREATE POLICY "select_webhook_endpoints" ON webhook_endpoints FOR SELECT
  TO authenticated USING (is_admin());
DROP POLICY IF EXISTS "insert_webhook_endpoints" ON webhook_endpoints;
CREATE POLICY "insert_webhook_endpoints" ON webhook_endpoints FOR INSERT
  TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "update_webhook_endpoints" ON webhook_endpoints;
CREATE POLICY "update_webhook_endpoints" ON webhook_endpoints FOR UPDATE
  TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_webhook_endpoints" ON webhook_endpoints;
CREATE POLICY "delete_webhook_endpoints" ON webhook_endpoints FOR DELETE
  TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "select_webhook_deliveries" ON webhook_deliveries;
CREATE POLICY "select_webhook_deliveries" ON webhook_deliveries FOR SELECT
  TO authenticated USING (is_admin());
DROP POLICY IF EXISTS "insert_webhook_deliveries" ON webhook_deliveries;
CREATE POLICY "insert_webhook_deliveries" ON webhook_deliveries FOR INSERT
  TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "update_webhook_deliveries" ON webhook_deliveries;
CREATE POLICY "update_webhook_deliveries" ON webhook_deliveries FOR UPDATE
  TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_webhook_deliveries" ON webhook_deliveries;
CREATE POLICY "delete_webhook_deliveries" ON webhook_deliveries FOR DELETE
  TO authenticated USING (is_admin());

-- ============================================================
-- RATE LIMITING
-- ============================================================
CREATE TABLE IF NOT EXISTS rate_limit_buckets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  bucket_minute timestamptz NOT NULL,
  request_count int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_limit_unique ON rate_limit_buckets(user_id, bucket_minute);

ALTER TABLE rate_limit_buckets ENABLE ROW LEVEL SECURITY;

-- Service-role only; no policies needed for client access
-- Edge function manages this with service role key

-- ============================================================
-- DOCUMENT UPLOADS
-- ============================================================
CREATE TABLE IF NOT EXISTS document_uploads (
  upload_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uploaded_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  document_id text NOT NULL,
  title text NOT NULL,
  document_type text NOT NULL DEFAULT 'policy',
  department text NOT NULL DEFAULT 'general',
  access_level doc_access_level NOT NULL DEFAULT 'internal',
  source text NOT NULL,
  file_name text,
  file_size bigint,
  chunk_count int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'processing',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_document_uploads_uploaded_by ON document_uploads(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_document_uploads_status ON document_uploads(status);

ALTER TABLE document_uploads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_document_uploads" ON document_uploads;
CREATE POLICY "select_document_uploads" ON document_uploads FOR SELECT
  TO authenticated USING (uploaded_by = auth.uid() OR is_admin());
DROP POLICY IF EXISTS "insert_document_uploads" ON document_uploads;
CREATE POLICY "insert_document_uploads" ON document_uploads FOR INSERT
  TO authenticated WITH CHECK (is_admin());
DROP POLICY IF EXISTS "update_document_uploads" ON document_uploads;
CREATE POLICY "update_document_uploads" ON document_uploads FOR UPDATE
  TO authenticated USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS "delete_document_uploads" ON document_uploads;
CREATE POLICY "delete_document_uploads" ON document_uploads FOR DELETE
  TO authenticated USING (is_admin());

-- ============================================================
-- ANALYTICS EVENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS analytics_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  session_id uuid REFERENCES conversation_sessions(session_id) ON DELETE SET NULL,
  event_type text NOT NULL,
  intent text,
  tool_name text,
  latency_ms int,
  sentiment text,
  language text,
  metadata jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytics_events_type ON analytics_events(event_type);
CREATE INDEX IF NOT EXISTS idx_analytics_events_created ON analytics_events(created_at);
CREATE INDEX IF NOT EXISTS idx_analytics_events_intent ON analytics_events(intent);

ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "insert_analytics_events" ON analytics_events;
CREATE POLICY "insert_analytics_events" ON analytics_events FOR INSERT
  TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "select_analytics_events" ON analytics_events;
CREATE POLICY "select_analytics_events" ON analytics_events FOR SELECT
  TO authenticated USING (is_admin());