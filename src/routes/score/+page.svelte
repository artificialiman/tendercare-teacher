<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import { getActiveStaffId, listMyAssignments, type Assignment } from '$lib/teacherIdentity';
	import Crest from '$lib/components/Crest.svelte';

	let checkingSession = $state(true);
	let loading = $state(true);
	let error = $state('');

	let assignments = $state<Assignment[]>([]);
	let selectedSubjectId = $state('');
	let selectedClassId = $state('');

	onMount(async () => {
		const {
			data: { session }
		} = await supabase.auth.getSession();
		if (!session) {
			goto('/login');
			return;
		}
		const staffId = getActiveStaffId();
		if (!staffId) {
			goto('/');
			return;
		}
		checkingSession = false;
		try {
			assignments = await listMyAssignments(staffId);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load your assignments';
		} finally {
			loading = false;
		}
	});

	// Only the subjects/classes this teacher is actually assigned to.
	const subjects = $derived(
		[...new Map(assignments.map((a) => [a.subject_id, a.subject_name])).entries()].map(
			([id, name]) => ({ id, name })
		)
	);
	const classesForSubject = $derived(
		assignments
			.filter((a) => a.subject_id === selectedSubjectId)
			.map((a) => ({ id: a.class_id, label: a.class_label }))
	);

	function handleSubjectChange() {
		selectedClassId = '';
	}

	function openSheet() {
		if (!selectedSubjectId || !selectedClassId) return;
		goto(`/score/sheet?subject=${selectedSubjectId}&class=${encodeURIComponent(selectedClassId)}`);
	}

	const selectedSubjectName = $derived(subjects.find((s) => s.id === selectedSubjectId)?.name ?? '');
</script>

<svelte:head>
	<title>Score Entry — Tendercare Teacher Dashboard</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else}
<div class="score-picker-page">
	<Crest class="picker-watermark" />

	<header class="page-header">
		<div>
			<h1>Score Entry</h1>
			<p>Choose a subject, then a class, to open its broadsheet.</p>
		</div>
		<a class="back-button" href="/">&larr; Dashboard</a>
	</header>

	{#if error}
		<div class="page-error" role="alert">{error}</div>
	{/if}

	<div class="form-card">
		<h2>Assignment</h2>
		{#if loading}
			<p class="loading-note">Loading subjects…</p>
		{:else}
			<div class="select-row">
				<div class="select-wrapper">
					<label for="subjectSelect">Subject</label>
					<select
						id="subjectSelect"
						class="styled-select"
						bind:value={selectedSubjectId}
						onchange={handleSubjectChange}
					>
						<option value="">Select a subject</option>
						{#each subjects as s (s.id)}
							<option value={s.id}>{s.name}</option>
						{/each}
					</select>
				</div>
				<div class="select-wrapper">
					<label for="classSelect">Class</label>
					<select
						id="classSelect"
						class="styled-select"
						bind:value={selectedClassId}
						disabled={!selectedSubjectId}
					>
						<option value="">
							Select a class
						</option>
						{#each classesForSubject as c (c.id)}
							<option value={c.id}>{c.label}</option>
						{/each}
					</select>
				</div>
				<button class="btn-primary" disabled={!selectedClassId} onclick={openSheet}>
					Open sheet
				</button>
			</div>
			{#if !loading && subjects.length === 0 && !error}
				<p class="empty-note">No subject-class assignments on file for you yet — ask admin to assign them.</p>
			{:else if selectedSubjectId && classesForSubject.length === 0}
				<p class="empty-note">No classes assigned to you for {selectedSubjectName}.</p>
			{/if}
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
	.score-picker-page {
		position: relative;
		overflow: hidden;
		max-width: 900px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
		min-height: 100dvh;
	}
	:global(.picker-watermark) {
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
	.select-row {
		display: flex;
		gap: var(--space-3);
		flex-wrap: wrap;
		align-items: flex-end;
	}
	.select-wrapper {
		flex: 1;
		min-width: 200px;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.select-wrapper label {
		font-size: var(--text-xs);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-ash-dark);
	}
	.styled-select {
		width: 100%;
		padding: 0.75rem 0.9rem;
		font-size: var(--text-sm);
		background: var(--color-cream);
		border: 1.5px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		color: var(--color-ink);
		cursor: pointer;
	}
	.styled-select:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.btn-primary {
		font-size: var(--text-sm);
		font-weight: 600;
		letter-spacing: var(--tracking-wide);
		background: var(--color-purple);
		color: var(--color-cream);
		padding: 0.75rem 1.4rem;
		border-radius: var(--radius-md);
		white-space: nowrap;
		border: none;
		cursor: pointer;
	}
	.btn-primary:hover:not(:disabled) {
		background: var(--color-purple-deep);
	}
	.btn-primary:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.empty-note {
		margin: var(--space-4) 0 0;
		font-size: var(--text-sm);
		color: var(--color-ash-dark);
	}
</style>
