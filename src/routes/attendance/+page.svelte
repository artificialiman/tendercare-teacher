<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';
	import ConfirmButton from '$lib/components/ConfirmButton.svelte';
	import { runPromotion, checkPromotionAlreadyRun, type PromotionResult } from '$lib/roster';

	let checkingSession = $state(true);
	let loading = $state(true);
	let error = $state('');
	let classes = $state<{ id: string; label: string }[]>([]);

	let running = $state(false);
	let result = $state<PromotionResult | null>(null);
	let promotionError = $state('');
	let promotionAlreadyRun = $state(false);

	onMount(async () => {
		const {
			data: { session }
		} = await supabase.auth.getSession();
		if (!session) {
			goto('/login');
			return;
		}
		checkingSession = false;
		try {
			const { data, error: err } = await supabase.from('classes').select('id, label').order('sort_order');
			if (err) throw err;
			classes = data ?? [];
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load classes';
		} finally {
			loading = false;
		}
		try {
			promotionAlreadyRun = await checkPromotionAlreadyRun();
		} catch {
			// If this check itself fails, leave the button live -- the
			// database-side guard in run_promotion() still refuses a
			// second run regardless of what the UI shows.
		}
	});

	async function handleRunPromotion() {
		running = true;
		promotionError = '';
		result = null;
		try {
			result = await runPromotion();
			promotionAlreadyRun = true;
			const { data } = await supabase.from('classes').select('id, label').order('sort_order');
			classes = data ?? [];
		} catch (e) {
			const message = e instanceof Error ? e.message : 'Promotion failed';
			if (message.toLowerCase().includes('already been run')) {
				promotionAlreadyRun = true;
			} else {
				promotionError = message;
			}
		} finally {
			running = false;
		}
	}
</script>

<svelte:head>
	<title>Attendance & Bio Edit — Tendercare Teacher Dashboard</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else}
<div class="attendance-page">
	<Crest class="attendance-watermark" />

	<header class="page-header">
		<div>
			<h1>Attendance & Bio Edit</h1>
			<p>
				Choose a class to add or remove students, link a portrait, or review a repeat/pardon
				status.
			</p>
		</div>
		<a class="back-button" href="/">&larr; Dashboard</a>
	</header>

	{#if error}
		<div class="page-error" role="alert">{error}</div>
	{/if}

	<div class="form-card promotion-card">
		<h2>September 1st Promotion</h2>
		<p class="promotion-note">
			Advances every active, non-repeating student one level in their same arm/department,
			graduates SS3, and moves JSS3 into an SS1 Unassigned holding class for department
			assignment on the roster page. Whole roster, one shot — the three confirm steps below are
			deliberate.
		</p>
		{#if promotionError}
			<div class="page-error" role="alert">{promotionError}</div>
		{/if}
		{#if result}
			<div class="promotion-result">
				Promoted {result.promoted_count}, graduated {result.graduated_count}, {result.pending_assignment_count}
				now pending department assignment.
			</div>
		{/if}
		{#if promotionAlreadyRun}
			<div class="promotion-done">
				Already run for this cycle — the next run unlocks after next year's September 1st rollover.
			</div>
		{:else}
			<ConfirmButton
				label="Run September 1st Promotion"
				confirmLabel="This moves the ENTIRE roster. Confirm?"
				finalLabel="Yes — run it now"
				variant="danger"
				disabled={running}
				onconfirm={handleRunPromotion}
			/>
		{/if}
	</div>

	<div class="form-card">
		<h2>Choose a class</h2>
		{#if loading}
			<p class="loading-note">Loading classes…</p>
		{:else}
			<div class="class-tabs">
				{#each classes as c (c.id)}
					<a class="class-tab" href="/roster?class={encodeURIComponent(c.id)}">{c.label}</a>
				{/each}
			</div>
		{/if}
	</div>
</div>
{/if}

<style>
	.session-check {
		text-align: center;
		padding: 4rem 1rem;
		opacity: 0.6;
		font-family: var(--font-sans);
	}
	.attendance-page {
		position: relative;
		overflow: hidden;
		max-width: 900px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
		min-height: 100dvh;
	}
	:global(.attendance-watermark) {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		width: min(60vw, 560px);
		height: auto;
		color: var(--color-purple-deep);
		opacity: 0.035;
		pointer-events: none;
		z-index: 0;
	}
	.page-header,
	.page-error,
	.form-card {
		position: relative;
		z-index: 1;
	}
	.page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-4);
		margin-bottom: var(--space-6);
		flex-wrap: wrap;
	}
	.page-header h1 {
		font-family: var(--font-serif);
		font-weight: 400;
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		margin: 0 0 var(--space-1);
	}
	.page-header p {
		font-size: var(--text-sm);
		color: var(--color-ash-dark);
		max-width: 60ch;
		margin: 0;
	}
	.back-button {
		padding: 0.6rem 1.1rem;
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-sm);
		color: var(--color-ink);
		font-weight: 600;
		font-size: 0.85rem;
		text-decoration: none;
		flex-shrink: 0;
	}
	.back-button:hover {
		background: var(--color-cream);
	}
	.page-error {
		background: #fdecea;
		border: 1px solid #f5c6c0;
		color: var(--color-wine);
		padding: var(--space-3) var(--space-4);
		border-radius: var(--radius-md);
		margin-bottom: var(--space-5);
		font-size: var(--text-sm);
	}
	.form-card {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		padding: var(--space-6);
		box-shadow: var(--shadow-sm);
	}
	.form-card h2 {
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: var(--tracking-wide);
		color: var(--color-purple);
		margin: 0 0 var(--space-4);
	}
	.promotion-card {
		border-color: var(--color-wine);
		margin-bottom: var(--space-6);
	}
	.promotion-note {
		font-size: var(--text-sm);
		opacity: 0.65;
		max-width: 65ch;
		margin: 0 0 var(--space-4);
	}
	.promotion-result {
		font-size: var(--text-sm);
		background: var(--color-purple-ghost);
		color: var(--color-purple-deep);
		padding: var(--space-3) var(--space-4);
		border-radius: var(--radius-md);
		margin-bottom: var(--space-4);
	}
	.promotion-done {
		font-size: var(--text-sm);
		opacity: 0.65;
		font-style: italic;
	}
	.loading-note {
		opacity: 0.6;
		font-size: var(--text-sm);
	}
	.class-tabs {
		display: flex;
		gap: var(--space-2);
		flex-wrap: wrap;
	}
	.class-tab {
		font-size: var(--text-sm);
		font-weight: 600;
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		color: var(--color-ash-dark);
		text-decoration: none;
	}
	.class-tab:hover {
		border-color: var(--color-purple-light);
		color: var(--color-purple-deep);
	}
</style>
