import { getApps, initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  apiKey: 'REDACTED_FIREBASE_WEB_API_KEY',
  authDomain: 'homehd-personal.firebaseapp.com',
  projectId: 'homehd-personal',
  storageBucket: 'homehd-personal.firebasestorage.app',
  messagingSenderId: '266908773576',
  appId: '1:266908773576:web:2ac0026f747cf0994c09fd',
};

const app = getApps().length ? getApps()[0] : initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const firebaseAuth = getAuth(app);
