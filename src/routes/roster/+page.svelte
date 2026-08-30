<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
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
		isJSS3,
		isSeniorClass,
		siblingDepartmentClassId,
		moveStudentToClass,
		type Student,
		type Remark
	} from '$lib/roster';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';

	const classId = page.url.searchParams.get('class') ?? '';

	let checkingSession = $state(true);
	let loading = $state(true);
	let error = $state('');

	let classLabel = $state('');
	let allClasses = $state<{ id: string; label: string }[]>([]);
	let students = $state<Student[]>([]);

	let newName = $state('');
	let adding = $state(false);

	let showInactive = $state(false);
	let confirmingEraseId = $state<string | null>(null);

	// Remarks -- read-only here. Auto-assigned by a DB trigger from each
	// student's average once CA/Exam/Total are complete for the term
	// (see 0006_auto_remarks.sql) -- there's no write path for staff to
	// type one, on purpose.
	let currentTermId = $state<string | null>(null);
	let remarksByStudent = $state<Map<string, Remark>>(new Map());

	let editingPortraitId = $state<string | null>(null);
	let editPortraitUrl = $state('');
	let savingPortrait = $state(false);

	async function load() {
		if (!classId) {
			loading = false;
			return;
		}
		loading = true;
		error = '';
		try {
			const [{ data: classData, error: classErr }, studentData] = await Promise.all([
				supabase.from('classes').select('id, label').order('sort_order'),
				listRoster(classId)
			]);
			if (classErr) throw classErr;
			allClasses = classData ?? [];
			classLabel = allClasses.find((c) => c.id === classId)?.label ?? classId;
			students = studentData;

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
		if (!newName.trim() || !classId) return;
		adding = true;
		error = '';
		try {
			await addStudent({ full_name: newName.trim(), class_id: classId });
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

	let movingId = $state<string | null>(null);

	async function handleMoveClass(id: string, newClassId: string) {
		error = '';
		movingId = id;
		try {
			await moveStudentToClass(id, newClassId);
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to move student';
		} finally {
			movingId = null;
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

	function initials(name: string): string {
		return name
			.split(' ')
			.map((w) => w[0])
			.filter(Boolean)
			.slice(0, 2)
			.join('')
			.toUpperCase();
	}

	const visibleStudents = $derived(students.filter((s) => showInactive || s.active));
	const activeCount = $derived(students.filter((s) => s.active).length);
</script>

<svelte:head>
	<title>{classLabel || 'Attendance & Bio Edit'} — Tendercare Teacher Dashboard</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else if !classId}
	<div class="roster-page">
		<div class="page-error" role="alert">Pick a class first.</div>
		<a class="back-button" href="/attendance">&larr; Choose a class</a>
	</div>
{:else}
<div class="roster-page">
	<Crest class="roster-watermark" />

	<header class="page-header">
		<div>
			<h1>{loading ? 'Loading…' : classLabel}</h1>
			<p>{activeCount} active students in this class.</p>
		</div>
		<a class="back-button" href="/attendance">&larr; Change class</a>
	</header>

	{#if error}
		<div class="page-error" role="alert">{error}</div>
	{/if}

	{#if !loading}
	<div class="class-tabs">
		{#each allClasses as c (c.id)}
			<a class="class-tab" class:is-active={c.id === classId} href="/roster?class={encodeURIComponent(c.id)}">{c.label}</a>
		{/each}
	</div>
	{/if}

	<section class="add-card">
		<h2 class="section-label">Add a student to {classLabel}</h2>
		<form
			onsubmit={(e) => {
				e.preventDefault();
				handleAdd();
			}}
		>
			<input type="text" placeholder="Full name" bind:value={newName} required />
			<button type="submit" class="btn-primary" disabled={adding}>{adding ? 'Adding…' : 'Add student'}</button>
		</form>
	</section>

	{#if loading}
		<p class="loading-note">Loading…</p>
	{:else}
		<div class="roster-card-wrap">
			<table class="roster-table">
				<thead>
					<tr>
						<th></th>
						<th>ID</th>
						<th>Name</th>
						<th>Remark</th>
						<th></th>
					</tr>
				</thead>
				<tbody>
					{#each visibleStudents as s (s.id)}
						<tr class:inactive-row={!s.active}>
							<td>
								<button class="portrait-dot" onclick={() => openPortraitEditor(s)} title={s.portrait_url ? 'Edit portrait link' : 'Add portrait link'}>
									{#if s.portrait_url}
										<img src={s.portrait_url} alt="" loading="lazy" />
									{:else}
										{initials(s.full_name)}
									{/if}
								</button>
							</td>
							<td class="sheet-id">{s.id}</td>
							<td class="name-cell">
								{s.full_name}
								{#if s.repeating}
									<span class="repeat-badge" title="Assigned to repeat this class">Repeating</span>
								{/if}
							</td>
							<td>
								{#if remarksByStudent.has(s.id)}
									<span
										class="remark-badge"
										title="Auto-assigned from this student's average once CA/Exam/Total are complete"
									>
										{remarksByStudent.get(s.id)?.teacher_remark}
									</span>
								{:else}
									<span class="remark-pending" title="No remark yet — scores aren't all complete for this term">—</span>
								{/if}
							</td>
							<td class="actions-cell">
								{#if s.active}
									{#if isJSS3(s.class_id)}
										<span class="promote-group" title="Promote to SS1 — choose a path">
											<button
												class="btn-promote"
												disabled={movingId === s.id}
												onclick={() => handleMoveClass(s.id, 'SS1 Science')}
											>
												→ SS1 Science
											</button>
											<button
												class="btn-promote"
												disabled={movingId === s.id}
												onclick={() => handleMoveClass(s.id, 'SS1 Actuarial')}
											>
												→ SS1 Actuarial
											</button>
										</span>
									{/if}
									{#if isSeniorClass(s.class_id)}
										<button
											class="btn-switch-dept"
											disabled={movingId === s.id}
											onclick={() => {
												const sibling = siblingDepartmentClassId(s.class_id);
												if (sibling) handleMoveClass(s.id, sibling);
											}}
											title="Students are allowed to change their mind after their first assignment"
										>
											Switch to {siblingDepartmentClassId(s.class_id)?.split(' ')[1]}
										</button>
									{/if}
									<button class="btn-repeat" onclick={() => handleToggleRepeat(s)}>
										{s.repeating ? 'Pardon repeat' : 'Assign repeat'}
									</button>
									<button class="btn-remove" onclick={() => handleRemove(s.id)}>Remove</button>
								{:else}
									<button class="btn-restore" onclick={() => handleRestore(s.id)}>Restore</button>
									{#if confirmingEraseId === s.id}
										<span class="erase-confirm">
											Permanently erase — deletes their scores, remarks, and portal access too. Cannot be
											undone.
											<button class="btn-erase-confirm" onclick={() => handlePermanentErase(s.id)}>Confirm erase</button>
											<button class="btn-cancel" onclick={() => (confirmingEraseId = null)}>Cancel</button>
										</span>
									{:else}
										<button class="btn-erase" onclick={() => (confirmingEraseId = s.id)}>Permanently erase…</button>
									{/if}
								{/if}
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>

		<p class="show-inactive-row">
			<label class="show-inactive-toggle">
				<input type="checkbox" bind:checked={showInactive} />
				Show removed students
			</label>
		</p>
	{/if}

	{#if editingPortraitId}
		<div
			class="portrait-modal-backdrop"
			role="button"
			tabindex="0"
			onclick={closePortraitEditor}
			onkeydown={(e) => e.key === 'Escape' && closePortraitEditor()}
		>
			<div class="portrait-modal" role="dialog" aria-modal="true" tabindex="-1" onclick={(e) => e.stopPropagation()}>
				<h2>Portrait link</h2>
				<p class="portrait-modal-note">
					A link, not an upload — paste a URL to an already-hosted image. Keeps the roster out of
					the 10KB-into-the-database rule.
				</p>
				<input type="url" placeholder="https://…" bind:value={editPortraitUrl} />
				<div class="portrait-modal-actions">
					<button class="btn-secondary" onclick={closePortraitEditor}>Cancel</button>
					<button class="btn-primary" onclick={handleSavePortrait} disabled={savingPortrait}>
						{savingPortrait ? 'Saving…' : 'Save'}
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
		font-family: var(--font-sans);
	}
	.roster-page {
		position: relative;
		overflow: hidden;
		max-width: 900px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
		min-height: 100dvh;
	}
	:global(.roster-watermark) {
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
	.class-tabs,
	.add-card,
	.roster-card-wrap,
	.show-inactive-row,
	.page-error {
		position: relative;
		z-index: 1;
	}
	.page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-4);
		margin-bottom: var(--space-5);
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
	.class-tabs {
		display: flex;
		gap: var(--space-2);
		flex-wrap: wrap;
		margin-bottom: var(--space-5);
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
	.class-tab.is-active {
		background: var(--color-purple);
		border-color: var(--color-purple);
		color: var(--color-white);
	}
	.class-tab:hover:not(.is-active) {
		border-color: var(--color-purple-light);
	}
	.add-card {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		padding: var(--space-5);
		margin-bottom: var(--space-6);
		box-shadow: var(--shadow-sm);
	}
	.section-label {
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: var(--tracking-wide);
		color: var(--color-purple);
		margin: 0 0 var(--space-3);
		font-weight: 600;
	}
	.add-card form {
		display: flex;
		gap: var(--space-3);
		flex-wrap: wrap;
		align-items: center;
	}
	.add-card input[type='text'] {
		flex: 1;
		min-width: 200px;
		padding: 0.7rem 0.9rem;
		border: 1.5px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		font-size: var(--text-sm);
		background: var(--color-cream);
	}
	.add-card input:focus {
		outline: none;
		border-color: var(--color-purple-light);
		background: var(--color-white);
	}
	.btn-primary {
		font-size: var(--text-sm);
		font-weight: 600;
		letter-spacing: var(--tracking-wide);
		background: var(--color-purple);
		color: var(--color-cream);
		padding: 0.7rem 1.3rem;
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
	.btn-secondary {
		font-size: var(--text-sm);
		font-weight: 600;
		background: var(--color-cream);
		color: var(--color-ink);
		padding: 0.7rem 1.2rem;
		border-radius: var(--radius-md);
		border: 1px solid var(--color-cream-deep);
		cursor: pointer;
	}
	.btn-secondary:hover {
		background: var(--color-cream-warm);
	}
	.loading-note {
		opacity: 0.6;
		font-size: var(--text-sm);
	}
	.roster-card-wrap {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		overflow: hidden;
	}
	.roster-table {
		width: 100%;
		border-collapse: collapse;
	}
	.roster-table th,
	.roster-table td {
		text-align: left;
		padding: 0.7rem 0.9rem;
		border-bottom: 1px solid var(--color-cream-deep);
		font-size: var(--text-sm);
	}
	.roster-table th {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-ash-dark);
		background: var(--color-cream);
	}
	.inactive-row {
		opacity: 0.5;
	}
	.sheet-id {
		font-family: var(--font-sans);
		font-size: 0.8rem;
		color: var(--color-ash-dark);
	}
	.name-cell {
		font-weight: 600;
		color: var(--color-ink);
	}
	.portrait-dot {
		width: 2.1rem;
		height: 2.1rem;
		border-radius: 50%;
		background: var(--color-purple-ghost);
		color: var(--color-purple-deep);
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 0.7rem;
		font-weight: 700;
		flex-shrink: 0;
		overflow: hidden;
		border: none;
		padding: 0;
		cursor: pointer;
	}
	.portrait-dot img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.actions-cell {
		display: flex;
		gap: 0.4rem;
		align-items: center;
		flex-wrap: wrap;
	}
	.btn-repeat {
		color: var(--color-purple-deep);
		font-size: var(--text-xs);
		font-weight: 600;
		background: var(--color-purple-ghost);
		padding: 0.3rem 0.6rem;
		border-radius: var(--radius-sm);
	}
	.promote-group {
		display: inline-flex;
		gap: 0.3rem;
	}
	.btn-promote {
		color: white;
		background: var(--color-purple-deep);
		font-size: var(--text-xs);
		font-weight: 600;
		padding: 0.3rem 0.6rem;
		border-radius: var(--radius-sm);
	}
	.btn-promote:disabled {
		opacity: 0.5;
	}
	.btn-switch-dept {
		color: var(--color-purple-deep);
		background: transparent;
		border: 1px solid var(--color-cream-deep);
		font-size: var(--text-xs);
		font-weight: 600;
		padding: 0.3rem 0.6rem;
		border-radius: var(--radius-sm);
	}
	.btn-switch-dept:disabled {
		opacity: 0.5;
	}
	.btn-remove {
		color: var(--color-wine);
		font-weight: 600;
		font-size: var(--text-xs);
	}
	.btn-restore {
		color: #15803d;
		font-weight: 600;
		font-size: var(--text-xs);
	}
	.btn-erase,
	.btn-erase-confirm {
		color: var(--color-wine);
		font-weight: 600;
		font-size: var(--text-xs);
	}
	.btn-cancel {
		color: var(--color-ash-dark);
		font-size: var(--text-xs);
	}
	.erase-confirm {
		font-size: 0.8rem;
		max-width: 40ch;
		background: #fdecea;
		padding: 0.5rem;
		border-radius: var(--radius-sm);
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.repeat-badge {
		display: inline-block;
		font-size: 0.7rem;
		font-weight: 700;
		padding: 0.15rem 0.5rem;
		border-radius: var(--radius-full);
		background: #fef3c7;
		color: #92400e;
		margin-left: 0.4rem;
		vertical-align: middle;
	}
	.remark-badge {
		display: inline-block;
		font-size: 0.78rem;
		font-weight: 600;
		padding: 0.2rem 0.55rem;
		border-radius: var(--radius-full);
		background: var(--color-purple-ghost);
		color: var(--color-purple-deep);
		white-space: nowrap;
	}
	.remark-pending {
		color: var(--color-ash);
		font-size: 0.85rem;
	}
	.show-inactive-row {
		margin-top: var(--space-3);
	}
	.show-inactive-toggle {
		font-size: var(--text-sm);
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}

	.portrait-modal-backdrop {
		position: fixed;
		inset: 0;
		background: rgba(26, 16, 32, 0.4);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 10;
		padding: var(--space-5);
	}
	.portrait-modal {
		background: var(--color-white);
		border-radius: var(--radius-lg);
		padding: var(--space-6);
		max-width: 400px;
		width: 100%;
		box-shadow: var(--shadow-lg);
	}
	.portrait-modal h2 {
		font-family: var(--font-serif);
		color: var(--color-purple-deep);
		font-size: var(--text-lg);
		margin: 0 0 var(--space-2);
	}
	.portrait-modal-note {
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
		margin: 0 0 var(--space-4);
	}
	.portrait-modal input {
		width: 100%;
		box-sizing: border-box;
		padding: 0.7rem 0.9rem;
		border: 1.5px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		font-size: var(--text-sm);
		margin-bottom: var(--space-4);
	}
	.portrait-modal input:focus {
		outline: none;
		border-color: var(--color-purple-light);
	}
	.portrait-modal-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-2);
	}
</style>
