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
		upsertRemark,
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
	let editingRemarkId = $state<string | null>(null);
	let editTeacherRemark = $state('');
	let editPrincipalRemark = $state('');
	let savingRemark = $state(false);

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

	function openRemarkEditor(studentId: string) {
		const existing = remarksByStudent.get(studentId);
		editTeacherRemark = existing?.teacher_remark ?? '';
		editPrincipalRemark = existing?.principal_remark ?? '';
		editingRemarkId = studentId;
	}

	function closeRemarkEditor() {
		editingRemarkId = null;
	}

	async function handleSaveRemark() {
		if (!editingRemarkId || !currentTermId) return;
		savingRemark = true;
		error = '';
		try {
			await upsertRemark(editingRemarkId, currentTermId, editTeacherRemark, editPrincipalRemark);
			remarksByStudent = await listRemarksForTerm(
				students.map((s) => s.id),
				currentTermId
			);
			editingRemarkId = null;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save remark';
		} finally {
			savingRemark = false;
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
						<th></th>
					</tr>
				</thead>
				<tbody>
					{#each visibleStudents as s (s.id)}
						<tr class:inactive-row={!s.active}>
							<td>{s.id}</td>
							<td>{s.full_name}</td>
							<td>{s.class_id}</td>
							<td>{s.active ? 'Active' : 'Removed'}</td>
							<td class="actions-cell">
								{#if s.active}
									<button
										class="btn-remark"
										onclick={() => openRemarkEditor(s.id)}
										disabled={!currentTermId}
										title={currentTermId ? '' : 'No current term set (terms.is_current)'}
									>
										{remarksByStudent.has(s.id) ? 'Edit remark' : 'Add remark'}
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

	{#if editingRemarkId}
		{@const s = students.find((x) => x.id === editingRemarkId)}
		<div class="remark-modal-backdrop" onclick={closeRemarkEditor}>
			<div class="remark-modal" onclick={(e) => e.stopPropagation()}>
				<h2>Remark — {s?.full_name ?? editingRemarkId}</h2>
				<p class="remark-modal-sub">Current term ({currentTermId}) only. Past terms belong to their already-generated report.</p>

				<label for="teacher-remark">Class Teacher's Comment</label>
				<textarea
					id="teacher-remark"
					rows="3"
					bind:value={editTeacherRemark}
					placeholder="e.g. A diligent and attentive student this term…"
				></textarea>

				<label for="principal-remark">Principal's Comment</label>
				<textarea
					id="principal-remark"
					rows="3"
					bind:value={editPrincipalRemark}
					placeholder="e.g. Commendable progress. Keep up the good work."
				></textarea>

				<div class="remark-modal-actions">
					<button class="btn-cancel" onclick={closeRemarkEditor} disabled={savingRemark}>Cancel</button>
					<button class="btn-save-remark" onclick={handleSaveRemark} disabled={savingRemark}>
						{savingRemark ? 'Saving…' : 'Save remark'}
					</button>
				</div>
			</div>
		</div>
	{/if}
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
	.btn-remark {
		color: var(--color-purple-deep, #3a1a5c);
		font-weight: 600;
	}
	.btn-remark:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.remark-modal-backdrop {
		position: fixed;
		inset: 0;
		background: rgba(20, 20, 30, 0.45);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 40;
		padding: 1rem;
	}
	.remark-modal {
		background: white;
		border-radius: 10px;
		padding: 1.5rem;
		max-width: 480px;
		width: 100%;
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		box-shadow: 0 12px 40px rgba(0, 0, 0, 0.2);
	}
	.remark-modal h2 {
		font-size: 1.1rem;
	}
	.remark-modal-sub {
		font-size: 0.8rem;
		opacity: 0.6;
		margin-bottom: 0.3rem;
	}
	.remark-modal label {
		font-size: 0.8rem;
		font-weight: 600;
		margin-top: 0.3rem;
	}
	.remark-modal textarea {
		width: 100%;
		font-family: inherit;
		font-size: 0.9rem;
		padding: 0.5rem;
		border: 1px solid #ddd;
		border-radius: 6px;
		resize: vertical;
	}
	.remark-modal-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
		margin-top: 0.6rem;
	}
	.btn-save-remark {
		background: var(--color-purple-deep, #3a1a5c);
		color: white;
		padding: 0.5rem 1rem;
		border-radius: 6px;
		font-weight: 600;
	}
	.btn-save-remark:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
</style>
