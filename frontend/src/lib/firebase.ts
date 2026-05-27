import { initializeApp, getApp, getApps, type FirebaseApp } from 'firebase/app';
import { getAuth, type Auth } from 'firebase/auth';
import { getAnalytics, isSupported, type Analytics } from 'firebase/analytics';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID,
};

let app: FirebaseApp;
let auth: Auth;
let analytics: Analytics | undefined;

const isConfigValid = firebaseConfig.apiKey && firebaseConfig.apiKey !== "";

if (!isConfigValid) {
  console.warn(
    "⚠️ [Firebase] VITE_FIREBASE_API_KEY is not defined. Firebase features will not work.\n" +
    "Please create a '.env' file inside the 'frontend/' directory with your credentials.\n" +
    "See 'frontend/.env.example' for guidance."
  );
  app = initializeApp({
    apiKey: "placeholder-key-please-configure-env",
    authDomain: "placeholder-app.firebaseapp.com",
    projectId: "placeholder-app",
    appId: "1:000000000000:web:0000000000000000000000"
  });
  auth = getAuth(app);
} else {
  app = !getApps().length ? initializeApp(firebaseConfig) : getApp();
  auth = getAuth(app);
  
  // Safely initialize analytics (requires browser support)
  isSupported().then((yes) => {
    if (yes) {
      analytics = getAnalytics(app);
    }
  });
}

export { app, auth, analytics };


