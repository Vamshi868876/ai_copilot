import { useState, useEffect } from "react";
import { useAuth } from "@/hooks/useAuth";
import { setupDemoUsers } from "@/lib/api";
import { ROLE_LABELS, type Role } from "@/types";
import { Brain, Lock, Mail, Shield, ArrowRight, Loader2 } from "lucide-react";

const DEMO_ACCOUNTS: { email: string; role: Role; description: string }[] = [
  { email: "admin@demo.co", role: "admin", description: "Full access to all data and features" },
  { email: "support@demo.co", role: "support_agent", description: "Customer support and ticket management" },
  { email: "finance@demo.co", role: "finance_user", description: "Invoice and billing information" },
  { email: "employee@demo.co", role: "employee", description: "Company policies and own data only" },
  { email: "banker@demo.co", role: "bank_teller", description: "Banking: accounts, transactions, cards, loans" },
  { email: "doctor@demo.co", role: "doctor", description: "Healthcare: appointments, prescriptions, labs" },
  { email: "hr@demo.co", role: "hr_admin", description: "HR: leave requests, pay stubs, employee data" },
  { email: "it@demo.co", role: "it_admin", description: "IT: ticket management, procurement" },
];

export default function LoginPage() {
  const { signIn } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("Demo!Copilot2026");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [initializing, setInitializing] = useState(true);

  useEffect(() => {
    setupDemoUsers()
      .catch(() => {})
      .finally(() => setInitializing(false));
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await signIn(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setLoading(false);
    }
  };

  const quickLogin = async (roleEmail: string) => {
    setEmail(roleEmail);
    setPassword("Demo!Copilot2026");
    setError(null);
    setLoading(true);
    try {
      await signIn(roleEmail, "Demo!Copilot2026");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setLoading(false);
    }
  };

  if (initializing) {
    return (
      <div className="min-h-screen bg-slate-950 flex items-center justify-center">
        <Loader2 className="w-8 h-8 text-blue-500 animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-950 flex items-center justify-center p-4">
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-blue-500/10 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-emerald-500/10 rounded-full blur-3xl" />
      </div>

      <div className="relative w-full max-w-md">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-br from-blue-500 to-emerald-500 rounded-2xl mb-4 shadow-lg shadow-blue-500/20">
            <Brain className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-white">AI Support Copilot</h1>
          <p className="text-sm text-slate-400 mt-1">Enterprise AI Support & Operations</p>
        </div>

        <div className="bg-slate-900/80 backdrop-blur-xl border border-slate-800 rounded-2xl p-6 shadow-2xl">
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="text-xs font-medium text-slate-400 mb-1.5 block">Email</label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@company.com"
                  required
                  className="w-full pl-10 pr-3 py-2.5 bg-slate-800/50 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
                />
              </div>
            </div>

            <div>
              <label className="text-xs font-medium text-slate-400 mb-1.5 block">Password</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Demo!Copilot2026"
                  required
                  className="w-full pl-10 pr-3 py-2.5 bg-slate-800/50 border border-slate-700 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
                />
              </div>
            </div>

            {error && (
              <div className="text-sm text-rose-400 bg-rose-500/10 border border-rose-500/20 rounded-lg px-3 py-2">
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full py-2.5 bg-gradient-to-r from-blue-500 to-emerald-500 text-white font-medium text-sm rounded-lg hover:from-blue-600 hover:to-emerald-600 focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50 transition-all flex items-center justify-center gap-2"
            >
              {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <>Sign In <ArrowRight className="w-4 h-4" /></>}
            </button>
          </form>

          <div className="mt-6 pt-6 border-t border-slate-800">
            <p className="text-xs font-medium text-slate-500 mb-3 flex items-center gap-1.5">
              <Shield className="w-3.5 h-3.5" /> Quick demo login (password: Demo!Copilot2026)
            </p>
            <div className="grid grid-cols-1 gap-2">
              {DEMO_ACCOUNTS.map((acc) => (
                <button
                  key={acc.email}
                  onClick={() => quickLogin(acc.email)}
                  disabled={loading}
                  className="flex items-center justify-between px-3 py-2 bg-slate-800/50 hover:bg-slate-800 border border-slate-700 hover:border-slate-600 rounded-lg text-left transition-colors disabled:opacity-50 group"
                >
                  <div>
                    <span className="text-sm text-white font-medium">{ROLE_LABELS[acc.role]}</span>
                    <span className="text-xs text-slate-500 block">{acc.description}</span>
                  </div>
                  <ArrowRight className="w-4 h-4 text-slate-600 group-hover:text-blue-400 transition-colors" />
                </button>
              ))}
            </div>
          </div>
        </div>

        <p className="text-center text-xs text-slate-600 mt-6">
          RAG + Agentic Tools + RBAC + Conversational Memory
        </p>
      </div>
    </div>
  );
}
