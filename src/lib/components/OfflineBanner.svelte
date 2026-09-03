<script lang="ts">
	import { isOnline, listOutbox, flushOutbox } from '$lib/offline';
	import { scoreOutboxHandlers } from '$lib/scores';
	import { onMount } from 'svelte';

	let pendingCount = $state(0);
	let syncing = $state(false);
	let lastSyncNote = $state('');

	async function refreshPendingCount() {
		pendingCount = (await listOutbox()).length;
	}

	async function sync() {
		if (syncing) return;
		syncing = true;
		try {
			const { flushed, remaining } = await flushOutbox({ ...scoreOutboxHandlers });
			pendingCount = remaining;
			if (flushed > 0) {
				lastSyncNote = `Synced ${flushed} change${flushed === 1 ? '' : 's'}.`;
				setTimeout(() => (lastSyncNote = ''), 4000);
			}
		} finally {
			syncing = false;
		}
	}

	onMount(() => {
		refreshPendingCount();
		const unsubscribe = isOnline.subscribe((online) => {
			if (online) sync();
		});
		return unsubscribe;
	});
</script>

{#if !$isOnline}
	<div class="offline-banner offline">
		You're offline — showing the last saved copy. Changes you make will be saved locally and sync
		once you're back online.
	</div>
{:else if syncing}
	<div class="offline-banner syncing">Syncing…</div>
{:else if pendingCount > 0}
	<div class="offline-banner pending">
		{pendingCount} change{pendingCount === 1 ? '' : 's'} waiting to sync.
	</div>
{:else if lastSyncNote}
	<div class="offline-banner synced">{lastSyncNote}</div>
{/if}

<style>
	.offline-banner {
		position: sticky;
		top: 0;
		z-index: 100;
		text-align: center;
		font-size: var(--text-sm);
		padding: var(--space-2) var(--space-4);
	}
	.offline {
		background: var(--color-wine);
		color: var(--color-white);
	}
	.syncing,
	.pending {
		background: var(--color-purple-ghost);
		color: var(--color-purple-deep);
	}
	.synced {
		background: var(--color-cream);
		color: var(--color-purple-deep);
	}
</style>
