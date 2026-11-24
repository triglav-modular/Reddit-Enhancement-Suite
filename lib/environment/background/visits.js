/* @flow */

// Safari gives extensions no history API, so the Safari build keeps its own
// record of visited pages and links in the background's IndexedDB. It answers
// the same questions RES asks Chrome's history: "add this URL" and "has this
// URL been visited?".

const DB_NAME = 'res-visits';
const STORE = 'visits';
export const MAX_AGE = 365 * 24 * 60 * 60 * 1000; // a year

/**
 * The key a URL is recorded under. Reddit serves the same page on several
 * hosts and with tracking or sorting queries, so a Reddit URL is keyed by its
 * path alone. Other URLs lose only their fragment.
 */
export function normalizeVisitURL(url: string): ?string {
	let parsed;
	try {
		parsed = new URL(url);
	} catch (e) {
		return null;
	}
	if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return null;

	parsed.hash = '';
	if (parsed.hostname === 'reddit.com' || parsed.hostname.endsWith('.reddit.com')) {
		parsed.protocol = 'https:';
		parsed.hostname = 'www.reddit.com';
		parsed.port = '';
		parsed.search = '';
		if (!parsed.pathname.endsWith('/')) parsed.pathname += '/';
	}
	return parsed.href;
}

let dbPromise: ?Promise<IDBDatabase>;

function openDB(): Promise<IDBDatabase> {
	if (!dbPromise) {
		dbPromise = new Promise((resolve, reject) => {
			const request = indexedDB.open(DB_NAME, 1);
			request.onupgradeneeded = () => {
				const store = request.result.createObjectStore(STORE, { keyPath: 'url' });
				store.createIndex('time', 'time');
			};
			request.onsuccess = () => resolve(request.result);
			request.onerror = () => {
				dbPromise = null;
				reject(request.error);
			};
		});
	}
	return dbPromise;
}

async function withStore<T>(mode: 'readonly' | 'readwrite', fn: (store: IDBObjectStore) => ?IDBRequest): Promise<T> {
	const db = await openDB();
	return new Promise((resolve, reject) => {
		const transaction = db.transaction(STORE, mode);
		const request = fn(transaction.objectStore(STORE));
		transaction.oncomplete = () => resolve(request ? request.result as any : undefined as any);
		transaction.onerror = () => reject(transaction.error);
		transaction.onabort = () => reject(transaction.error);
	});
}

export async function addVisit(url: string, time: number = Date.now()): Promise<void> {
	const key = normalizeVisitURL(url);
	if (!key) return;
	await withStore<unknown>('readwrite', store => store.put({ url: key, time }));
}

export async function isVisited(url: string): Promise<boolean> {
	const key = normalizeVisitURL(url);
	if (!key) return false;
	return !!(await withStore<unknown>('readonly', store => store.get(key)));
}

/** Forgets visits older than `MAX_AGE`, as Safari's own history does after a year by default. */
export function prune(now: number = Date.now()): Promise<void> {
	return withStore<void>('readwrite', store => {
		const cursorRequest = store.index('time').openCursor(IDBKeyRange.upperBound(now - MAX_AGE));
		cursorRequest.onsuccess = () => {
			const cursor = cursorRequest.result;
			if (!cursor) return;
			cursor.delete();
			cursor.continue();
		};
		return null;
	});
}
