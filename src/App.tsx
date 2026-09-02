import { AuthProvider, useAuth } from "@/hooks/useAuth";
import LoginPage from "@/pages/LoginPage";
import ChatPage from "@/pages/ChatPage";
import { Loader2 } from "lucide-react";

function AppContent() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-950 flex items-center justify-center">
        <Loader2 className="w-8 h-8 text-blue-500 animate-spin" />
      </div>
    );
  }

  return user ? <ChatPage /> : <LoginPage />;
}

export default function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}
