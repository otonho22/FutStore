import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signInWithPopup,
  GoogleAuthProvider,
  signOut,
  type User,
} from 'firebase/auth';
import { auth } from '../lib/firebase';
import { api } from '../lib/api';

// Acesso administrador padrão (modo local — não passa pelo Firebase).
const LOCAL_ADMIN_KEY = 'pf_local_admin_v1';
const LOCAL_ADMIN_LOGIN = 'adm';
const LOCAL_ADMIN_PASSWORD = 'adm123';

export type LocalAdmin = {
  email: string;
  displayName: string;
  uid: string;
  isLocal: true;
};

export type AppUser = User | LocalAdmin | null;

interface AuthState {
  user: AppUser;
  role: 'admin' | 'customer' | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  signup: (email: string, password: string, displayName: string) => Promise<void>;
  loginWithGoogle: () => Promise<void>;
  logout: () => Promise<void>;
  refreshRole: () => Promise<void>;
}

const AuthContext = createContext<AuthState | undefined>(undefined);

function readLocalAdmin(): LocalAdmin | null {
  try {
    const raw = localStorage.getItem(LOCAL_ADMIN_KEY);
    return raw ? (JSON.parse(raw) as LocalAdmin) : null;
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [firebaseUser, setFirebaseUser] = useState<User | null>(null);
  const [firebaseRole, setFirebaseRole] = useState<'admin' | 'customer' | null>(null);
  const [localAdmin, setLocalAdmin] = useState<LocalAdmin | null>(() => readLocalAdmin());
  const [loading, setLoading] = useState(true);

  async function readRole(u: User) {
    const token = await u.getIdTokenResult();
    return (token.claims.role as 'admin' | 'customer' | undefined) ?? 'customer';
  }

  useEffect(() => {
    return onAuthStateChanged(auth, async (u) => {
      setFirebaseUser(u);
      if (u) {
        setFirebaseRole(await readRole(u));
      } else {
        setFirebaseRole(null);
      }
      setLoading(false);
    });
  }, []);

  const user: AppUser = localAdmin ?? firebaseUser;
  const role: 'admin' | 'customer' | null = localAdmin ? 'admin' : firebaseRole;

  async function login(email: string, password: string) {
    if (email.trim().toLowerCase() === LOCAL_ADMIN_LOGIN && password === LOCAL_ADMIN_PASSWORD) {
      const admin: LocalAdmin = {
        email: 'adm',
        displayName: 'Administrador',
        uid: 'local-admin',
        isLocal: true,
      };
      localStorage.setItem(LOCAL_ADMIN_KEY, JSON.stringify(admin));
      setLocalAdmin(admin);
      return;
    }
    await signInWithEmailAndPassword(auth, email, password);
  }

  async function signup(email: string, password: string, displayName: string) {
    const cred = await createUserWithEmailAndPassword(auth, email, password);
    await cred.user.getIdToken(true);
    await api('/api/users/me', {
      method: 'POST',
      body: JSON.stringify({ displayName, acceptedTerms: true }),
    });
  }

  async function loginWithGoogle() {
    const provider = new GoogleAuthProvider();
    provider.setCustomParameters({ prompt: 'select_account' });
    const cred = await signInWithPopup(auth, provider);
    // Garante que existe doc do usuário no Firestore
    await cred.user.getIdToken(true);
    try {
      await api('/api/users/me', {
        method: 'POST',
        body: JSON.stringify({
          displayName: cred.user.displayName ?? cred.user.email ?? 'Usuário',
          acceptedTerms: true,
        }),
      });
    } catch {
      // não fatal — provavelmente já existia
    }
  }

  async function logout() {
    if (localAdmin) {
      localStorage.removeItem(LOCAL_ADMIN_KEY);
      setLocalAdmin(null);
    }
    if (firebaseUser) {
      await signOut(auth);
    }
  }

  async function refreshRole() {
    if (localAdmin) return;
    if (auth.currentUser) {
      await auth.currentUser.getIdToken(true);
      setFirebaseRole(await readRole(auth.currentUser));
    }
  }

  const value = useMemo<AuthState>(
    () => ({ user, role, loading, login, signup, loginWithGoogle, logout, refreshRole }),
    [user, role, loading],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}

export function isLocalAdmin(user: AppUser): user is LocalAdmin {
  return !!user && (user as LocalAdmin).isLocal === true;
}
