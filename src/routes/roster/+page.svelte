<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		listRoster,
		addStudent,
		removeStudent,
		restoreStudent,
		permanentlyEraseStudent,
		getCurrentTermId,
		listRemarksForTerm,
		assignRepeat,
		pardonRepeat,
		setPortraitUrl,
		type Student,
		type Remark
	} from '$lib/roster';
	import { supabase } from '$lib/supabase';

	let students = $state<Student[]>([]);
	let classes = $state<{ id: string; label: string }[]>([]);
	let loading = $state(true);
	let error = $state('');
	let checkingSession = $state(true);

	let newName = $state('');
	let newClassId = $state('');
	let adding = $state(false);

	let showInactive = $state(false);
	let confirmingEraseId = $state<string | null>(null);

	// Remarks -- editing a student's teacher/principal comment for the
	// current term. RLS on the remarks table (staff role only) is the
	// real gate; this page's session check above is just the UI shell.
	let currentTermId = $state<string | null>(null);
	let remarksByStudent = $state<Map<string, Remark>>(new Map());
	let editingPortraitId = $state<string | null>(null);
	let editPortraitUrl = $state('');
	let savingPortrait = $state(false);

	async function load() {
		loading = true;
		error = '';
		try {
			const [{ data: classData, error: classErr }, studentData] = await Promise.all([
				supabase.from('classes').select('id, label').order('sort_order'),
				listRoster()
			]);
			if (classErr) throw classErr;
			classes = classData ?? [];
			students = studentData;
			if (!newClassId && classes.length) newClassId = classes[0].id;

			currentTermId = await getCurrentTermId();
			if (currentTermId) {
				remarksByStudent = await listRemarksForTerm(
					students.map((s) => s.id),
					currentTermId
				);
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load roster';
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		// This only guards the UI shell — the real gate is RLS (see
		// 0002_rls_policies.sql), which rejects writes without a valid
		// 'staff' JWT claim regardless of what this page does. Someone
		// bypassing this check client-side still can't write to
		// `students`; they'd just see error toasts instead of a login
		// screen, which is why this redirect exists at all.
		const {
			data: { session }
		} = await supabase.auth.getSession();
		if (!session) {
			goto('/login');
			return;
		}
		checkingSession = false;
		await load();
	});

	async function handleAdd() {
		if (!newName.trim() || !newClassId) return;
		adding = true;
		error = '';
		try {
			await addStudent({ full_name: newName.trim(), class_id: newClassId });
			newName = '';
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to add student';
		} finally {
			adding = false;
		}
	}

	async function handleRemove(id: string) {
		error = '';
		try {
			await removeStudent(id);
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to remove student';
		}
	}

	async function handleRestore(id: string) {
		error = '';
		try {
			await restoreStudent(id);
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to restore student';
		}
	}

	async function handlePermanentErase(id: string) {
		error = '';
		try {
			await permanentlyEraseStudent(id);
			confirmingEraseId = null;
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to erase student';
		}
	}

	async function handleToggleRepeat(s: Student) {
		error = '';
		try {
			if (s.repeating) {
				await pardonRepeat(s.id);
			} else {
				await assignRepeat(s.id);
			}
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to update repeat status';
		}
	}

	function openPortraitEditor(s: Student) {
		editPortraitUrl = s.portrait_url ?? '';
		editingPortraitId = s.id;
	}

	function closePortraitEditor() {
		editingPortraitId = null;
	}

	async function handleSavePortrait() {
		if (!editingPortraitId) return;
		savingPortrait = true;
		error = '';
		try {
			await setPortraitUrl(editingPortraitId, editPortraitUrl);
			await load();
			editingPortraitId = null;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save portrait link';
		} finally {
			savingPortrait = false;
		}
	}

	const visibleStudents = $derived(students.filter((s) => showInactive || s.active));
	const activeCount = $derived(students.filter((s) => s.active).length);
</script>

<svelte:head>
	<title>Roster — Tendercare Teacher Dashboard</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else}
<div class="roster-page">
	<header class="roster-header">
		<h1>Student Roster</h1>
		<p class="roster-subtitle">
			{activeCount} active students. Changes here take effect immediately across the
			result/transcript portal, student directory, and public site — there's nothing else to
			update.
		</p>
	</header>

	{#if error}
		<div class="roster-error" role="alert">{error}</div>
	{/if}

	<section class="add-student">
		<h2>Add a student</h2>
		<form
			onsubmit={(e) => {
				e.preventDefault();
				handleAdd();
			}}
		>
			<input type="text" placeholder="Full name" bind:value={newName} required />
			<select bind:value={newClassId} required>
				{#each classes as c (c.id)}
					<option value={c.id}>{c.label}</option>
				{/each}
			</select>
			<button type="submit" disabled={adding}>{adding ? 'Adding…' : 'Add student'}</button>
		</form>
	</section>

	<section class="roster-list">
		<div class="roster-list-header">
			<h2>Roster</h2>
			<label class="show-inactive-toggle">
				<input type="checkbox" bind:checked={showInactive} />
				Show removed students
			</label>
		</div>

		{#if loading}
			<p>Loading…</p>
		{:else}
			<table>
				<thead>
					<tr>
						<th>ID</th>
						<th>Name</th>
						<th>Class</th>
						<th>Status</th>
						<th>Remark</th>
						<th></th>
					</tr>
				</thead>
				<tbody>
					{#each visibleStudents as s (s.id)}
						<tr class:inactive-row={!s.active}>
							<td>{s.id}</td>
							<td class="name-cell">
								{#if s.portrait_url}
									<img class="portrait-thumb" src={s.portrait_url} alt="" loading="lazy" />
								{/if}
								{s.full_name}
								{#if s.repeating}
									<span class="repeat-badge" title="Assigned to repeat this class">Repeating</span>
								{/if}
							</td>
							<td>{s.class_id}</td>
							<td>{s.active ? 'Active' : 'Removed'}</td>
							<td>
								{#if remarksByStudent.has(s.id)}
									<span class="remark-badge" title="Auto-assigned from this student's average once CA/Exam/Total are complete">
										{remarksByStudent.get(s.id)?.teacher_remark}
									</span>
								{:else}
									<span class="remark-pending" title="No remark yet -- scores aren't all complete for this term">—</span>
								{/if}
							</td>
							<td class="actions-cell">
								{#if s.active}
									<button class="btn-portrait" onclick={() => openPortraitEditor(s)}>
										{s.portrait_url ? 'Edit portrait' : 'Add portrait'}
									</button>
									<button class="btn-repeat" onclick={() => handleToggleRepeat(s)}>
										{s.repeating ? 'Pardon repeat' : 'Assign repeat'}
									</button>
									<button class="btn-remove" onclick={() => handleRemove(s.id)}>Remove</button>
								{:else}
									<button class="btn-restore" onclick={() => handleRestore(s.id)}>Restore</button>
									{#if confirmingEraseId === s.id}
										<span class="erase-confirm">
											Permanently erase — this also deletes their scores, remarks, and portal
											access. Cannot be undone.
											<button class="btn-erase-confirm" onclick={() => handlePermanentErase(s.id)}
												>Confirm erase</button
											>
											<button class="btn-cancel" onclick={() => (confirmingEraseId = null)}
												>Cancel</button
											>
										</span>
									{:else}
										<button class="btn-erase" onclick={() => (confirmingEraseId = s.id)}
											>Permanently erase…</button
										>
									{/if}
								{/if}
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		{/if}
	</section>
</div>
{/if}

<style>
	.session-check {
		text-align: center;
		padding: 4rem 1rem;
		opacity: 0.6;
		font-family: var(--font-sans, system-ui);
	}
	.roster-page {
		max-width: 900px;
		margin: 0 auto;
		padding: var(--space-8, 2rem) var(--space-5, 1.25rem);
		font-family: var(--font-sans, system-ui);
	}
	.roster-subtitle {
		opacity: 0.7;
		max-width: 60ch;
	}
	.roster-error {
		background: #fee;
		color: #900;
		padding: var(--space-3, 0.75rem);
		border-radius: 8px;
		margin-bottom: var(--space-5, 1.25rem);
	}
	.add-student form {
		display: flex;
		gap: var(--space-3, 0.75rem);
		flex-wrap: wrap;
		margin-bottom: var(--space-8, 2rem);
	}
	.add-student input[type='text'] {
		flex: 1;
		min-width: 220px;
		padding: 0.6rem 0.8rem;
		border: 1px solid #ccc;
		border-radius: 8px;
	}
	.add-student select,
	.add-student button {
		padding: 0.6rem 0.8rem;
		border-radius: 8px;
	}
	.roster-list-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	.show-inactive-toggle {
		font-size: 0.9rem;
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		margin-top: var(--space-4, 1rem);
	}
	th,
	td {
		text-align: left;
		padding: 0.6rem 0.8rem;
		border-bottom: 1px solid #eee;
	}
	.inactive-row {
		opacity: 0.5;
	}
	.actions-cell {
		display: flex;
		gap: 0.4rem;
		align-items: center;
		flex-wrap: wrap;
	}
	.btn-remove {
		color: #900;
	}
	.btn-restore {
		color: #060;
	}
	.btn-erase,
	.btn-erase-confirm {
		color: #900;
		font-weight: 600;
	}
	.erase-confirm {
		font-size: 0.85rem;
		max-width: 40ch;
		background: #fff3f3;
		padding: 0.5rem;
		border-radius: 6px;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.remark-badge {
		display: inline-block;
		font-size: 0.78rem;
		font-weight: 600;
		padding: 0.2rem 0.55rem;
		border-radius: 20px;
		background: #eef3fb;
		color: var(--color-purple-deep, #3a1a5c);
		white-space: nowrap;
	}
	.remark-pending {
		color: #999;
		font-size: 0.85rem;
	}
</style>
