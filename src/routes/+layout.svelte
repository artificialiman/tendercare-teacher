<script lang="ts">
	import '$lib/styles/tendercare.css';
	import favicon from '$lib/assets/favicon.svg';
	import OfflineBanner from '$lib/components/OfflineBanner.svelte';
	import { onMount } from 'svelte';

	let { children } = $props();

	onMount(() => {
		if ('serviceWorker' in navigator) {
			navigator.serviceWorker.register('/service-worker.js').catch(() => {
				// Registration failing (e.g. unsupported browser) shouldn't
				// break the app -- it just means no offline app-shell caching,
				// same as before this existed.
			});
		}
	});
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<link rel="manifest" href="/manifest.json" />
	<meta name="theme-color" content="#3A1A5C" />
</svelte:head>

<OfflineBanner />
{@render children()}
