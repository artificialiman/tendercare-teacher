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

	/**
	 * Max marks are editable per sheet, not stored anywhere -- there's no
	 * column for it in `scores` or `subjects`. Defaults match the
	 * manual-shell reference (30 CA / 70 Exam), not an invented 40/60.
	 * Changing them here only affects how this session grades/displays;
	 * it doesn't rewrite any already-saved CA/Exam numbers.
	 */
	let maxCA = $state(30);
	let maxExam = $state(70);

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
		const max = field === 'ca' ? maxCA : maxExam;
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

	async function handleClearAll() {
		if (!termId) return;
		if (!confirm(`Clear every CA and Exam score on this sheet for ${classLabel}? This can't be undone.`)) return;
		error = '';
		try {
			await Promise.all(
				students.flatMap((s) => [saveScore(s.id, subjectId, termId!, 'ca', 0), saveScore(s.id, subjectId, termId!, 'exam', 0)])
			);
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to clear scores';
		}
	}

	const totals = $derived(students.map((s) => totalFor(s.id)).filter((t): t is number => t !== null));
	const average = $derived(totals.length ? totals.reduce((a, b) => a + b, 0) / totals.length : 0);
	const highest = $derived(totals.length ? Math.max(...totals) : 0);
	const lowest = $derived(totals.length ? Math.min(...totals) : 0);
</script>

<svelte:head>
	<title>{subjectName || 'Score Entry'} — {classLabel} — Tendercare Teacher Dashboard</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else}
<div class="sheet-page">
	<Crest class="sheet-watermark" />

	<header class="page-header">
		<div>
			<span class="subject-pill">{loading ? '—' : subjectName}</span>
			<h1>{loading ? 'Loading…' : classLabel}</h1>
			<p class="term-note">{termLabel || 'No current term set'}</p>
		</div>
		<a class="back-button" href="/score">&larr; Change assignment</a>
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
		<div class="sheet-toolbar">
			<div>
				<div class="sheet-toolbar-title">{classLabel} Broadsheet</div>
				<div class="sheet-toolbar-meta">
					Max CA
					<input type="number" min="0" class="max-input" bind:value={maxCA} />
					· Max Exam
					<input type="number" min="0" class="max-input" bind:value={maxExam} />
				</div>
			</div>
			<button class="btn-secondary" onclick={handleClearAll}>Clear all</button>
		</div>

		<div class="sheet-stats">
			<div class="sheet-stat"><span class="stat-label">Students</span><span class="stat-value">{students.length}</span></div>
			<div class="sheet-stat"><span class="stat-label">Average</span><span class="stat-value">{average.toFixed(1)}</span></div>
			<div class="sheet-stat"><span class="stat-label">Highest</span><span class="stat-value">{highest}</span></div>
			<div class="sheet-stat"><span class="stat-label">Lowest</span><span class="stat-value">{lowest}</span></div>
		</div>

		<div class="sheet-table-wrap">
		<table class="score-sheet">
			<thead>
				<tr>
					<th>ID</th>
					<th>Name</th>
					<th class:col-active={activeField === 'ca'}>CA <span class="max-note">({maxCA})</span></th>
					<th class:col-active={activeField === 'exam'}>Exam <span class="max-note">({maxExam})</span></th>
					<th>Total</th>
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
						<td class="num-cell" class:cell-active={activeRow === i && activeField === 'ca'} class:col-active={activeField === 'ca' && activeRow !== i}>
							<input
								type="number"
								inputmode="decimal"
								min="0"
								max={maxCA}
								class="score-input"
								class:saving={savingCell === `${s.id}:ca`}
								value={editValues.get(s.id)?.ca ?? ''}
								oninput={(e) => updateValue(s.id, 'ca', (e.target as HTMLInputElement).value)}
								onfocus={() => (activeField = 'ca')}
								onblur={() => handleBlur(s.id, 'ca')}
							/>
						</td>
						<td class="num-cell" class:cell-active={activeRow === i && activeField === 'exam'} class:col-active={activeField === 'exam' && activeRow !== i}>
							<input
								type="number"
								inputmode="decimal"
								min="0"
								max={maxExam}
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
								<span class="grade-badge grade-{nigerianGrade(total, maxCA, maxExam).toLowerCase()}">{nigerianGrade(total, maxCA, maxExam)}</span>
							{:else}
								<span class="grade-pending">—</span>
							{/if}
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
		</div>
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
	.page-header,
	.page-error,
	.sheet-card,
	.loading-note,
	.empty-note,
	.autosave-note {
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
	.page-header h1 {
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

	.sheet-card {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-sm);
		overflow: hidden;
	}
	.sheet-toolbar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		flex-wrap: wrap;
		gap: var(--space-3);
		padding: var(--space-4) var(--space-5);
		border-bottom: 1px solid var(--color-cream-deep);
		background: var(--color-cream);
	}
	.sheet-toolbar-title {
		font-family: var(--font-serif);
		font-weight: 600;
		font-size: var(--text-lg);
		color: var(--color-purple-deep);
	}
	.sheet-toolbar-meta {
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
		margin-top: 0.2rem;
	}
	.max-input {
		width: 3.4rem;
		text-align: center;
		padding: 0.2rem 0.3rem;
		margin: 0 0.3rem;
		font-size: var(--text-xs);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-sm);
		background: var(--color-white);
	}
	.btn-secondary {
		font-size: var(--text-sm);
		font-weight: 600;
		background: var(--color-white);
		color: var(--color-ink);
		padding: 0.6rem 1.1rem;
		border-radius: var(--radius-md);
		border: 1px solid var(--color-cream-deep);
		cursor: pointer;
	}
	.btn-secondary:hover {
		background: var(--color-cream-warm);
	}
	.sheet-stats {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 1px;
		background: var(--color-cream-deep);
		border-bottom: 1px solid var(--color-cream-deep);
	}
	.sheet-stat {
		background: var(--color-white);
		padding: var(--space-3) var(--space-4);
		text-align: center;
	}
	.stat-label {
		display: block;
		font-size: 0.68rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-ash-dark);
		margin-bottom: 0.2rem;
	}
	.stat-value {
		display: block;
		font-size: 1.35rem;
		font-weight: 700;
		color: var(--color-purple-deep);
		font-family: var(--font-serif);
	}
	.sheet-table-wrap {
		overflow-x: auto;
	}
	table.score-sheet {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--text-sm);
		min-width: 620px;
	}
	thead th {
		text-align: left;
		padding: 0.9rem 1rem;
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-ash-dark);
		border-bottom: 2px solid var(--color-cream-deep);
		white-space: nowrap;
		background: var(--color-white);
		position: sticky;
		top: 0;
	}
	thead th.col-active {
		background: var(--color-lemon-ghost);
		color: var(--color-purple-deep);
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
		padding: 0.7rem 1rem;
	}
	.id-cell {
		font-family: var(--font-sans);
		font-size: 0.8rem;
		color: var(--color-ash-dark);
	}
	.name-cell {
		font-weight: 600;
		color: var(--color-ink);
	}
	.total-cell {
		font-weight: 700;
		font-family: var(--font-serif);
		font-size: 1.05rem;
		color: var(--color-purple-deep);
		text-align: center;
	}
	.grade-badge {
		display: inline-block;
		padding: 0.3rem 0.7rem;
		border-radius: var(--radius-full);
		font-weight: 700;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		min-width: 2.4rem;
		text-align: center;
	}
	.grade-a1 { background: rgba(34, 197, 94, 0.15); color: #15803d; }
	.grade-b2 { background: rgba(52, 211, 153, 0.15); color: #0f766e; }
	.grade-b3 { background: rgba(59, 130, 246, 0.15); color: #1d4ed8; }
	.grade-c4 { background: rgba(96, 165, 250, 0.15); color: #1e40af; }
	.grade-c5 { background: rgba(234, 179, 8, 0.18); color: #92400e; }
	.grade-c6 { background: rgba(250, 204, 21, 0.2); color: #92400e; }
	.grade-d7 { background: rgba(249, 115, 22, 0.18); color: #9a3412; }
	.grade-e8 { background: rgba(239, 68, 68, 0.15); color: #b91c1c; }
	.grade-f9 { background: rgba(220, 38, 38, 0.18); color: #991b1b; }
	.grade-pending {
		color: var(--color-ash);
	}

	tr.row-active td {
		background: var(--color-lemon-ghost);
	}
	tr.row-active td.cell-active {
		background: #e8dfa0;
	}
	td.col-active {
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
		padding: 0.7rem 0.6rem;
		border: none;
		background: transparent;
		text-align: center;
		font-family: var(--font-sans);
		font-size: var(--text-sm);
		color: var(--color-ink);
	}
	.score-input:focus {
		outline: none;
		background: var(--color-white);
		box-shadow: inset 0 0 0 2px var(--color-purple-mid);
	}
	.score-input.saving {
		background: var(--color-purple-ghost);
	}
	.autosave-note {
		margin-top: var(--space-4);
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
		text-align: center;
	}
</style>
