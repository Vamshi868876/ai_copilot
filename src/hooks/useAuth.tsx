import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { supabase } from "@/lib/supabase";
import { login } from "@/lib/api";
import type { AppUser } from "@/types";

interface AuthContextValue {
  user: AppUser | null;
  token: string | null;
  loading: boolean;
  signIn: (email: string, password: string, role?: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AppUser | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const stored = localStorage.getItem("copilot_token");
    const storedUser = localStorage.getItem("copilot_user");
    if (stored && storedUser) {
      setToken(stored);
      setUser(JSON.parse(storedUser));
    }
    setLoading(false);
  }, []);

  const signIn = async (email: string, password: string, role?: string) => {
    const result = await login(email, password, role);
    setToken(result.access_token);
    setUser(result.user);
    localStorage.setItem("copilot_token", result.access_token);
    localStorage.setItem("copilot_user", JSON.stringify(result.user));
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    localStorage.removeItem("copilot_token");
    localStorage.removeItem("copilot_user");
    setToken(null);
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, token, loading, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
