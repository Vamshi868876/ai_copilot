import { useState, useRef, useEffect, useCallback } from "react";
import { useAuth } from "@/hooks/useAuth";
import {
  chatStream, listConversations, getConversation, deleteConversation,
  runEvaluation, runRAGEvaluation, checkHealth, submitFeedback, createEscalation,
  listEscalations, getAnalytics, listDocuments, uploadDocument,
  listWebhooks, createWebhook, exportConversation,
  runInjectionTest, checkPII, getObservability,
} from "@/lib/api";
import {
  INTENT_LABELS, INTENT_COLORS, ROLE_LABELS,
  type ChatMessageData, type SSEEvent, type ConversationSession, type Intent,
  type Escalation, type AnalyticsData, type DocumentUpload, type WebhookEndpoint,
  type RAGEvalMetrics, type RAGEvalResult, type InjectionTestResult, type PIICheckResult, type ObservabilityData,
} from "@/types";
import {
  Send, Plus, Trash2, Brain, Loader2, FileText, Wrench, MessageSquare,
  ChevronDown, BarChart3, Activity, User, LogOut, RefreshCw, BookOpen,
  Package, Receipt, LifeBuoy, ThumbsUp, ThumbsDown, UserCog, Upload,
  Download, Webhook, TrendingUp, Clock, Smile, Frown, Meh, Globe, X,
  ShieldCheck, ShieldAlert, Eye, DollarSign, Zap, AlertTriangle, CheckCircle2, XCircle,
} from "lucide-react";

interface DisplayMessage extends ChatMessageData {
  status?: string;
  streaming?: boolean;
  toolBadge?: string | null;
  feedbackGiven?: "positive" | "negative" | null;
}

type PanelType = "none" | "eval" | "analytics" | "escalations" | "documents" | "webhooks" | "rag-eval" | "security" | "observability";

const SUGGESTED_PROMPTS = [
  { text: "What is the employee leave policy?", icon: BookOpen },
  { text: "What is the status of order ORD-1001?", icon: Package },
  { text: "Is invoice INV-1001 paid?", icon: Receipt },
  { text: "What is the balance of account ACC-2001?", icon: TrendingUp },
  { text: "Show appointments for patient PAT-7001", icon: UserCog },
  { text: "What is my leave balance?", icon: Clock },
  { text: "Create an IT ticket, my VPN keeps dropping", icon: LifeBuoy },
  { text: "Escalate this issue to a human agent", icon: UserCog },
];

export default function ChatPage() {
  const { user, token, signOut } = useAuth();
  const [sessions, setSessions] = useState<ConversationSession[]>([]);
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<DisplayMessage[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [showSidebar, setShowSidebar] = useState(true);
  const [activePanel, setActivePanel] = useState<PanelType>("none");
  const [evalResult, setEvalResult] = useState<{ metrics: Record<string, number>; results: unknown[] } | null>(null);
  const [evalLoading, setEvalLoading] = useState(false);
  const [ragEvalResult, setRagEvalResult] = useState<{ metrics: RAGEvalMetrics; results: RAGEvalResult[] } | null>(null);
  const [ragEvalLoading, setRagEvalLoading] = useState(false);
  const [injectionResult, setInjectionResult] = useState<InjectionTestResult | null>(null);
  const [injectionLoading, setInjectionLoading] = useState(false);
  const [piiInput, setPiiInput] = useState("");
  const [piiResult, setPiiResult] = useState<PIICheckResult | null>(null);
  const [piiLoading, setPiiLoading] = useState(false);
  const [observability, setObservability] = useState<ObservabilityData | null>(null);
  const [observabilityLoading, setObservabilityLoading] = useState(false);
  const [health, setHealth] = useState<{ status: string; llm_provider: string; llm_configured: boolean; embedding_configured: boolean } | null>(null);
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
  const [escalations, setEscalations] = useState<Escalation[]>([]);
  const [documents, setDocuments] = useState<DocumentUpload[]>([]);
  const [webhooks, setWebhooks] = useState<WebhookEndpoint[]>([]);
  const [escLoading, setEscLoading] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const isStaff = user?.role !== "employee";

  const loadSessions = useCallback(async () => {
    if (!token) return;
    const data = await listConversations(token);
    setSessions(data);
  }, [token]);

  const loadConversation = useCallback(async (sessionId: string) => {
    if (!token) return;
    try {
      const data = await getConversation(token, sessionId);
      setMessages(data.messages.map(m => ({ ...m, toolBadge: m.tool_name })));
      setActiveSessionId(sessionId);
    } catch {
      setMessages([]);
    }
  }, [token]);

  useEffect(() => {
    loadSessions();
    checkHealth().then(setHealth).catch(() => {});
  }, [loadSessions]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSend = async (text?: string) => {
    const messageText = text || input.trim();
    if (!messageText || sending || !token) return;

    setInput("");
    setSending(true);

    const userMsg: DisplayMessage = { role: "user", content: messageText };
    setMessages(prev => [...prev, userMsg]);

    const assistantMsg: DisplayMessage = { role: "assistant", content: "", streaming: true, status: "Processing..." };
    setMessages(prev => [...prev, assistantMsg]);

    try {
      let accumulatedContent = "";
      let finalIntent: Intent | undefined;
      let finalConfidence: number | undefined;
      let finalTool: string | null = null;
      let finalSources: DisplayMessage["sources"] = [];
      let finalLatency: number | undefined;
      let newSessionId = activeSessionId;

      for await (const event of chatStream(messageText, token, activeSessionId || undefined)) {
        switch (event.type) {
          case "status":
            setMessages(prev => {
              const updated = [...prev];
              updated[updated.length - 1].status = event.status;
              return updated;
            });
            break;
          case "intent":
            finalIntent = event.intent;
            finalConfidence = event.confidence;
            setMessages(prev => {
              const updated = [...prev];
              updated[updated.length - 1].intent = event.intent;
              updated[updated.length - 1].confidence = event.confidence;
              return updated;
            });
            break;
          case "token":
            accumulatedContent += event.content || "";
            setMessages(prev => {
              const updated = [...prev];
              updated[updated.length - 1].content = accumulatedContent;
              return updated;
            });
            break;
          case "done":
            accumulatedContent = event.answer || accumulatedContent;
            finalTool = event.tool || null;
            finalSources = event.sources || [];
            finalLatency = event.latency_ms;
            newSessionId = event.session_id || newSessionId;
            setMessages(prev => {
              const updated = [...prev];
              updated[updated.length - 1] = {
                ...updated[updated.length - 1],
                content: accumulatedContent,
                streaming: false,
                status: undefined,
                tool_name: finalTool,
                toolBadge: finalTool,
                sources: finalSources,
                latency_ms: finalLatency,
                intent: finalIntent,
                confidence: finalConfidence,
              };
              return updated;
            });
            if (!activeSessionId && newSessionId) {
              setActiveSessionId(newSessionId);
              loadSessions();
            }
            break;
          case "error":
            setMessages(prev => {
              const updated = [...prev];
              updated[updated.length - 1] = {
                ...updated[updated.length - 1],
                content: "Sorry, an error occurred while processing your request. Please try again.",
                streaming: false,
                status: undefined,
              };
              return updated;
            });
            break;
        }
      }
    } catch (err) {
      setMessages(prev => {
        const updated = [...prev];
        updated[updated.length - 1] = {
          ...updated[updated.length - 1],
          content: err instanceof Error ? err.message : "Failed to send message. Please check your connection and try again.",
          streaming: false,
          status: undefined,
        };
        return updated;
      });
    } finally {
      setSending(false);
      inputRef.current?.focus();
    }
  };

  const handleNewChat = () => {
    setActiveSessionId(null);
    setMessages([]);
    inputRef.current?.focus();
  };

  const handleDeleteSession = async (sessionId: string) => {
    if (!token) return;
    await deleteConversation(token, sessionId);
    if (activeSessionId === sessionId) {
      setActiveSessionId(null);
      setMessages([]);
    }
    loadSessions();
  };

  const handleEvaluate = async () => {
    if (!token) return;
    setEvalLoading(true);
    try {
      const result = await runEvaluation(token);
      setEvalResult(result);
      setActivePanel("eval");
    } catch {
      setEvalResult({ metrics: { error: 1 }, results: [] });
    } finally {
      setEvalLoading(false);
    }
  };

  const handleRAGEval = async () => {
    if (!token) return;
    setRagEvalLoading(true);
    try {
      const result = await runRAGEvaluation(token);
      setRagEvalResult(result);
      setActivePanel("rag-eval");
    } catch {
      setRagEvalResult(null);
    } finally {
      setRagEvalLoading(false);
    }
  };

  const handleInjectionTest = async () => {
    if (!token) return;
    setInjectionLoading(true);
    try {
      const result = await runInjectionTest(token);
      setInjectionResult(result);
      setActivePanel("security");
    } catch {
      setInjectionResult(null);
    } finally {
      setInjectionLoading(false);
    }
  };

  const handlePIICheck = async () => {
    if (!token || !piiInput.trim()) return;
    setPiiLoading(true);
    try {
      const result = await checkPII(token, piiInput);
      setPiiResult(result);
    } catch {
      setPiiResult(null);
    } finally {
      setPiiLoading(false);
    }
  };

  const handleObservability = async () => {
    if (!token) return;
    setObservabilityLoading(true);
    try {
      const data = await getObservability(token);
      setObservability(data);
      setActivePanel("observability");
    } catch {
      setObservability(null);
    } finally {
      setObservabilityLoading(false);
    }
  };

  const handleFeedback = async (msgIndex: number, rating: "positive" | "negative") => {
    if (!token || !activeSessionId) return;
    const msg = messages[msgIndex];
    if (!msg || msg.feedbackGiven) return;
    setMessages(prev => {
      const updated = [...prev];
      updated[msgIndex].feedbackGiven = rating;
      return updated;
    });
    try {
      await submitFeedback(token, msg.message_id, activeSessionId, rating);
    } catch { /* best-effort */ }
  };

  const handleEscalate = async () => {
    if (!token) return;
    setEscLoading(true);
    try {
      await createEscalation(token, activeSessionId || undefined, "User requested escalation from chat interface");
      loadEscalations();
      setActivePanel("escalations");
    } catch { /* ignore */ } finally {
      setEscLoading(false);
    }
  };

  const loadEscalations = async () => {
    if (!token) return;
    const data = await listEscalations(token);
    setEscalations(data);
  };

  const loadAnalytics = async () => {
    if (!token) return;
    try {
      const data = await getAnalytics(token);
      setAnalytics(data);
    } catch { /* ignore */ }
  };

  const loadDocuments = async () => {
    if (!token) return;
    const data = await listDocuments(token);
    setDocuments(data);
  };

  const loadWebhooks = async () => {
    if (!token) return;
    const data = await listWebhooks(token);
    setWebhooks(data);
  };

  const handleExport = async () => {
    if (!token || !activeSessionId) return;
    try {
      const data = await exportConversation(token, activeSessionId);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `conversation-${activeSessionId.slice(0, 8)}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch { /* ignore */ }
  };

  const openPanel = (panel: PanelType) => {
    if (activePanel === panel) {
      setActivePanel("none");
      return;
    }
    setActivePanel(panel);
    if (panel === "escalations") loadEscalations();
    if (panel === "analytics") loadAnalytics();
    if (panel === "documents") loadDocuments();
    if (panel === "webhooks") loadWebhooks();
    if (panel === "security") handleInjectionTest();
    if (panel === "observability") handleObservability();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <div className="h-screen bg-slate-950 flex overflow-hidden">
      {/* Sidebar */}
      {showSidebar && (
        <div className="w-72 bg-slate-900 border-r border-slate-800 flex flex-col flex-shrink-0">
          <div className="p-3 border-b border-slate-800">
            <button
              onClick={handleNewChat}
              className="w-full flex items-center gap-2 px-3 py-2.5 bg-slate-800 hover:bg-slate-700 border border-slate-700 rounded-lg text-sm text-white font-medium transition-colors"
            >
              <Plus className="w-4 h-4" /> New conversation
            </button>
          </div>

          <div className="flex-1 overflow-y-auto p-2 space-y-1">
            {sessions.length === 0 ? (
              <p className="text-xs text-slate-500 text-center py-4">No conversations yet</p>
            ) : (
              sessions.map((s) => (
                <div
                  key={s.session_id}
                  className={`group flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer transition-colors ${
                    activeSessionId === s.session_id ? "bg-slate-800" : "hover:bg-slate-800/50"
                  }`}
                  onClick={() => loadConversation(s.session_id)}
                >
                  <MessageSquare className="w-3.5 h-3.5 text-slate-500 flex-shrink-0" />
                  <span className="text-sm text-slate-300 truncate flex-1">{s.title}</span>
                  <button
                    onClick={(e) => { e.stopPropagation(); handleDeleteSession(s.session_id); }}
                    className="opacity-0 group-hover:opacity-100 text-slate-500 hover:text-rose-400 transition-all"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              ))
            )}
          </div>

          <div className="p-3 border-t border-slate-800 space-y-1.5">
            <button
              onClick={handleEvaluate}
              disabled={evalLoading}
              className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors disabled:opacity-50"
            >
              {evalLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <BarChart3 className="w-4 h-4" />}
              Intent Evaluation
            </button>
            <button
              onClick={handleRAGEval}
              disabled={ragEvalLoading}
              className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors disabled:opacity-50"
            >
              {ragEvalLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <FileText className="w-4 h-4" />}
              RAG Evaluation
            </button>
            <button
              onClick={() => openPanel("security")}
              className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors"
            >
              <ShieldCheck className="w-4 h-4" /> Security Tests
            </button>
            {isStaff && (
              <button
                onClick={handleObservability}
                disabled={observabilityLoading}
                className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors disabled:opacity-50"
              >
                {observabilityLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Eye className="w-4 h-4" />}
                LLM Observability
              </button>
            )}
            {isStaff && (
              <>
                <button
                  onClick={() => openPanel("analytics")}
                  className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors"
                >
                  <TrendingUp className="w-4 h-4" /> Analytics
                </button>
                <button
                  onClick={() => openPanel("escalations")}
                  className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors"
                >
                  <UserCog className="w-4 h-4" /> Escalations
                </button>
                {user?.role === "admin" && (
                  <>
                    <button
                      onClick={() => openPanel("documents")}
                      className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors"
                    >
                      <Upload className="w-4 h-4" /> Documents
                    </button>
                    <button
                      onClick={() => openPanel("webhooks")}
                      className="w-full flex items-center gap-2 px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-300 transition-colors"
                    >
                      <Webhook className="w-4 h-4" /> Webhooks
                    </button>
                  </>
                )}
              </>
            )}
            <div className="flex items-center gap-2 px-3 py-2 bg-slate-800/30 rounded-lg mt-1">
              <div className="w-8 h-8 rounded-full bg-gradient-to-br from-blue-500 to-emerald-500 flex items-center justify-center flex-shrink-0">
                <User className="w-4 h-4 text-white" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-xs text-white font-medium truncate">{user?.email}</p>
                <p className="text-xs text-slate-500">{user ? ROLE_LABELS[user.role] : ""}</p>
              </div>
              <button onClick={signOut} className="text-slate-500 hover:text-rose-400 transition-colors">
                <LogOut className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Main chat area */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Header */}
        <div className="px-4 py-3 border-b border-slate-800 flex items-center justify-between bg-slate-900/50">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setShowSidebar(!showSidebar)}
              className="text-slate-400 hover:text-white transition-colors"
            >
              <MessageSquare className="w-5 h-5" />
            </button>
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-blue-500 to-emerald-500 flex items-center justify-center">
                <Brain className="w-5 h-5 text-white" />
              </div>
              <div>
                <h1 className="text-sm font-semibold text-white">AI Support Copilot</h1>
                <div className="flex items-center gap-1.5">
                  {health && (
                    <span className={`w-1.5 h-1.5 rounded-full ${health.llm_configured ? "bg-emerald-400" : "bg-amber-400"}`} />
                  )}
                  <span className="text-xs text-slate-500">
                    {health?.llm_configured ? `LLM: ${health.llm_provider}` : "LLM: local fallback"}
                  </span>
                </div>
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {activeSessionId && (
              <button
                onClick={handleExport}
                className="text-xs px-2.5 py-1.5 rounded-lg border border-slate-700 text-slate-400 hover:text-white hover:border-slate-600 transition-colors flex items-center gap-1.5"
              >
                <Download className="w-3.5 h-3.5" /> Export
              </button>
            )}
            <button
              onClick={handleEscalate}
              disabled={escLoading}
              className="text-xs px-2.5 py-1.5 rounded-lg border border-rose-500/30 text-rose-400 hover:bg-rose-500/10 transition-colors flex items-center gap-1.5 disabled:opacity-50"
            >
              {escLoading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <UserCog className="w-3.5 h-3.5" />}
              Escalate
            </button>
            {health && (
              <span className={`text-xs px-2 py-1 rounded-full border ${
                health.status === "healthy"
                  ? "text-emerald-400 bg-emerald-500/10 border-emerald-500/20"
                  : "text-amber-400 bg-amber-500/10 border-amber-500/20"
              }`}>
                <Activity className="w-3 h-3 inline mr-1" />
                {health.status}
              </span>
            )}
          </div>
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto">
          {messages.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center p-8">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-blue-500/20 to-emerald-500/20 flex items-center justify-center mb-4">
                <Brain className="w-8 h-8 text-blue-400" />
              </div>
              <h2 className="text-xl font-semibold text-white mb-2">How can I help you?</h2>
              <p className="text-sm text-slate-400 mb-8 text-center max-w-md">
                I can help with knowledge questions, orders, invoices, banking, healthcare, HR, IT support, procurement, and human agent escalation.
              </p>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3 max-w-2xl w-full">
                {SUGGESTED_PROMPTS.map((p) => (
                  <button
                    key={p.text}
                    onClick={() => handleSend(p.text)}
                    className="flex items-center gap-3 px-4 py-3 bg-slate-900 hover:bg-slate-800 border border-slate-800 hover:border-slate-700 rounded-xl text-left transition-all group"
                  >
                    <p.icon className="w-4 h-4 text-slate-500 group-hover:text-blue-400 transition-colors flex-shrink-0" />
                    <span className="text-sm text-slate-300">{p.text}</span>
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <div className="max-w-3xl mx-auto p-4 space-y-6">
              {messages.map((msg, i) => (
                <MessageBubble key={i} message={msg} onFeedback={(rating) => handleFeedback(i, rating)} />
              ))}
              <div ref={messagesEndRef} />
            </div>
          )}
        </div>

        {/* Input */}
        <div className="p-4 border-t border-slate-800 bg-slate-900/50">
          <div className="max-w-3xl mx-auto">
            <div className="relative flex items-end gap-2 bg-slate-800/50 border border-slate-700 rounded-2xl p-2 focus-within:border-blue-500 transition-colors">
              <textarea
                ref={inputRef}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Ask about policies, orders, invoices, banking, healthcare, HR, IT, procurement..."
                rows={1}
                className="flex-1 bg-transparent text-sm text-white placeholder-slate-500 resize-none focus:outline-none px-2 py-2 max-h-32"
                style={{ minHeight: "40px" }}
              />
              <button
                onClick={() => handleSend()}
                disabled={!input.trim() || sending}
                className="w-10 h-10 flex items-center justify-center bg-gradient-to-br from-blue-500 to-emerald-500 text-white rounded-xl hover:from-blue-600 hover:to-emerald-600 disabled:opacity-30 disabled:cursor-not-allowed transition-all flex-shrink-0"
              >
                {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
              </button>
            </div>
            <p className="text-xs text-slate-600 mt-2 text-center">
              Press Enter to send, Shift+Enter for new line
            </p>
          </div>
        </div>
      </div>

      {/* Side panel */}
      {activePanel !== "none" && (
        <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setActivePanel("none")}>
          <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6 max-w-3xl w-full max-h-[85vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold text-white flex items-center gap-2">
                {activePanel === "eval" && <><BarChart3 className="w-5 h-5 text-blue-400" /> Intent Evaluation Results</>}
                {activePanel === "rag-eval" && <><FileText className="w-5 h-5 text-emerald-400" /> RAG Evaluation Results</>}
                {activePanel === "analytics" && <><TrendingUp className="w-5 h-5 text-blue-400" /> Analytics Dashboard</>}
                {activePanel === "escalations" && <><UserCog className="w-5 h-5 text-amber-400" /> Escalations</>}
                {activePanel === "documents" && <><Upload className="w-5 h-5 text-emerald-400" /> Document Management</>}
                {activePanel === "webhooks" && <><Webhook className="w-5 h-5 text-purple-400" /> Webhook Endpoints</>}
                {activePanel === "security" && <><ShieldCheck className="w-5 h-5 text-rose-400" /> Security Test Suite</>}
                {activePanel === "observability" && <><Eye className="w-5 h-5 text-cyan-400" /> LLM Observability</>}
              </h2>
              <button onClick={() => setActivePanel("none")} className="text-slate-500 hover:text-white">
                <X className="w-5 h-5" />
              </button>
            </div>
            {activePanel === "eval" && evalResult && <EvalDisplay result={evalResult} />}
            {activePanel === "rag-eval" && ragEvalResult && <RAGEvalDisplay result={ragEvalResult} />}
            {activePanel === "analytics" && analytics && <AnalyticsDisplay data={analytics} />}
            {activePanel === "escalations" && <EscalationsDisplay escalations={escalations} />}
            {activePanel === "documents" && token && <DocumentsDisplay documents={documents} onUpload={loadDocuments} token={token} />}
            {activePanel === "webhooks" && token && <WebhooksDisplay webhooks={webhooks} token={token} onRefresh={loadWebhooks} />}
            {activePanel === "security" && <SecurityDisplay injectionResult={injectionResult} injectionLoading={injectionLoading} onRunInjection={handleInjectionTest} piiInput={piiInput} setPiiInput={setPiiInput} onPIICheck={handlePIICheck} piiResult={piiResult} piiLoading={piiLoading} />}
            {activePanel === "observability" && observability && <ObservabilityDisplay data={observability} />}
            {activePanel === "rag-eval" && ragEvalLoading && <div className="flex items-center justify-center py-8"><Loader2 className="w-6 h-6 text-blue-400 animate-spin" /></div>}
          </div>
        </div>
      )}
    </div>
  );
}

function MessageBubble({ message, onFeedback }: { message: DisplayMessage; onFeedback: (rating: "positive" | "negative") => void }) {
  const isUser = message.role === "user";
  const intent = message.intent as Intent | undefined;
  const intentLabel = intent ? INTENT_LABELS[intent] : null;
  const intentColor = intent ? INTENT_COLORS[intent] : null;

  if (isUser) {
    return (
      <div className="flex justify-end">
        <div className="max-w-[80%] bg-gradient-to-br from-blue-600 to-blue-500 text-white rounded-2xl rounded-tr-sm px-4 py-3 shadow-lg">
          <p className="text-sm whitespace-pre-wrap">{message.content}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex gap-3">
      <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-blue-500 to-emerald-500 flex items-center justify-center flex-shrink-0 mt-1">
        <Brain className="w-4 h-4 text-white" />
      </div>
      <div className="flex-1 min-w-0">
        {message.streaming && message.status && (
          <div className="flex items-center gap-2 mb-2">
            <Loader2 className="w-3.5 h-3.5 text-blue-400 animate-spin" />
            <span className="text-xs text-slate-400">{message.status}</span>
          </div>
        )}

        {!message.streaming && (intentLabel || message.toolBadge) && (
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            {intentLabel && intentColor && (
              <span className={`text-xs font-medium px-2 py-0.5 rounded-full border ${intentColor}`}>
                {intentLabel}
              </span>
            )}
            {message.toolBadge && (
              <span className="text-xs text-slate-500 flex items-center gap-1">
                <Wrench className="w-3 h-3" />
                {message.toolBadge}
              </span>
            )}
            {message.confidence !== undefined && message.confidence > 0 && (
              <span className="text-xs text-slate-600">
                {(message.confidence * 100).toFixed(0)}% confidence
              </span>
            )}
          </div>
        )}

        <div className="bg-slate-800/50 border border-slate-700/50 rounded-2xl rounded-tl-sm px-4 py-3">
          <p className="text-sm text-slate-100 whitespace-pre-wrap">{message.content || (message.streaming ? "" : "(empty response)")}</p>
        </div>

        {message.sources && message.sources.length > 0 && (
          <div className="mt-2 space-y-1">
            <p className="text-xs text-slate-500 font-medium">Sources:</p>
            {message.sources.map((src, i) => (
              <div key={i} className="flex items-start gap-2 text-xs text-slate-400 bg-slate-800/30 border border-slate-700/30 rounded-lg px-3 py-2">
                <FileText className="w-3.5 h-3.5 text-slate-500 flex-shrink-0 mt-0.5" />
                <div>
                  <span className="text-slate-300 font-medium">{src.title}</span>
                  <span className="text-slate-600"> — {src.source}</span>
                  {src.similarity && (
                    <span className="text-slate-600"> (similarity: {(src.similarity * 100).toFixed(1)}%)</span>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {!message.streaming && message.content && (
          <div className="flex items-center gap-3 mt-2">
            <div className="flex items-center gap-1">
              <button
                onClick={() => onFeedback("positive")}
                disabled={!!message.feedbackGiven}
                className={`p-1 rounded transition-colors ${
                  message.feedbackGiven === "positive"
                    ? "text-emerald-400 bg-emerald-500/10"
                    : "text-slate-600 hover:text-emerald-400 hover:bg-emerald-500/5"
                } disabled:cursor-default`}
              >
                <ThumbsUp className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={() => onFeedback("negative")}
                disabled={!!message.feedbackGiven}
                className={`p-1 rounded transition-colors ${
                  message.feedbackGiven === "negative"
                    ? "text-rose-400 bg-rose-500/10"
                    : "text-slate-600 hover:text-rose-400 hover:bg-rose-500/5"
                } disabled:cursor-default`}
              >
                <ThumbsDown className="w-3.5 h-3.5" />
              </button>
            </div>
            {message.latency_ms && (
              <span className="text-xs text-slate-600">{message.latency_ms}ms</span>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function EvalDisplay({ result }: { result: { metrics: Record<string, number>; results: unknown[] } }) {
  const metrics = result.metrics;
  const metricLabels: Record<string, string> = {
    intent_accuracy: "Intent Classification Accuracy",
    tool_selection_accuracy: "Tool Selection Accuracy",
    total_questions: "Total Questions",
    latency_ms: "Total Latency (ms)",
  };

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        {Object.entries(metrics).map(([key, value]) => (
          <div key={key} className="bg-slate-800/50 border border-slate-700 rounded-lg p-3">
            <p className="text-xs text-slate-500">{metricLabels[key] || key}</p>
            <p className="text-lg font-semibold text-white">
              {key.includes("accuracy") ? `${(value * 100).toFixed(1)}%` : value.toFixed(0)}
            </p>
          </div>
        ))}
      </div>
      <div>
        <p className="text-xs text-slate-500 mb-2">Per-question results:</p>
        <div className="space-y-1">
          {(result.results as Array<Record<string, unknown>>).map((r, i) => (
            <div key={i} className="flex items-center gap-3 text-xs bg-slate-800/30 border border-slate-700/30 rounded-lg px-3 py-2">
              <span className={`w-2 h-2 rounded-full ${r.intent_correct ? "bg-emerald-400" : "bg-rose-400"}`} />
              <span className="text-slate-300 flex-1 truncate">{r.question as string}</span>
              <span className="text-slate-500">expected: {r.expected_intent as string}</span>
              <span className="text-slate-400">got: {r.predicted_intent as string}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function AnalyticsDisplay({ data }: { data: AnalyticsData }) {
  const sentimentIcons: Record<string, typeof Smile> = {
    positive: Smile, negative: Frown, neutral: Meh,
  };

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <StatCard label="Total Events" value={data.total_events} icon={Activity} color="text-blue-400" />
        <StatCard label="Conversations" value={data.total_conversations} icon={MessageSquare} color="text-emerald-400" />
        <StatCard label="Avg Latency" value={`${data.avg_latency_ms}ms`} icon={Clock} color="text-amber-400" />
        <StatCard label="Satisfaction" value={`${data.feedback.satisfaction_rate}%`} icon={ThumbsUp} color="text-rose-400" />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
          <h3 className="text-sm font-medium text-slate-300 mb-3">Intent Distribution</h3>
          <div className="space-y-2">
            {Object.entries(data.intent_distribution).map(([intent, count]) => (
              <div key={intent} className="flex items-center justify-between text-xs">
                <span className="text-slate-400 capitalize">{intent}</span>
                <div className="flex items-center gap-2 flex-1 ml-3">
                  <div className="flex-1 h-1.5 bg-slate-700 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-blue-500 rounded-full"
                      style={{ width: `${data.total_events > 0 ? (count / data.total_events) * 100 : 0}%` }}
                    />
                  </div>
                  <span className="text-slate-500 w-8 text-right">{count}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
          <h3 className="text-sm font-medium text-slate-300 mb-3">Tool Usage</h3>
          <div className="space-y-2">
            {Object.entries(data.tool_usage).map(([tool, count]) => (
              <div key={tool} className="flex items-center justify-between text-xs">
                <span className="text-slate-400">{tool}</span>
                <span className="text-slate-500">{count}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
          <h3 className="text-sm font-medium text-slate-300 mb-3">Sentiment</h3>
          <div className="space-y-2">
            {Object.entries(data.sentiment_distribution).map(([sentiment, count]) => {
              const Icon = sentimentIcons[sentiment] || Meh;
              return (
                <div key={sentiment} className="flex items-center justify-between text-xs">
                  <span className="text-slate-400 flex items-center gap-1.5 capitalize">
                    <Icon className="w-3.5 h-3.5" /> {sentiment}
                  </span>
                  <span className="text-slate-500">{count}</span>
                </div>
              );
            })}
          </div>
        </div>

        <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
          <h3 className="text-sm font-medium text-slate-300 mb-3">Languages</h3>
          <div className="space-y-2">
            {Object.entries(data.language_distribution).map(([lang, count]) => (
              <div key={lang} className="flex items-center justify-between text-xs">
                <span className="text-slate-400 flex items-center gap-1.5 capitalize">
                  <Globe className="w-3.5 h-3.5" /> {lang}
                </span>
                <span className="text-slate-500">{count}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
          <p className="text-xs text-slate-500">Feedback</p>
          <p className="text-lg font-semibold text-white">{data.feedback.total}</p>
          <p className="text-xs text-emerald-400">{data.feedback.positive} positive</p>
          <p className="text-xs text-rose-400">{data.feedback.negative} negative</p>
        </div>
        <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
          <p className="text-xs text-slate-500">Open Escalations</p>
          <p className="text-lg font-semibold text-amber-400">{data.escalations.open}</p>
        </div>
        <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
          <p className="text-xs text-slate-500">Resolved</p>
          <p className="text-lg font-semibold text-emerald-400">{data.escalations.resolved}</p>
        </div>
      </div>
    </div>
  );
}

function StatCard({ label, value, icon: Icon, color }: { label: string; value: string | number; icon: typeof Activity; color: string }) {
  return (
    <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-3">
      <div className="flex items-center gap-2 mb-1">
        <Icon className={`w-4 h-4 ${color}`} />
        <p className="text-xs text-slate-500">{label}</p>
      </div>
      <p className="text-xl font-semibold text-white">{value}</p>
    </div>
  );
}

function EscalationsDisplay({ escalations }: { escalations: Escalation[] }) {
  if (escalations.length === 0) {
    return <p className="text-sm text-slate-500 text-center py-8">No escalations yet.</p>;
  }
  return (
    <div className="space-y-3">
      {escalations.map((esc) => (
        <div key={esc.escalation_id} className="bg-slate-800/50 border border-slate-700 rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-white">{esc.escalation_id.slice(0, 8)}</span>
            <div className="flex items-center gap-2">
              <span className={`text-xs px-2 py-0.5 rounded-full border ${
                esc.status === "open" ? "text-amber-400 bg-amber-500/10 border-amber-500/20" :
                esc.status === "resolved" || esc.status === "closed" ? "text-emerald-400 bg-emerald-500/10 border-emerald-500/20" :
                "text-blue-400 bg-blue-500/10 border-blue-500/20"
              }`}>{esc.status}</span>
              <span className={`text-xs px-2 py-0.5 rounded-full border ${
                esc.priority === "urgent" ? "text-red-400 bg-red-500/10 border-red-500/20" :
                esc.priority === "high" ? "text-amber-400 bg-amber-500/10 border-amber-500/20" :
                "text-slate-400 bg-slate-500/10 border-slate-500/20"
              }`}>{esc.priority}</span>
            </div>
          </div>
          <p className="text-sm text-slate-300">{esc.reason}</p>
          {esc.conversation_summary && (
            <p className="text-xs text-slate-500 mt-1">{esc.conversation_summary}</p>
          )}
          <p className="text-xs text-slate-600 mt-2">{new Date(esc.created_at).toLocaleString()}</p>
        </div>
      ))}
    </div>
  );
}

function DocumentsDisplay({ documents, onUpload, token }: { documents: DocumentUpload[]; onUpload: () => void; token: string }) {
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [docType, setDocType] = useState("policy");
  const [department, setDepartment] = useState("general");
  const [uploading, setUploading] = useState(false);
  const [uploadMsg, setUploadMsg] = useState<string | null>(null);

  const handleUpload = async () => {
    if (!title.trim() || !content.trim()) return;
    setUploading(true);
    setUploadMsg(null);
    try {
      const result = await uploadDocument(token, { title, content, document_type: docType, department });
      setUploadMsg(`Uploaded: ${result.document_id} (${result.chunks_inserted} chunks)`);
      setTitle("");
      setContent("");
      onUpload();
    } catch (err) {
      setUploadMsg(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="space-y-5">
      <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
        <h3 className="text-sm font-medium text-slate-300 mb-3">Upload New Document</h3>
        <div className="space-y-3">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Document title"
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500"
          />
          <div className="grid grid-cols-2 gap-3">
            <select
              value={docType}
              onChange={(e) => setDocType(e.target.value)}
              className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white focus:outline-none focus:border-blue-500"
            >
              <option value="policy">Policy</option>
              <option value="faq">FAQ</option>
              <option value="guide">Guide</option>
              <option value="manual">Manual</option>
            </select>
            <select
              value={department}
              onChange={(e) => setDepartment(e.target.value)}
              className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white focus:outline-none focus:border-blue-500"
            >
              <option value="general">General</option>
              <option value="hr">HR</option>
              <option value="finance">Finance</option>
              <option value="support">Support</option>
              <option value="banking">Banking</option>
              <option value="hospital">Hospital</option>
              <option value="it">IT</option>
            </select>
          </div>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="Paste document content here..."
            rows={5}
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 resize-none"
          />
          <button
            onClick={handleUpload}
            disabled={uploading || !title.trim() || !content.trim()}
            className="px-4 py-2 bg-gradient-to-r from-blue-500 to-emerald-500 text-white text-sm font-medium rounded-lg hover:from-blue-600 hover:to-emerald-600 disabled:opacity-50 transition-all flex items-center gap-2"
          >
            {uploading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}
            Upload & Auto-Chunk
          </button>
          {uploadMsg && <p className="text-xs text-slate-400">{uploadMsg}</p>}
        </div>
      </div>

      <div>
        <h3 className="text-sm font-medium text-slate-300 mb-3">Uploaded Documents</h3>
        {documents.length === 0 ? (
          <p className="text-sm text-slate-500 text-center py-4">No documents uploaded yet.</p>
        ) : (
          <div className="space-y-2">
            {documents.map((doc) => (
              <div key={doc.upload_id} className="flex items-center gap-3 bg-slate-800/30 border border-slate-700/30 rounded-lg px-3 py-2">
                <FileText className="w-4 h-4 text-slate-500 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-white truncate">{doc.title}</p>
                  <p className="text-xs text-slate-500">{doc.document_id} — {doc.chunk_count} chunks — {doc.department}</p>
                </div>
                <span className={`text-xs px-2 py-0.5 rounded-full ${doc.status === "completed" ? "text-emerald-400 bg-emerald-500/10" : "text-amber-400 bg-amber-500/10"}`}>
                  {doc.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function RAGEvalDisplay({ result }: { result: { metrics: RAGEvalMetrics; results: RAGEvalResult[] } }) {
  const m = result.metrics;
  const pct = (v: number) => `${(v * 100).toFixed(1)}%`;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
        <EvalMetricCard label="Faithfulness" value={pct(m.avg_faithfulness)} icon={CheckCircle2} color="text-emerald-400" />
        <EvalMetricCard label="Answer Relevancy" value={pct(m.avg_answer_relevancy)} icon={Zap} color="text-blue-400" />
        <EvalMetricCard label="Context Precision" value={pct(m.avg_context_precision)} icon={FileText} color="text-cyan-400" />
        <EvalMetricCard label="Context Recall" value={pct(m.avg_context_recall)} icon={FileText} color="text-teal-400" />
        <EvalMetricCard label="Citation Accuracy" value={pct(m.avg_citation_accuracy)} icon={CheckCircle2} color="text-emerald-400" />
        <EvalMetricCard label="Hallucination Rate" value={pct(m.hallucination_rate)} icon={AlertTriangle} color="text-rose-400" />
      </div>
      <div>
        <p className="text-xs text-slate-500 mb-2">Per-question results:</p>
        <div className="space-y-2">
          {result.results.map((r, i) => (
            <div key={i} className="bg-slate-800/30 border border-slate-700/30 rounded-lg p-3">
              <div className="flex items-center gap-2 mb-2">
                {r.hallucination_detected ? (
                  <XCircle className="w-4 h-4 text-rose-400" />
                ) : (
                  <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                )}
                <span className="text-sm text-slate-300 flex-1">{r.question}</span>
              </div>
              <div className="grid grid-cols-5 gap-2 text-xs">
                <div><span className="text-slate-500">Faith:</span> <span className="text-slate-300">{pct(r.faithfulness)}</span></div>
                <div><span className="text-slate-500">Rel:</span> <span className="text-slate-300">{pct(r.answer_relevancy)}</span></div>
                <div><span className="text-slate-500">Prec:</span> <span className="text-slate-300">{pct(r.context_precision)}</span></div>
                <div><span className="text-slate-500">Recall:</span> <span className="text-slate-300">{pct(r.context_recall)}</span></div>
                <div><span className="text-slate-500">Cite:</span> <span className="text-slate-300">{pct(r.citation_accuracy)}</span></div>
              </div>
              <p className="text-xs text-slate-400 mt-2 line-clamp-2">{r.answer.slice(0, 200)}...</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function EvalMetricCard({ label, value, icon: Icon, color }: { label: string; value: string; icon: typeof Activity; color: string }) {
  return (
    <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3">
      <div className="flex items-center gap-2 mb-1">
        <Icon className={`w-4 h-4 ${color}`} />
        <p className="text-xs text-slate-500">{label}</p>
      </div>
      <p className="text-lg font-semibold text-white">{value}</p>
    </div>
  );
}

function SecurityDisplay({ injectionResult, injectionLoading, onRunInjection, piiInput, setPiiInput, onPIICheck, piiResult, piiLoading }: {
  injectionResult: InjectionTestResult | null;
  injectionLoading: boolean;
  onRunInjection: () => void;
  piiInput: string;
  setPiiInput: (v: string) => void;
  onPIICheck: () => void;
  piiResult: PIICheckResult | null;
  piiLoading: boolean;
}) {
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-sm font-medium text-slate-300 mb-3 flex items-center gap-2">
          <ShieldAlert className="w-4 h-4 text-rose-400" /> Prompt Injection Defense
        </h3>
        <button
          onClick={onRunInjection}
          disabled={injectionLoading}
          className="px-4 py-2 bg-gradient-to-r from-rose-500 to-orange-500 text-white text-sm font-medium rounded-lg hover:from-rose-600 hover:to-orange-600 disabled:opacity-50 transition-all flex items-center gap-2 mb-4"
        >
          {injectionLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <ShieldCheck className="w-4 h-4" />}
          Run Injection Test Suite
        </button>
        {injectionResult && (
          <div className="space-y-3">
            <div className="grid grid-cols-3 gap-3">
              <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
                <p className="text-xs text-slate-500">Total Tests</p>
                <p className="text-lg font-semibold text-white">{injectionResult.total}</p>
              </div>
              <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
                <p className="text-xs text-slate-500">Passed</p>
                <p className="text-lg font-semibold text-emerald-400">{injectionResult.passed}</p>
              </div>
              <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
                <p className="text-xs text-slate-500">Pass Rate</p>
                <p className="text-lg font-semibold text-white">{(injectionResult.pass_rate * 100).toFixed(0)}%</p>
              </div>
            </div>
            <div className="space-y-2">
              {injectionResult.results.map((r, i) => (
                <div key={i} className="flex items-center gap-3 bg-slate-800/30 border border-slate-700/30 rounded-lg px-3 py-2">
                  {r.passed ? (
                    <CheckCircle2 className="w-4 h-4 text-emerald-400 flex-shrink-0" />
                  ) : (
                    <XCircle className="w-4 h-4 text-rose-400 flex-shrink-0" />
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-slate-300">{r.description}</p>
                    <p className="text-xs text-slate-600 truncate">"{r.input.slice(0, 60)}"</p>
                  </div>
                  <span className={`text-xs px-2 py-0.5 rounded-full ${r.detected ? "text-rose-400 bg-rose-500/10" : "text-emerald-400 bg-emerald-500/10"}`}>
                    {r.detected ? "Blocked" : "Allowed"}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      <div>
        <h3 className="text-sm font-medium text-slate-300 mb-3 flex items-center gap-2">
          <Eye className="w-4 h-4 text-cyan-400" /> PII Detection & Redaction
        </h3>
        <textarea
          value={piiInput}
          onChange={(e) => setPiiInput(e.target.value)}
          placeholder="Enter text to check for PII (e.g., 'My email is john@company.com and my SSN is 123-45-6789')"
                   rows={3}
          className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-cyan-500 resize-none mb-2"
        />
        <button
          onClick={onPIICheck}
          disabled={piiLoading || !piiInput.trim()}
          className="px-4 py-2 bg-gradient-to-r from-cyan-500 to-blue-500 text-white text-sm font-medium rounded-lg hover:from-cyan-600 hover:to-blue-600 disabled:opacity-50 transition-all flex items-center gap-2 mb-3"
        >
          {piiLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Eye className="w-4 h-4" />}
          Check for PII
        </button>
        {piiResult && (
          <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 space-y-2">
            <p className="text-sm font-medium text-white">{piiResult.has_pii ? "PII Detected!" : "No PII detected"}</p>
            {piiResult.detections.length > 0 && (
              <div className="space-y-1">
                {piiResult.detections.map((d, i) => (
                  <div key={i} className="flex items-center gap-2 text-xs">
                    <AlertTriangle className="w-3 h-3 text-amber-400" />
                    <span className="text-slate-400">{d.type}</span>
                    <span className="text-slate-600">→</span>
                    <span className="text-rose-400">{d.replacement}</span>
                  </div>
                ))}
              </div>
            )}
            {piiResult.has_pii && (
              <div>
                <p className="text-xs text-slate-500 mb-1">Redacted text:</p>
                <p className="text-xs text-slate-300 bg-slate-800/50 rounded p-2">{piiResult.redacted_text}</p>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function ObservabilityDisplay({ data }: { data: ObservabilityData }) {
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <StatCard label="Total Calls" value={data.total_calls} icon={Activity} color="text-blue-400" />
        <StatCard label="Success Rate" value={`${(data.success_rate * 100).toFixed(1)}%`} icon={CheckCircle2} color="text-emerald-400" />
        <StatCard label="Total Tokens" value={data.total_tokens.toLocaleString()} icon={Zap} color="text-amber-400" />
        <StatCard label="Est. Cost" value={`${data.estimated_cost_usd}`} icon={DollarSign} color="text-emerald-400" />
      </div>

      <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
        <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
          <p className="text-xs text-slate-500">Successful</p>
          <p className="text-lg font-semibold text-emerald-400">{data.successful_calls}</p>
        </div>
        <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
          <p className="text-xs text-slate-500">Failed</p>
          <p className="text-lg font-semibold text-rose-400">{data.failed_calls}</p>
        </div>
        <div className="bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-center">
          <p className="text-xs text-slate-500">Avg Latency</p>
          <p className="text-lg font-semibold text-white">{data.avg_latency_ms}ms</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
          <h3 className="text-sm font-medium text-slate-300 mb-3">Calls by Purpose</h3>
          <div className="space-y-2">
            {Object.entries(data.purpose_distribution).map(([purpose, count]) => (
              <div key={purpose} className="flex items-center justify-between text-xs">
                <span className="text-slate-400">{purpose}</span>
                <span className="text-slate-500">{count}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
          <h3 className="text-sm font-medium text-slate-300 mb-3">Calls by Model</h3>
          <div className="space-y-2">
            {Object.entries(data.model_distribution).map(([model, count]) => (
              <div key={model} className="flex items-center justify-between text-xs">
                <span className="text-slate-400">{model}</span>
                <span className="text-slate-500">{count}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div>
        <h3 className="text-sm font-medium text-slate-300 mb-3">Recent LLM Calls</h3>
        <div className="space-y-2 max-h-64 overflow-y-auto">
          {data.recent_observations.map((obs, i) => (
            <div key={i} className="flex items-center gap-3 bg-slate-800/30 border border-slate-700/30 rounded-lg px-3 py-2 text-xs">
              {obs.success ? (
                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 flex-shrink-0" />
              ) : (
                <XCircle className="w-3.5 h-3.5 text-rose-400 flex-shrink-0" />
              )}
              <span className="text-slate-400">{obs.purpose as string}</span>
              <span className="text-slate-600">{obs.model as string}</span>
              <span className="text-slate-500">{obs.latency_ms as number}ms</span>
              {obs.total_tokens ? <span className="text-slate-500">{obs.total_tokens as number} tok</span> : null}
              <span className="text-slate-600 ml-auto">{new Date(obs.created_at as string).toLocaleTimeString()}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function WebhooksDisplay({ webhooks, token, onRefresh }: { webhooks: WebhookEndpoint[]; token: string; onRefresh: () => void }) {
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");
  const [eventTypes, setEventTypes] = useState("escalation_created");
  const [creating, setCreating] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const handleCreate = async () => {
    if (!name.trim() || !url.trim()) return;
    setCreating(true);
    setMsg(null);
    try {
      await createWebhook(token, { name, url, event_types: eventTypes.split(",").map(s => s.trim()) });
      setMsg("Webhook created successfully");
      setName("");
      setUrl("");
      onRefresh();
    } catch (err) {
      setMsg(err instanceof Error ? err.message : "Failed to create webhook");
    } finally {
      setCreating(false);
    }
  };

  return (
    <div className="space-y-5">
      <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4">
        <h3 className="text-sm font-medium text-slate-300 mb-3">Add Webhook Endpoint</h3>
        <div className="space-y-3">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Webhook name (e.g. Slack notifications)"
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500"
          />
          <input
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            placeholder="https://hooks.slack.com/services/..."
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500"
          />
          <input
            value={eventTypes}
            onChange={(e) => setEventTypes(e.target.value)}
            placeholder="escalation_created,chat (comma-separated)"
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500"
          />
          <button
            onClick={handleCreate}
            disabled={creating || !name.trim() || !url.trim()}
            className="px-4 py-2 bg-gradient-to-r from-blue-500 to-emerald-500 text-white text-sm font-medium rounded-lg hover:from-blue-600 hover:to-emerald-600 disabled:opacity-50 transition-all flex items-center gap-2"
          >
            {creating ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
            Create Webhook
          </button>
          {msg && <p className="text-xs text-slate-400">{msg}</p>}
        </div>
      </div>

      <div>
        <h3 className="text-sm font-medium text-slate-300 mb-3">Configured Endpoints</h3>
        {webhooks.length === 0 ? (
          <p className="text-sm text-slate-500 text-center py-4">No webhooks configured yet.</p>
        ) : (
          <div className="space-y-2">
            {webhooks.map((wh) => (
              <div key={wh.id} className="flex items-center gap-3 bg-slate-800/30 border border-slate-700/30 rounded-lg px-3 py-2">
                <Webhook className="w-4 h-4 text-slate-500 flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-white truncate">{wh.name}</p>
                  <p className="text-xs text-slate-500 truncate">{wh.url}</p>
                  <p className="text-xs text-slate-600">{wh.event_types.join(", ")}</p>
                </div>
                <span className={`text-xs px-2 py-0.5 rounded-full ${wh.active ? "text-emerald-400 bg-emerald-500/10" : "text-slate-500 bg-slate-500/10"}`}>
                  {wh.active ? "Active" : "Inactive"}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
