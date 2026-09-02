# Enterprise AI Support & Operations Copilot

An enterprise-grade AI assistant that combines NLP, RAG (Retrieval-Augmented Generation), agentic tool calling, conversational memory, role-based access control (RBAC), structured outputs, observability, and an evaluation framework.

## Architecture

```
User → React Chat UI → Edge Function API → Auth + RBAC
  → Intent Classification (hybrid: regex + LLM)
  → Agent Router
    ├── Knowledge Agent → RAG → PGVector
    ├── Order Agent → Order Tool → PostgreSQL
    ├── Invoice Agent → Invoice Tool → PostgreSQL
    ├── Customer Agent → Customer Tool → PostgreSQL
    ├── Support Agent → Ticket Tool → PostgreSQL
    └── General Agent → LLM
  → Structured Response → Conversation Memory → Response → React UI
```

## Tech Stack

- **Frontend:** React + Vite + TypeScript + Tailwind CSS + Lucide icons
- **Backend:** Supabase Edge Functions (Deno/TypeScript)
- **Database:** PostgreSQL with PGVector (via Supabase)
- **Auth:** Supabase Auth (JWT) with custom RBAC layer
- **LLM:** Provider abstraction (OpenAI / Groq) with local fallback
- **Embeddings:** OpenAI text-embedding-3-small (1536 dimensions)

## Features

### AI/ML Components

1. **Hybrid Intent Classification**
   - Deterministic regex for structured identifiers (ORD-, INV-, CUST-, TKT-)
   - LLM-based classification for natural language
   - Confidence scoring with clarification fallback

2. **RAG Pipeline**
   - Document ingestion with chunking
   - PGVector semantic similarity search (cosine distance, HNSW index)
   - Keyword fallback search when embeddings unavailable
   - Metadata filtering by access level
   - Grounded generation with source citations

3. **Agentic Router**
   - Structured routing decisions with confidence scores
   - Routes to 6 capabilities: knowledge, order, invoice, customer, support, general
   - Does not blindly call tools — validates intent first

4. **Tool/Function Calling**
   - 6 tools with strict input validation, parameterized queries, authorization
   - `get_order_status(order_id)` — order lookup with items
   - `get_invoice_status(invoice_id)` — invoice status lookup
   - `get_customer(customer_id)` — customer information
   - `get_customer_orders(customer_id)` — customer order history
   - `create_support_ticket(customer_id, issue, priority)` — ticket creation
   - `search_knowledge_base(query)` — RAG retrieval
   - All tools use parameterized queries (no arbitrary SQL)

5. **Conversational Memory**
   - Session-scoped history stored in PostgreSQL
   - Context-windowed (last 6-10 messages sent to LLM)
   - Follow-up reference resolution (e.g., "the previous order")

6. **Structured Outputs**
   - All AI responses include intent, confidence, tool, sources, latency
   - Validated with fallback handling

### Security

- **JWT Authentication** via Supabase Auth
- **RBAC** with 4 roles: Admin, Support Agent, Finance User, Employee
- **Row-Level Security (RLS)** on every table
- **Database-level authorization** via SECURITY DEFINER helper functions
- **Defense in depth:** LLM never makes authorization decisions
- **Audit logging** for sensitive actions
- **Tool execution logging** with latency tracking
- **Prompt injection defense:** authorization enforced at DB level, not by LLM
- **SQL injection prevention:** parameterized queries only

### Observability

- Structured audit logs (user, action, resource, status)
- Tool execution logs (tool, args, status, latency, error)
- Request latency tracking
- LLM provider/model tracking

### Evaluation Framework

- Intent classification accuracy
- Tool selection accuracy
- Per-question results with expected vs. predicted
- Run via "Run Evaluation" button in UI or `GET /api/v1/evaluate`

## Database Schema

| Table | Purpose |
|-------|---------|
| `app_users` | User profiles with roles, linked to auth.users |
| `customers` | Enterprise customer records (CUST-XXXX) |
| `orders` | Customer orders (ORD-XXXX) with status |
| `order_items` | Line items per order |
| `invoices` | Invoices (INV-XXXX) with payment status |
| `support_tickets` | Tickets (TKT-XXXX) with priority |
| `knowledge_documents` | Source documents with access levels |
| `knowledge_chunks` | Chunked text with vector embeddings |
| `conversation_sessions` | Chat sessions per user |
| `conversation_messages` | Messages with intent/tool/sources metadata |
| `audit_logs` | Security audit trail |
| `tool_execution_logs` | Per-tool-call execution records |
| `evaluation_runs` | Evaluation results |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/auth/login` | Login (auto-creates user) |
| POST | `/api/v1/chat` | Non-streaming chat |
| POST | `/api/v1/chat/stream` | Streaming chat (SSE) |
| POST | `/api/v1/knowledge/ingest` | Ingest document (admin) |
| GET | `/api/v1/orders/{order_id}` | Order lookup |
| GET | `/api/v1/invoices/{invoice_id}` | Invoice lookup |
| GET | `/api/v1/customers/{customer_id}` | Customer lookup |
| POST | `/api/v1/support/tickets` | Create ticket |
| GET | `/api/v1/conversations` | List conversations |
| GET | `/api/v1/conversations/{session_id}` | Get conversation |
| DELETE | `/api/v1/conversations/{session_id}` | Delete conversation |
| GET | `/api/v1/evaluate` | Run evaluation |
| GET | `/api/v1/health` | Health check |
| GET | `/api/v1/demo-users` | Create demo users |

## Demo Scenarios

1. **"What is the employee leave policy?"** → RAG
2. **"What is the status of order ORD-1001?"** → Order Tool
3. **"Is invoice INV-1001 paid?"** → Invoice Tool
4. **"Create a support ticket because my invoice is overdue."** → Support Tool
5. **"Tell me about our refund policy."** → RAG
6. **"Hello"** → General LLM
7. **Follow-up: "What about the previous order?"** → Conversation Memory
8. **Unauthorized access** (Employee role tries finance docs) → Blocked by RBAC

## Demo Accounts

| Role | Email | Password |
|------|-------|----------|
| Admin | admin@demo.co | Demo!Copilot2026 |
| Support Agent | support@demo.co | Demo!Copilot2026 |
| Finance User | finance@demo.co | Demo!Copilot2026 |
| Employee | employee@demo.co | Demo!Copilot2026 |

## Local Setup

```bash
npm install
npm run dev
```

The app auto-creates demo users on the login page. Click any role to instantly sign in.

## Environment Variables

The following are pre-configured by the platform:
- `VITE_SUPABASE_URL` — Supabase project URL
- `VITE_SUPABASE_ANON_KEY` — Supabase anon key
- `SUPABASE_URL` — Server-side Supabase URL
- `SUPABASE_SERVICE_ROLE_KEY` — Service role key (edge functions)

Optional LLM configuration (edge function secrets):
- `LLM_PROVIDER` — `openai` or `groq` (default: `openai`)
- `OPENAI_API_KEY` — OpenAI API key for LLM + embeddings
- `GROQ_API_KEY` — Groq API key (alternative LLM provider)
- `LLM_MODEL` — Model name (default: `gpt-4o-mini`)
- `EMBEDDING_MODEL` — Embedding model (default: `text-embedding-3-small`)

Without LLM keys, the system uses a local fallback that produces reasonable responses for all demo scenarios. Semantic search falls back to keyword matching when embeddings are unavailable.

## Known Limitations

- Without an OpenAI API key, RAG uses keyword search instead of semantic embeddings
- Without any LLM key, responses use a local heuristic responder (still functional for demos)
- The edge function is a single deployable unit (Supabase constraint) but is organized into clearly separated modules
- No Docker setup (the platform provides managed infrastructure instead)
- Evaluation covers intent classification and tool selection; full RAG faithfulness scoring requires an LLM judge

## Future Improvements

- Add LLM-as-judge for RAG faithfulness and citation correctness evaluation
- Implement streaming token-by-token from the actual LLM (currently chunks the final answer)
- Add rate limiting per user/role
- Implement document upload with automatic chunking and embedding
- Add WebSocket support for real-time multi-agent collaboration
- Implement conversation summarization for long sessions
