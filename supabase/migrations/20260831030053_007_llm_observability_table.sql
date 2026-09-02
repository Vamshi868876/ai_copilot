/*
# LLM Observability Table

1. New Tables
- `llm_observations` — tracks every LLM API call with token counts, latency, cost estimates, and success/failure status.
  - `id` (uuid, primary key)
  - `user_id` (uuid, references auth.users)
  - `session_id` (text, nullable, links to conversation session)
  - `request_id` (text, unique identifier per LLM call)
  - `model` (text, which LLM model was used)
  - `provider` (text, openai/groq/local)
  - `purpose` (text, classification/rag_answer/general/tool_extraction/evaluation)
  - `prompt_tokens` (integer, nullable)
  - `completion_tokens` (integer, nullable)
  - `total_tokens` (integer, nullable)
  - `latency_ms` (integer, how long the LLM call took)
  - `retrieval_latency_ms` (integer, nullable, time spent on RAG retrieval)
  - `tool_latency_ms` (integer, nullable, time spent on tool execution)
  - `estimated_cost_usd` (numeric, calculated from token counts and model pricing)
  - `success` (boolean, whether the call succeeded)
  - `error` (text, nullable, error message if failed)
  - `intent` (text, nullable, classified intent if relevant)
  - `tool_name` (text, nullable, tool executed if relevant)
  - `created_at` (timestamptz, default now())

2. Security
- Enable RLS on `llm_observations`.
- Staff roles (non-employee) can read all observations.
- All authenticated users can insert their own observations.
- No updates or deletes via API — observations are append-only.
*/

CREATE TABLE IF NOT EXISTS llm_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id text,
  request_id text NOT NULL,
  model text NOT NULL,
  provider text NOT NULL,
  purpose text NOT NULL,
  prompt_tokens integer,
  completion_tokens integer,
  total_tokens integer,
  latency_ms integer NOT NULL,
  retrieval_latency_ms integer,
  tool_latency_ms integer,
  estimated_cost_usd numeric(10, 6) DEFAULT 0,
  success boolean NOT NULL DEFAULT true,
  error text,
  intent text,
  tool_name text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE llm_observations ENABLE ROW LEVEL SECURITY;

-- Staff can read all observations
DROP POLICY IF EXISTS "staff_select_observations" ON llm_observations;
CREATE POLICY "staff_select_observations"
ON llm_observations FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM app_users
    WHERE app_users.id = auth.uid()
    AND app_users.role != 'employee'
  )
);

-- All authenticated users can insert their own observations
DROP POLICY IF EXISTS "insert_own_observations" ON llm_observations;
CREATE POLICY "insert_own_observations"
ON llm_observations FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- No updates or deletes — observations are append-only

CREATE INDEX IF NOT EXISTS idx_llm_obs_created_at ON llm_observations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_llm_obs_user_id ON llm_observations(user_id);
CREATE INDEX IF NOT EXISTS idx_llm_obs_purpose ON llm_observations(purpose);
