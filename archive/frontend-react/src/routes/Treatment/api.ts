import { collection, doc, getDocs, setDoc, updateDoc } from 'firebase/firestore';
import { db } from '../../lib/firebaseClient';
import type { GetResponse, Reading, Session } from './schemas';

export class ApiError extends Error {
  constructor(public code: string, message?: string) {
    super(message ?? code);
    this.name = 'ApiError';
  }
}

function wrapError(e: unknown): never {
  const msg = e instanceof Error ? e.message : String(e);
  const code = msg.toLowerCase().includes('permission') ? 'unauthorized' : 'network_error';
  throw new ApiError(code, msg);
}

export async function saveSession(session: Session): Promise<void> {
  try {
    await setDoc(doc(db, 'treatment_sessions', session.session_id), session);
  } catch (e) { wrapError(e); }
}

export async function saveReading(reading: Reading): Promise<void> {
  try {
    await setDoc(doc(db, 'treatment_readings', reading.reading_id), reading);
  } catch (e) { wrapError(e); }
}

export async function updateSession(
  patch: Partial<Session> & { session_id: string },
): Promise<void> {
  const { session_id, ...rest } = patch;
  try {
    await updateDoc(doc(db, 'treatment_sessions', session_id), rest);
  } catch (e) { wrapError(e); }
}

export async function getAll(): Promise<GetResponse> {
  try {
    const [sessSnap, readSnap] = await Promise.all([
      getDocs(collection(db, 'treatment_sessions')),
      getDocs(collection(db, 'treatment_readings')),
    ]);
    return {
      ok: true,
      sessions: sessSnap.docs.map(d => d.data() as Session),
      readings: readSnap.docs.map(d => d.data() as Reading),
    };
  } catch (e) { wrapError(e); }
}
