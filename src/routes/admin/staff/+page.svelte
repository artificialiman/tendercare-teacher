<script lang="ts">
	import { onMount } from 'svelte';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';

	type StaffRow = {
		id: string;
		full_name: string;
		staff_type: 'part_time' | 'full_time' | 'corps_member';
		is_class_teacher: boolean;
		subject: string | null;
		active: boolean;
	};

	let staff = $state<StaffRow[]>([]);
	let loading = $state(true);
	let saving = $state(false);
	let error = $state<string | null>(null);

	let newName = $state('');
	let newType = $state<StaffRow['staff_type']>('full_time');
	let newIsClassTeacher = $state(false);
	let newSubject = $state('');

	const typeLabels: Record<StaffRow['staff_type'], string> = {
		part_time: 'Part-time',
		full_time: 'Full-time',
		corps_member: 'Corps Member'
	};

	onMount(load);

	async function load() {
		loading = true;
		const { data, error: err } = await supabase
			.from('staff')
			.select('*')
			.eq('active', true)
			.order('full_name');
		if (err) error = err.message;
		staff = data ?? [];
		loading = false;
	}

	async function addStaff() {
		if (!newName.trim()) return;
		saving = true;
		error = null;
		const { error: err } = await supabase.from('staff').insert({
			full_name: newName.trim(),
			staff_type: newType,
			is_class_teacher: newIsClassTeacher,
			subject: newSubject.trim() || null
		});
		if (err) {
			error = err.message;
		} else {
			newName = '';
			newSubject = '';
			newIsClassTeacher = false;
			await load();
		}
		saving = false;
	}

	async function removeStaff(id: string) {
		saving = true;
		const { error: err } = await supabase.from('staff').update({ active: false }).eq('id', id);
		if (err) error = err.message;
		await load();
		saving = false;
	}
</script>

<svelte:head>
	<title>Staff &amp; Roles — Tendercare Admin</title>
</svelte:head>

<div class="staff-page">
	<Crest class="staff-page__watermark" />

	<header class="staff-page__header">
		<a href="/admin" class="staff-page__back">&larr; Admin</a>
		<h1>Staff &amp; Roles</h1>
		<p>Add, remove, and assign roles. Permission tiers between staff types are shared for now.</p>
	</header>

	{#if error}
		<p class="staff-page__error">{error}</p>
	{/if}

	<form class="staff-form" onsubmit={(e) => { e.preventDefault(); addStaff(); }}>
		<input type="text" placeholder="Full name" bind:value={newName} required />
		<select bind:value={newType}>
			<option value="full_time">Full-time</option>
			<option value="part_time">Part-time</option>
			<option value="corps_member">Corps Member</option>
		</select>
		<input type="text" placeholder="Subject (optional)" bind:value={newSubject} />
		<label class="staff-form__checkbox">
			<input type="checkbox" bind:checked={newIsClassTeacher} />
			Class teacher
		</label>
		<button type="submit" disabled={saving}>Add Staff</button>
	</form>

	{#if loading}
		<p class="staff-page__loading">Loading…</p>
	{:else if staff.length === 0}
		<p class="staff-page__empty">No staff on record yet.</p>
	{:else}
		<div class="staff-list">
			{#each staff as person (person.id)}
				<div class="staff-row">
					<div>
						<span class="staff-row__name">{person.full_name}</span>
						<span class="staff-row__meta">
							{typeLabels[person.staff_type]}{person.is_class_teacher ? ' · Class Teacher' : ''}{person.subject ? ` · ${person.subject}` : ''}
						</span>
					</div>
					<button class="staff-row__remove" onclick={() => removeStaff(person.id)} disabled={saving}>
						Remove
					</button>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.staff-page {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		max-width: 800px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
	}
	:global(.staff-page__watermark) {
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
	.staff-page__header,
	.staff-form,
	.staff-list,
	.staff-page__error,
	.staff-page__loading,
	.staff-page__empty {
		position: relative;
		z-index: 1;
	}
	.staff-page__back {
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-purple-deep);
		text-decoration: none;
		opacity: 0.7;
	}
	.staff-page__header h1 {
		font-family: var(--font-serif);
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		margin: var(--space-2) 0 0.15rem;
	}
	.staff-page__header p {
		opacity: 0.6;
		margin: 0 0 var(--space-6);
		font-size: var(--text-sm);
	}
	.staff-page__error {
		color: var(--color-wine);
		font-size: var(--text-sm);
		margin-bottom: var(--space-4);
	}
	.staff-form {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-3);
		align-items: center;
		background: var(--color-cream);
		border-radius: var(--radius-md);
		padding: var(--space-5);
		margin-bottom: var(--space-8);
	}
	.staff-form input[type='text'],
	.staff-form select {
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		font-family: var(--font-sans);
		font-size: var(--text-sm);
		background: var(--color-white);
	}
	.staff-form__checkbox {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--text-sm);
	}
	.staff-form button {
		background: var(--color-purple-deep);
		color: white;
		border: none;
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-5);
		font-size: var(--text-sm);
		font-weight: 600;
		cursor: pointer;
	}
	.staff-form button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.staff-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.staff-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		padding: var(--space-4) var(--space-5);
	}
	.staff-row__name {
		display: block;
		font-family: var(--font-serif);
		font-size: var(--text-md);
		color: var(--color-ink);
	}
	.staff-row__meta {
		display: block;
		font-size: var(--text-xs);
		opacity: 0.55;
		margin-top: 0.15rem;
	}
	.staff-row__remove {
		background: none;
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		padding: var(--space-1) var(--space-3);
		font-size: var(--text-xs);
		cursor: pointer;
		color: var(--color-wine);
	}
	.staff-row__remove:disabled {
		opacity: 0.5;
		cursor: default;
	}
</style>
