export type Role = "admin" | "support_agent" | "finance_user" | "employee" | "bank_teller" | "doctor" | "hr_admin" | "it_admin";
export type Intent = "knowledge" | "order" | "invoice" | "customer" | "support" | "general" | "banking" | "hospital" | "hr" | "it" | "procurement" | "escalation";

export interface AppUser {
  id: string;
  email: string;
  full_name: string | null;
  role: Role;
  customer_id: string | null;
}

export interface SourceRef {
  document_id: string;
  title: string;
  source: string;
  chunk_content: string;
  similarity?: number;
}

export interface ChatMessageData {
  message_id?: string;
  role: "user" | "assistant" | "system";
  content: string;
  intent?: string;
  confidence?: number;
  tool_name?: string | null;
  sources?: SourceRef[];
  latency_ms?: number;
  created_at?: string;
}

export interface ConversationSession {
  session_id: string;
  title: string;
  created_at: string;
  updated_at?: string;
}

export interface ChatResponse {
  intent: Intent;
  confidence: number;
  tool: string | null;
  answer: string;
  sources: SourceRef[];
  requires_clarification: boolean;
  latency_ms: number;
  session_id?: string;
}

export interface SSEEvent {
  type: "status" | "intent" | "token" | "done" | "error";
  status?: string;
  intent?: Intent;
  confidence?: number;
  content?: string;
  answer?: string;
  sources?: SourceRef[];
  tool?: string | null;
  latency_ms?: number;
  session_id?: string;
  error?: string;
  security?: {
    injection_detected?: boolean;
    injection_category?: string;
    pii_detected?: boolean;
    pii_types?: string[];
  };
}

export interface Escalation {
  escalation_id: string;
  session_id: string;
  user_id: string;
  reason: string;
  priority: string;
  status: string;
  assigned_to: string | null;
  conversation_summary: string | null;
  created_at: string;
  resolved_at: string | null;
}

export interface AnalyticsData {
  total_events: number;
  total_conversations: number;
  intent_distribution: Record<string, number>;
  tool_usage: Record<string, number>;
  sentiment_distribution: Record<string, number>;
  language_distribution: Record<string, number>;
  avg_latency_ms: number;
  feedback: {
    total: number;
    positive: number;
    negative: number;
    satisfaction_rate: number;
  };
  escalations: {
    total: number;
    open: number;
    resolved: number;
  };
}

export interface DocumentUpload {
  upload_id: string;
  uploaded_by: string;
  document_id: string;
  title: string;
  document_type: string;
  department: string;
  access_level: string;
  source: string;
  chunk_count: number;
  status: string;
  created_at: string;
}

export interface WebhookEndpoint {
  id: string;
  name: string;
  url: string;
  event_types: string[];
  active: boolean;
  created_at: string;
}

export interface RAGEvalMetrics {
  avg_faithfulness: number;
  avg_answer_relevancy: number;
  avg_context_precision: number;
  avg_context_recall: number;
  avg_citation_accuracy: number;
  hallucination_rate: number;
  total_questions: number;
  latency_ms: number;
}

export interface RAGEvalResult {
  question: string;
  answer: string;
  sources: SourceRef[];
  faithfulness: number;
  answer_relevancy: number;
  context_precision: number;
  context_recall: number;
  citation_accuracy: number;
  hallucination_detected: boolean;
  hallucination_score: number;
}

export interface InjectionTestResult {
  total: number;
  passed: number;
  failed: number;
  pass_rate: number;
  results: Array<{
    description: string;
    input: string;
    expected_blocked: boolean;
    detected: boolean;
    confidence: number;
    matched_patterns: string[];
    category: string;
    passed: boolean;
  }>;
}

export interface PIICheckResult {
  has_pii: boolean;
  detections: Array<{ type: string; replacement: string }>;
  redacted_text: string;
}

export interface ObservabilityData {
  total_calls: number;
  successful_calls: number;
  failed_calls: number;
  success_rate: number;
  total_tokens: number;
  prompt_tokens: number;
  completion_tokens: number;
  estimated_cost_usd: string;
  avg_latency_ms: number;
  purpose_distribution: Record<string, number>;
  model_distribution: Record<string, number>;
  recent_observations: Array<Record<string, unknown>>;
}

export const ROLE_LABELS: Record<Role, string> = {
  admin: "Administrator",
  support_agent: "Support Agent",
  finance_user: "Finance User",
  employee: "Employee",
  bank_teller: "Bank Teller",
  doctor: "Doctor",
  hr_admin: "HR Admin",
  it_admin: "IT Admin",
};

export const INTENT_LABELS: Record<Intent, string> = {
  knowledge: "RAG",
  order: "Order Tool",
  invoice: "Invoice Tool",
  customer: "Customer Tool",
  support: "Support Tool",
  general: "General LLM",
  banking: "Banking Tool",
  hospital: "Hospital Tool",
  hr: "HR Tool",
  it: "IT Tool",
  procurement: "Procurement Tool",
  escalation: "Escalation",
};

export const INTENT_COLORS: Record<Intent, string> = {
  knowledge: "text-emerald-600 bg-emerald-50 border-emerald-200",
  order: "text-blue-600 bg-blue-50 border-blue-200",
  invoice: "text-amber-600 bg-amber-50 border-amber-200",
  customer: "text-cyan-600 bg-cyan-50 border-cyan-200",
  support: "text-rose-600 bg-rose-50 border-rose-200",
  general: "text-slate-600 bg-slate-50 border-slate-200",
  banking: "text-indigo-600 bg-indigo-50 border-indigo-200",
  hospital: "text-pink-600 bg-pink-50 border-pink-200",
  hr: "text-orange-600 bg-orange-50 border-orange-200",
  it: "text-purple-600 bg-purple-50 border-purple-200",
  procurement: "text-teal-600 bg-teal-50 border-teal-200",
  escalation: "text-red-600 bg-red-50 border-red-200",
};
