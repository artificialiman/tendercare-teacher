<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { supabase } from '$lib/supabase';
	import { listRoster, getCurrentTermId, type Student } from '$lib/roster';
	import { listScores, saveScore, nigerianGrade, type ScoreEntry } from '$lib/scores';
	import Crest from '$lib/components/Crest.svelte';

	const subjectId = page.url.searchParams.get('subject') ?? '';
	const classId = page.url.searchParams.get('class') ?? '';

	const CA_MAX = 40;
	const EXAM_MAX = 60;

	let checkingSession = $state(true);
	let loading = $state(true);
	let error = $state('');
	let subjectName = $state('');
	let classLabel = $state('');
	let termId = $state<string | null>(null);
	let termLabel = $state('');

	let students = $state<Student[]>([]);
	let scoresByStudent = $state<Map<string, ScoreEntry>>(new Map());
	let editValues = $state<Map<string, { ca: string; exam: string }>>(new Map());
	let savingCell = $state<string | null>(null); // `${studentId}:${field}`
	let activeRow = $state<number | null>(null);
	let activeField = $state<'ca' | 'exam' | null>(null);

	onMount(async () => {
		const {
			data: { session }
		} = await supabase.auth.getSession();
		if (!session) {
			goto('/login');
			return;
		}
		checkingSession = false;

		if (!subjectId || !classId) {
			error = 'Missing subject or class — go back and pick both.';
			loading = false;
			return;
		}
		await load();
	});

	async function load() {
		loading = true;
		error = '';
		try {
			const [{ data: subj }, { data: cls }, roster, tId, term] = await Promise.all([
				supabase.from('subjects').select('name').eq('id', subjectId).maybeSingle(),
				supabase.from('classes').select('label').eq('id', classId).maybeSingle(),
				listRoster(classId),
				getCurrentTermId(),
				supabase.from('terms').select('academic_year, term_number').eq('is_current', true).maybeSingle()
			]);
			subjectName = subj?.name ?? subjectId;
			classLabel = cls?.label ?? classId;
			students = roster.filter((s) => s.active);
			termId = tId;
			termLabel = term.data ? `${term.data.academic_year} · Term ${term.data.term_number}` : '';

			if (termId) {
				scoresByStudent = await listScores(
					students.map((s) => s.id),
					subjectId,
					termId
				);
			}
			editValues = new Map(
				students.map((s) => {
					const existing = scoresByStudent.get(s.id);
					return [
						s.id,
						{
							ca: existing?.ca != null ? String(existing.ca) : '',
							exam: existing?.exam != null ? String(existing.exam) : ''
						}
					];
				})
			);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load sheet';
		} finally {
			loading = false;
		}
	}

	function totalFor(studentId: string): number | null {
		const v = editValues.get(studentId);
		if (!v) return null;
		const ca = v.ca === '' ? null : Number(v.ca);
		const exam = v.exam === '' ? null : Number(v.exam);
		if (ca === null || exam === null || Number.isNaN(ca) || Number.isNaN(exam)) return null;
		return ca + exam;
	}

	async function handleBlur(studentId: string, field: 'ca' | 'exam') {
		if (!termId) return;
		const v = editValues.get(studentId);
		if (!v) return;
		const raw = v[field];
		if (raw === '') return;
		const max = field === 'ca' ? CA_MAX : EXAM_MAX;
		let num = Number(raw);
		if (Number.isNaN(num)) return;
		if (num < 0) num = 0;
		if (num > max) num = max;
		v[field] = String(num);
		editValues.set(studentId, { ...v });
		editValues = new Map(editValues);

		savingCell = `${studentId}:${field}`;
		error = '';
		try {
			await saveScore(studentId, subjectId, termId, field, num);
			const existing = scoresByStudent.get(studentId) ?? { student_id: studentId, ca: null, exam: null };
			scoresByStudent.set(studentId, { ...existing, [field]: num });
			scoresByStudent = new Map(scoresByStudent);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save score';
		} finally {
			savingCell = null;
		}
	}

	function updateValue(studentId: string, field: 'ca' | 'exam', value: string) {
		const v = editValues.get(studentId) ?? { ca: '', exam: '' };
		v[field] = value;
		editValues.set(studentId, { ...v });
		editValues = new Map(editValues);
	}
</script>

<svelte:head>
	<title>{subjectName || 'Score Entry'} — {classLabel} — Tendercare Teacher Dashboard</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else}
<div class="sheet-page">
	<Crest class="sheet-watermark" aria-hidden="true" />

	<header class="sheet-header">
		<div>
			<span class="subject-pill">{loading ? '—' : subjectName}</span>
			<h1>{loading ? 'Loading…' : classLabel}</h1>
			<p class="term-note">{termLabel || 'No current term set'}</p>
		</div>
		<a class="back-button" href="/score">&larr; Change subject/class</a>
	</header>

	{#if error}
		<div class="page-error" role="alert">{error}</div>
	{/if}

	{#if loading}
		<p class="loading-note">Loading sheet…</p>
	{:else if !termId}
		<p class="empty-note">No current term is set — scores can't be recorded until one is.</p>
	{:else if students.length === 0}
		<p class="empty-note">No active students in {classLabel}.</p>
	{:else}
	<div class="sheet-card">
		<table class="score-sheet" class:has-active-row={activeRow !== null}>
			<colgroup>
				<col class="col-id" />
				<col class="col-name" />
				<col class="col-num col-ca" />
				<col class="col-num col-exam" />
				<col class="col-num col-total" />
				<col class="col-grade" />
			</colgroup>
			<thead>
				<tr>
					<th>ID</th>
					<th>Name</th>
					<th>CA <span class="max-note">/{CA_MAX}</span></th>
					<th>Exam <span class="max-note">/{EXAM_MAX}</span></th>
					<th>Total <span class="max-note">/{CA_MAX + EXAM_MAX}</span></th>
					<th>Grade</th>
				</tr>
			</thead>
			<tbody>
				{#each students as s, i (s.id)}
					{@const total = totalFor(s.id)}
					<tr
						class:row-active={activeRow === i}
						onfocusin={() => (activeRow = i)}
						onfocusout={() => {
							activeRow = null;
							activeField = null;
						}}
					>
						<td class="id-cell">{s.id}</td>
						<td class="name-cell">{s.full_name}</td>
						<td class="num-cell" class:col-active={activeField === 'ca' && activeRow !== i}>
							<input
								type="number"
								inputmode="decimal"
								min="0"
								max={CA_MAX}
								class="score-input"
								class:saving={savingCell === `${s.id}:ca`}
								value={editValues.get(s.id)?.ca ?? ''}
								oninput={(e) => updateValue(s.id, 'ca', (e.target as HTMLInputElement).value)}
								onfocus={() => (activeField = 'ca')}
								onblur={() => handleBlur(s.id, 'ca')}
							/>
						</td>
						<td class="num-cell" class:col-active={activeField === 'exam' && activeRow !== i}>
							<input
								type="number"
								inputmode="decimal"
								min="0"
								max={EXAM_MAX}
								class="score-input"
								class:saving={savingCell === `${s.id}:exam`}
								value={editValues.get(s.id)?.exam ?? ''}
								oninput={(e) => updateValue(s.id, 'exam', (e.target as HTMLInputElement).value)}
								onfocus={() => (activeField = 'exam')}
								onblur={() => handleBlur(s.id, 'exam')}
							/>
						</td>
						<td class="num-cell total-cell">{total ?? '—'}</td>
						<td class="grade-cell">
							{#if total !== null}
								<span class="grade-badge">{nigerianGrade(total, CA_MAX, EXAM_MAX)}</span>
							{:else}
								<span class="grade-pending">—</span>
							{/if}
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
	<p class="autosave-note">Each field saves automatically when you move to the next one.</p>
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
	.sheet-page {
		position: relative;
		overflow: hidden;
		max-width: 1100px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
		min-height: 100dvh;
	}
	:global(.sheet-watermark) {
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
	.sheet-header,
	.page-error,
	.sheet-card,
	.loading-note,
	.empty-note,
	.autosave-note {
		position: relative;
		z-index: 1;
	}
	.sheet-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-4);
		margin-bottom: var(--space-6);
		flex-wrap: wrap;
	}
	.subject-pill {
		display: inline-block;
		font-size: var(--text-xs);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: var(--tracking-wide);
		background: var(--color-purple-ghost);
		color: var(--color-purple-deep);
		padding: 0.25rem 0.7rem;
		border-radius: var(--radius-full);
		margin-bottom: var(--space-2);
	}
	.sheet-header h1 {
		font-family: var(--font-serif);
		font-weight: 400;
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		margin: 0 0 var(--space-1);
	}
	.term-note {
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
	.loading-note,
	.empty-note {
		opacity: 0.6;
		font-size: var(--text-sm);
	}

	/* Paper-like sheet, matching the printed report cards and letterhead
	   treatment used across the suite -- white surface, deep-purple rules,
	   no chrome besides the crest watermark. */
	.sheet-card {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-sm);
		overflow-x: auto;
	}
	table.score-sheet {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--text-sm);
	}
	.col-id {
		width: 110px;
	}
	.col-num {
		width: 90px;
	}
	.col-grade {
		width: 80px;
	}
	thead th {
		text-align: left;
		padding: var(--space-3) var(--space-4);
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-purple-deep);
		background: var(--color-cream);
		border-bottom: 2px solid var(--color-purple-light);
		position: sticky;
		top: 0;
	}
	.max-note {
		opacity: 0.5;
		font-weight: 400;
		text-transform: none;
	}
	tbody td {
		padding: 0;
		border-bottom: 1px solid var(--color-cream-deep);
	}
	.id-cell,
	.name-cell,
	.total-cell,
	.grade-cell {
		padding: var(--space-3) var(--space-4);
	}
	.id-cell {
		font-family: var(--font-sans);
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
	}
	.name-cell {
		font-weight: 600;
		color: var(--color-ink);
	}
	.total-cell {
		font-weight: 700;
		color: var(--color-purple-deep);
		text-align: center;
	}
	.grade-badge {
		display: inline-block;
		font-size: var(--text-xs);
		font-weight: 700;
		padding: 0.2rem 0.55rem;
		border-radius: var(--radius-full);
		background: var(--color-purple-ghost);
		color: var(--color-purple-deep);
	}
	.grade-pending {
		color: var(--color-ash);
	}

	/* Full row + column crosshair highlight on the cell being edited.
	   Row: a plain background swap on the active <tr>, driven by
	   focus events (works for keyboard tabbing, not just mouse clicks).
	   Column: box-shadow ridges on every cell in that column via
	   nth-child, scoped by which input has focus. */
	tr.row-active {
		background: var(--color-lemon-ghost);
	}
	tr.row-active .id-cell,
	tr.row-active .name-cell,
	tr.row-active .total-cell {
		background: var(--color-lemon-ghost);
	}
	.num-cell {
		text-align: center;
		vertical-align: middle;
	}
	.score-input {
		width: 100%;
		height: 100%;
		box-sizing: border-box;
		padding: var(--space-3) var(--space-2);
		border: none;
		background: transparent;
		text-align: center;
		font-family: var(--font-sans);
		font-size: var(--text-sm);
		color: var(--color-ink);
	}
	.score-input:focus {
		outline: none;
		background: var(--color-lemon-soft);
		box-shadow: inset 0 0 0 2px var(--color-purple);
	}
	.score-input.saving {
		background: var(--color-purple-ghost);
	}
	/* Column crosshair: every other cell in the active field's column
	   (across all rows) gets the same wash, via a class toggled in
	   script rather than a <col>-targeted selector -- background on
	   <col>/<colgroup> doesn't render reliably across browsers. */
	td.col-active {
		background: var(--color-lemon-ghost);
	}
	.autosave-note {
		margin-top: var(--space-4);
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
		text-align: center;
	}
</style>
