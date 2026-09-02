import { API_URL } from "./supabase";
import type { AppUser, ChatResponse, SSEEvent, ConversationSession, ChatMessageData, Escalation, AnalyticsData, DocumentUpload, WebhookEndpoint, RAGEvalMetrics, RAGEvalResult, InjectionTestResult, PIICheckResult, ObservabilityData } from "@/types";

function authHeaders(token: string): HeadersInit {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${token}`,
  };
}

export async function login(email: string, password: string, role?: string): Promise<{ access_token: string; user: AppUser }> {
  const resp = await fetch(`${API_URL}/v1/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, role }),
  });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ error: "Login failed" }));
    throw new Error(err.error || "Login failed");
  }
  return resp.json();
}

export async function setupDemoUsers(): Promise<void> {
  await fetch(`${API_URL}/v1/demo-users`, { method: "GET" });
}

export async function chat(message: string, token: string, sessionId?: string): Promise<ChatResponse> {
  const resp = await fetch(`${API_URL}/v1/chat`, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify({ message, session_id: sessionId }),
  });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ error: "Chat failed" }));
    throw new Error(err.error || "Chat failed");
  }
  return resp.json();
}

export async function* chatStream(
  message: string,
  token: string,
  sessionId?: string,
): AsyncGenerator<SSEEvent> {
  const resp = await fetch(`${API_URL}/v1/chat/stream`, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify({ message, session_id: sessionId }),
  });

  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ error: "Stream failed" }));
    throw new Error(err.error || "Stream failed");
  }

  const reader = resp.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";
    for (const line of lines) {
      if (line.startsWith("data: ")) {
        try {
          yield JSON.parse(line.slice(6)) as SSEEvent;
        } catch {
          // skip malformed
        }
      }
    }
  }
}

export async function listConversations(token: string): Promise<ConversationSession[]> {
  const resp = await fetch(`${API_URL}/v1/conversations`, { headers: authHeaders(token) });
  if (!resp.ok) return [];
  return resp.json();
}

export async function getConversation(token: string, sessionId: string): Promise<{ session_id: string; title: string; messages: ChatMessageData[] }> {
  const resp = await fetch(`${API_URL}/v1/conversations/${sessionId}`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("Failed to load conversation");
  return resp.json();
}

export async function deleteConversation(token: string, sessionId: string): Promise<void> {
  await fetch(`${API_URL}/v1/conversations/${sessionId}`, { method: "DELETE", headers: authHeaders(token) });
}

export async function exportConversation(token: string, sessionId: string): Promise<Record<string, unknown>> {
  const resp = await fetch(`${API_URL}/v1/conversations/${sessionId}/export`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("Failed to export conversation");
  return resp.json();
}

export async function runEvaluation(token: string): Promise<{ metrics: Record<string, number>; results: unknown[] }> {
  const resp = await fetch(`${API_URL}/v1/evaluate`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("Evaluation failed");
  return resp.json();
}

export async function checkHealth(): Promise<{ status: string; llm_provider: string; llm_configured: boolean; embedding_configured: boolean }> {
  const resp = await fetch(`${API_URL}/v1/health`);
  if (!resp.ok) throw new Error("Health check failed");
  return resp.json();
}

export async function submitFeedback(token: string, messageId: string | undefined, sessionId: string | undefined, rating: "positive" | "negative", comment?: string): Promise<void> {
  const resp = await fetch(`${API_URL}/v1/feedback`, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify({ message_id: messageId, session_id: sessionId, rating, comment }),
  });
  if (!resp.ok) throw new Error("Failed to submit feedback");
}

export async function createEscalation(token: string, sessionId: string | undefined, reason: string, priority?: string): Promise<Escalation> {
  const resp = await fetch(`${API_URL}/v1/escalate`, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify({ session_id: sessionId, reason, priority }),
  });
  if (!resp.ok) throw new Error("Failed to escalate");
  const data = await resp.json();
  return data.escalation as Escalation;
}

export async function listEscalations(token: string): Promise<Escalation[]> {
  const resp = await fetch(`${API_URL}/v1/escalations`, { headers: authHeaders(token) });
  if (!resp.ok) return [];
  return resp.json();
}

export async function getAnalytics(token: string): Promise<AnalyticsData> {
  const resp = await fetch(`${API_URL}/v1/analytics`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("Failed to fetch analytics");
  return resp.json();
}

export async function listDocuments(token: string): Promise<DocumentUpload[]> {
  const resp = await fetch(`${API_URL}/v1/documents`, { headers: authHeaders(token) });
  if (!resp.ok) return [];
  return resp.json();
}

export async function uploadDocument(token: string, data: { title: string; content: string; document_type?: string; department?: string; access_level?: string; source?: string }): Promise<{ success: boolean; document_id: string; chunks_inserted: number }> {
  const resp = await fetch(`${API_URL}/v1/documents/upload`, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify(data),
  });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ error: "Upload failed" }));
    throw new Error(err.error || "Upload failed");
  }
  return resp.json();
}

export async function listWebhooks(token: string): Promise<WebhookEndpoint[]> {
  const resp = await fetch(`${API_URL}/v1/webhooks`, { headers: authHeaders(token) });
  if (!resp.ok) return [];
  return resp.json();
}

export async function createWebhook(token: string, data: { name: string; url: string; event_types?: string[]; secret?: string }): Promise<void> {
  const resp = await fetch(`${API_URL}/v1/webhooks`, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify(data),
  });
  if (!resp.ok) throw new Error("Failed to create webhook");
}

export async function runRAGEvaluation(token: string): Promise<{ metrics: RAGEvalMetrics; results: RAGEvalResult[] }> {
  const resp = await fetch(`${API_URL}/v1/evaluate/rag`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("RAG evaluation failed");
  return resp.json();
}

export async function runInjectionTest(token: string): Promise<InjectionTestResult> {
  const resp = await fetch(`${API_URL}/v1/security/injection-test`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("Injection test failed");
  return resp.json();
}

export async function checkPII(token: string, text: string): Promise<PIICheckResult> {
  const resp = await fetch(`${API_URL}/v1/security/pii-check?text=${encodeURIComponent(text)}`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("PII check failed");
  return resp.json();
}

export async function getObservability(token: string): Promise<ObservabilityData> {
  const resp = await fetch(`${API_URL}/v1/observability`, { headers: authHeaders(token) });
  if (!resp.ok) throw new Error("Failed to fetch observability data");
  return resp.json();
}
