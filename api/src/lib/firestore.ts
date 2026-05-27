import { Firestore } from '@google-cloud/firestore';

let _db: Firestore | null = null;

export function getDb(): Firestore {
  if (!_db) _db = new Firestore();
  return _db;
}
