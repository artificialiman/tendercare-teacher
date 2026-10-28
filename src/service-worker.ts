/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true" />
/// <reference lib="esnext" />
/// <reference lib="webworker" />

import { build, files, version } from '$service-worker';

// ============================================================================
// Makes the whole app open with no connection at all, at any address.
//
// Everything the app shows is compiled into its JavaScript (teacherData.ts)
// and everything a teacher types is saved on the device (localState.ts), so
// the only thing a network is ever needed for is fetching the app itself. This
// worker therefore stores the app itself, once, and never asks the network
// for it again:
//
//   * every built file (scripts, styles, fonts, crest) -- `build` + `files`
//   * the HTML shell. The app renders in the browser only (ssr = false) and
//     uses absolute asset paths (vite.config.ts), so the shell is the same
//     document at every address and one stored copy serves them all.
//
// Page loads are answered from the stored copy FIRST, with no network wait --
// on a weak connection that is also simply faster than asking the server.
//
// Updates: a new version downloads in the background into its own cache and
// then WAITS. It takes over only after every open tab of the old version has
// been closed, so a deploy can never swap files out from under a teacher in
// the middle of entering scores. (The one exception is the very first
// install, where there is nothing to disturb.) The old copy keeps working
// until then, and its shell and files are always from the same version.
// ============================================================================

const sw = self as unknown as ServiceWorkerGlobalScope;

const CACHE_NAME = `app-shell-${version}`;
const ASSETS = [...build, ...files];
const SHELL = '/';

sw.addEventListener('install', (event) => {
	event.waitUntil(
		(async () => {
			const cache = await caches.open(CACHE_NAME);
			await cache.addAll(ASSETS);
			// `reload` skips the browser's HTTP cache so the shell stored here is
			// the one that goes with this exact version's files.
			await cache.add(new Request(SHELL, { cache: 'reload' }));
			// First install only: nothing is running yet, so take over at once.
			// On an update, stay waiting (see the note above).
			if (!sw.registration.active) await sw.skipWaiting();
		})()
	);
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(
		(async () => {
			const keys = await caches.keys();
			await Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)));
			await sw.clients.claim();
		})()
	);
});

sw.addEventListener('fetch', (event) => {
	const { request } = event;
	if (request.method !== 'GET') return;

	const url = new URL(request.url);
	if (url.origin !== sw.location.origin) return;

	// A page load at any address: answer with the stored shell; the app's own
	// router then draws whatever that address is.
	if (request.mode === 'navigate') {
		event.respondWith(
			(async () => {
				const cache = await caches.open(CACHE_NAME);
				const shell = await cache.match(SHELL);
				if (shell) return shell;
				// Only reachable if the stored copy is somehow missing: try the network.
				try {
					return await fetch(request);
				} catch {
					return new Response(
						'<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
							'<title>Offline</title><body style="font-family:sans-serif;padding:2rem;max-width:32rem;margin:auto">' +
							'<h1>Not available offline yet</h1><p>Open this app once while connected so it can save itself to this device, then it will work without a connection.</p>',
						{ status: 503, headers: { 'content-type': 'text/html; charset=utf-8' } }
					);
				}
			})()
		);
		return;
	}

	// Built files and static files: stored copy first, network only if missing.
	if (ASSETS.includes(url.pathname)) {
		event.respondWith(
			caches.open(CACHE_NAME).then(async (cache) => {
				const cached = await cache.match(request);
				if (cached) return cached;
				const response = await fetch(request);
				if (response.ok) cache.put(request, response.clone());
				return response;
			})
		);
	}
});

// Lets the page ask a waiting update to take over now (used only if a person
// chooses to, never automatically).
sw.addEventListener('message', (event) => {
	if (event.data === 'SKIP_WAITING') sw.skipWaiting();
});
