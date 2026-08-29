<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';

	let checkingSession = $state(true);
	let loading = $state(true);
	let error = $state('');
	let classes = $state<{ id: string; label: string }[]>([]);

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
	});
</script>

<svelte:head>
	<title>Attendance & Bio Edit — Tendercare Teacher Dashboard</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else}
<div class="attendance-page">
	<Crest class="attendance-watermark" aria-hidden="true" />

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
