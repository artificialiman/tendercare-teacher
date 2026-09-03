/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true" />
/// <reference lib="esnext" />
/// <reference lib="webworker" />

import { build, files, version } from '$service-worker';

// ============================================================================
// App-shell precaching only -- the actual data (roster/classes/scores) is
// cached separately in IndexedDB (offline.ts), not intercepted here. This
// worker's one job is making sure the app itself (JS/CSS/fonts/crest) loads
// with zero connectivity, per doctrine 2.1/10.5 (a page that doesn't need a
// live round-trip should never require one just to load its own shell).
// ============================================================================

const sw = self as unknown as ServiceWorkerGlobalScope;

const CACHE_NAME = `app-shell-${version}`;
const ASSETS = [...build, ...files];

sw.addEventListener('install', (event) => {
	event.waitUntil(
		caches
			.open(CACHE_NAME)
			.then((cache) => cache.addAll(ASSETS))
			.then(() => sw.skipWaiting())
	);
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
			.then(() => sw.clients.claim())
	);
});

// Cache-first for the precached shell assets; everything else (Supabase
// calls, anything not in ASSETS) passes straight through to the network
// untouched -- offline.ts's IndexedDB cache handles data-level fallback,
// this worker never intercepts or fabricates a data response.
sw.addEventListener('fetch', (event) => {
	if (event.request.method !== 'GET') return;

	const url = new URL(event.request.url);
	const isShellAsset = ASSETS.includes(url.pathname);
	if (!isShellAsset) return;

	event.respondWith(
		caches.open(CACHE_NAME).then(async (cache) => {
			const cached = await cache.match(event.request);
			if (cached) return cached;
			const response = await fetch(event.request);
			if (response.ok) cache.put(event.request, response.clone());
			return response;
		})
	);
});
