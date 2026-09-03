import { openDB, type IDBPDatabase } from 'idb';
import { writable } from 'svelte/store';

// ============================================================================
// Local IndexedDB cache + write outbox, per the offline plan: cache reads
// so the app is usable with no connection (doctrine §2.1/§2.5 -- a critical
// path shouldn't depend on a live call if a last-known-good copy exists),
// and queue writes so nothing typed offline is lost, replayed idempotently
// on reconnect (§2.6/§13). Auth itself is explicitly out of scope here --
// that's being built separately.
// ============================================================================

const DB_NAME = 'tendercare-teacher-offline';
const DB_VERSION = 1;

interface CacheEntry<T> {
	key: string;
	data: T;
	cachedAt: string;
}

export interface OutboxEntry {
	id?: number;
	kind: string;
	payload: unknown;
	createdAt: string;
}

let dbPromise: Promise<IDBPDatabase> | null = null;

function getDb(): Promise<IDBPDatabase> {
	if (!dbPromise) {
		dbPromise = openDB(DB_NAME, DB_VERSION, {
			upgrade(db) {
				if (!db.objectStoreNames.contains('cache')) {
					db.createObjectStore('cache', { keyPath: 'key' });
				}
				if (!db.objectStoreNames.contains('outbox')) {
					db.createObjectStore('outbox', { keyPath: 'id', autoIncrement: true });
				}
			}
		});
	}
	return dbPromise;
}

async function cacheRead<T>(key: string): Promise<CacheEntry<T> | undefined> {
	const db = await getDb();
	return (await db.get('cache', key)) as CacheEntry<T> | undefined;
}

async function cacheWrite<T>(key: string, data: T): Promise<void> {
	const db = await getDb();
	await db.put('cache', { key, data, cachedAt: new Date().toISOString() });
}

export interface ReadThroughResult<T> {
	data: T;
	fromCache: boolean;
	cachedAt: string | null;
}

/**
 * Try a live call first, with a timeout; on success, cache the result
 * under `key` and return it as fresh. On failure or timeout, fall back to
 * whatever's cached under that key, marked stale. Throws only if there's
 * neither a live result nor anything cached yet -- genuinely nothing to
 * show, not something a cache can paper over.
 */
export async function readThroughCache<T>(
	key: string,
	fetchLive: () => Promise<T>,
	timeoutMs = 6000
): Promise<ReadThroughResult<T>> {
	try {
		const data = await Promise.race([
			fetchLive(),
			new Promise<never>((_, reject) =>
				setTimeout(() => reject(new Error('offline-timeout')), timeoutMs)
			)
		]);
		await cacheWrite(key, data);
		return { data, fromCache: false, cachedAt: new Date().toISOString() };
	} catch (err) {
		const cached = await cacheRead<T>(key);
		if (cached) {
			return { data: cached.data, fromCache: true, cachedAt: cached.cachedAt };
		}
		throw err;
	}
}

// ---------------------------------------------------------------------------
// Outbox: writes made while offline, queued and replayed on reconnect.
// Every `kind` registered here MUST be idempotent -- replaying an entry
// that already landed (e.g. a flush that got half-way through before
// disconnecting again) must produce the same end state, never a
// duplicate. This is why addStudent() is deliberately NOT queueable here:
// it allocates a new sequential ID per call (create_student(), atomic but
// not idempotent), so two offline attempts would mint two different IDs
// for one intended student. Adding a student requires a live connection;
// everything else that's a plain update-by-ID, or upserted on a natural
// key (student_id/subject_id/term_id for scores), is safe to queue.
// ---------------------------------------------------------------------------

export async function enqueueWrite(kind: string, payload: unknown): Promise<void> {
	const db = await getDb();
	await db.add('outbox', { kind, payload, createdAt: new Date().toISOString() });
}

export async function listOutbox(): Promise<OutboxEntry[]> {
	const db = await getDb();
	return (await db.getAll('outbox')) as OutboxEntry[];
}

export interface FlushResult {
	flushed: number;
	remaining: number;
}

/**
 * Replay every queued write, oldest first, via the handler registered for
 * its kind. An entry is only removed after its handler resolves, so a
 * connection dropping mid-flush leaves the remainder queued for next
 * time rather than losing them. Stops at the first failure rather than
 * burning through the rest of the queue one-by-one if we've just gone
 * offline again mid-flush.
 */
export async function flushOutbox(
	handlers: Record<string, (payload: any) => Promise<void>>
): Promise<FlushResult> {
	const db = await getDb();
	const entries = (await db.getAll('outbox')) as OutboxEntry[];
	let flushed = 0;
	for (const entry of entries) {
		const handler = handlers[entry.kind];
		if (!handler) continue; // unknown kind -- leave queued, don't drop silently
		try {
			await handler(entry.payload);
			await db.delete('outbox', entry.id!);
			flushed++;
		} catch {
			break;
		}
	}
	const remaining = ((await db.getAll('outbox')) as OutboxEntry[]).length;
	return { flushed, remaining };
}

// ---------------------------------------------------------------------------
// Online/offline reactive state, for the banner and for gating whether a
// write attempts live first or goes straight to the outbox.
// ---------------------------------------------------------------------------

export const isOnline = writable(typeof navigator !== 'undefined' ? navigator.onLine : true);

if (typeof window !== 'undefined') {
	window.addEventListener('online', () => isOnline.set(true));
	window.addEventListener('offline', () => isOnline.set(false));
}
