<script lang="ts">
	import { onMount } from 'svelte';
	import { saveStatus, requestPersistentStorage } from '$lib/localState';
	import {
		sendScoresFile,
		saveScoresFile,
		restoreScoresFile,
		lastBackupAt,
		changesSinceBackup
	} from '$lib/handIn';

	// Everything on this card is about the one phone in the teacher's hand:
	// can the app open with no connection, are the scores safe here, and have
	// they been handed in. Nothing is fetched.

	let offline = $state<'ready' | 'preparing' | 'unsupported'>('preparing');
	let updateWaiting = $state(false);
	let busy = $state(false);
	let message = $state('');
	let messageBad = $state(false);
	let fileInput: HTMLInputElement | undefined = $state();

	// Re-read the backup bookkeeping whenever a save happens or an action finishes.
	let tick = $state(0);
	const lastBackup = $derived.by(() => {
		void tick;
		return lastBackupAt();
	});
	const unsent = $derived.by(() => {
		void tick;
		void $saveStatus.lastSavedAt;
		return changesSinceBackup();
	});
	const cells = $derived($saveStatus.scoreCells);

	const hoursSinceBackup = $derived(lastBackup ? (Date.now() - new Date(lastBackup).getTime()) / 3_600_000 : Infinity);
	const needsBackup = $derived(unsent > 0 && hoursSinceBackup > 24);

	const when = (iso: string) =>
		new Date(iso).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

	onMount(async () => {
		void requestPersistentStorage();
		if (!('serviceWorker' in navigator)) {
			offline = 'unsupported';
			return;
		}
		offline = navigator.serviceWorker.controller ? 'ready' : 'preparing';
		navigator.serviceWorker.addEventListener('controllerchange', () => (offline = 'ready'));
		const reg = await navigator.serviceWorker.getRegistration();
		if (reg) {
			updateWaiting = !!reg.waiting;
			reg.addEventListener('updatefound', () => {
				reg.installing?.addEventListener('statechange', () => {
					if (reg.waiting) updateWaiting = true;
				});
			});
		}
	});

	async function run(action: () => Promise<void>) {
		busy = true;
		message = '';
		messageBad = false;
		try {
			await action();
		} catch (e) {
			message = e instanceof Error ? e.message : 'Something went wrong.';
			messageBad = true;
		} finally {
			busy = false;
			tick++;
		}
	}

	const send = () =>
		run(async () => {
			const how = await sendScoresFile();
			if (how === 'shared') message = 'Scores file sent. Keep this phone’s scores until the school confirms it arrived.';
			else if (how === 'downloaded') message = 'Scores file saved to this phone (check Downloads). Send it to the school from there.';
		});

	const save = () =>
		run(async () => {
			await saveScoresFile();
			message = 'Scores file saved to this phone (check Downloads).';
		});

	async function onPick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		await run(async () => {
			const r = await restoreScoresFile(file);
			if (!r.ok) {
				message = r.problem ?? 'The file could not be restored.';
				messageBad = true;
				return;
			}
			message =
				`Restored ${r.applied ?? 0} score${r.applied === 1 ? '' : 's'}` +
				((r.keptNewer ?? 0) > 0 ? `; kept ${r.keptNewer} newer already on this phone` : '') +
				((r.invalid ?? 0) > 0 ? `; skipped ${r.invalid} unreadable` : '') +
				'.';
		});
	}
</script>

<section class="device">
	<p class="device-label">On this device</p>
	<div class="device-card">
		<div class="device-row">
			<span class="device-key">Offline</span>
			<span class="device-val">
				{#if offline === 'ready'}
					<span class="ok">✓ Ready</span> — opens and works with no connection.
				{:else if offline === 'preparing'}
					Saving the app to this phone… keep it open once while connected.
				{:else}
					<span class="warn">This browser can’t keep the app offline.</span> Scores still save on the phone.
				{/if}
			</span>
		</div>

		<div class="device-row">
			<span class="device-key">Scores</span>
			<span class="device-val">
				{cells} entr{cells === 1 ? 'y' : 'ies'} typed on this phone{#if $saveStatus.lastSavedAt}, last saved {when($saveStatus.lastSavedAt)}{/if}.
				{#if !$saveStatus.ok}
					<span class="bad">⚠ The last save failed: {$saveStatus.error}.</span>
				{:else if $saveStatus.persistent === false}
					<span class="warn">The phone may clear the app’s data if it runs low on space — send scores often.</span>
				{/if}
			</span>
		</div>

		<div class="device-row">
			<span class="device-key">Handed in</span>
			<span class="device-val">
				{#if cells === 0}
					Nothing to send yet.
				{:else if !lastBackup}
					<span class:warn={needsBackup}>Not sent anywhere yet — {unsent} change{unsent === 1 ? '' : 's'} exist only on this phone.</span>
				{:else}
					Last sent {when(lastBackup)}{#if unsent > 0}
						— <span class:warn={needsBackup}>{unsent} new change{unsent === 1 ? '' : 's'} since</span>{:else}, nothing new since{/if}.
				{/if}
			</span>
		</div>

		<div class="device-actions">
			<button class="btn-primary" onclick={send} disabled={busy || cells === 0}>Send scores file</button>
			<button class="btn-quiet" onclick={save} disabled={busy || cells === 0}>Save a copy</button>
			<button class="btn-quiet" onclick={() => fileInput?.click()} disabled={busy}>Restore from a file</button>
			<input bind:this={fileInput} type="file" accept=".json,application/json" hidden onchange={onPick} />
		</div>

		{#if message}
			<p class="device-msg" class:bad={messageBad} role="status">{message}</p>
		{/if}
		{#if updateWaiting}
			<p class="device-msg">A new version of the app is ready. It starts the next time you close the app and open it again — your scores are not affected.</p>
		{/if}
	</div>
</section>

<style>
	.device {
		position: relative;
		z-index: 1;
		max-width: 900px;
		margin: 0 auto;
		padding: 0 var(--space-5) var(--space-12);
	}
	.device-label {
		font-size: var(--text-xs);
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-purple);
		margin: var(--space-6) 0 var(--space-3);
	}
	.device-card {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		font-family: var(--font-sans);
	}
	.device-row {
		display: flex;
		gap: var(--space-4);
		padding: var(--space-2) 0;
		font-size: var(--text-sm);
		border-bottom: 1px solid var(--color-cream);
	}
	.device-row:last-of-type {
		border-bottom: 0;
	}
	.device-key {
		flex: 0 0 5.5rem;
		font-weight: 600;
		color: var(--color-purple-deep);
	}
	.device-val {
		flex: 1;
		color: var(--color-ash-dark);
		line-height: 1.45;
	}
	.ok {
		color: var(--color-purple-deep);
		font-weight: 600;
	}
	.warn {
		color: #8a5a00;
		font-weight: 600;
	}
	.bad {
		color: var(--color-wine);
		font-weight: 600;
	}
	.device-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-3);
	}
	.btn-primary,
	.btn-quiet {
		font-size: var(--text-xs);
		font-weight: 600;
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		cursor: pointer;
	}
	.btn-primary {
		background: var(--color-purple);
		color: var(--color-white);
		border: 1px solid var(--color-purple);
	}
	.btn-quiet {
		background: var(--color-white);
		color: var(--color-purple-deep);
		border: 1px solid var(--color-purple-light);
	}
	button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.device-msg {
		margin: var(--space-3) 0 0;
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
	}
	.device-msg.bad {
		color: var(--color-wine);
		font-weight: 600;
	}
</style>
