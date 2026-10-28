<script lang="ts">
	import { onMount } from 'svelte';
	import Crest from '$lib/components/Crest.svelte';
	import { getProfile, broadsheetScope } from '$lib/teacherIdentity';
	import { buildBroadsheet, listTerms, type Broadsheet } from '$lib/scores';
	import { currentTerm } from '$lib/teacherData';

	// Read-only by design: this page only ever reads. Editing happens in
	// Score Entry; adding/removing/moving students happens in Attendance & Bio.

	const terms = listTerms();

	let ready = $state(false);
	let hasProfile = $state(false);
	let scope = $state<{ classId: string; label: string; subjectIds: string[] }[]>([]);
	let activeClass = $state('');
	let termId = $state(currentTerm.id);

	onMount(() => {
		const p = getProfile();
		hasProfile = !!p && (p.subjectIds.length > 0 || p.classIds.length > 0);
		scope = broadsheetScope();
		activeClass = scope[0]?.classId ?? '';
		ready = true;
	});

	const sheet = $derived<Broadsheet | null>(
		ready && activeClass
			? buildBroadsheet(activeClass, scope.find((s) => s.classId === activeClass)?.subjectIds ?? [], termId)
			: null
	);

	const anyScores = $derived(!!sheet && sheet.rows.some((r) => r.scoredSubjects > 0));

	function show(n: number | null): string {
		return n === null ? '–' : Number.isInteger(n) ? String(n) : n.toFixed(1);
	}
</script>

<svelte:head>
	<title>Broadsheet · Tendercare Teacher</title>
</svelte:head>

<div class="bs-page">
	<header class="bs-header">
		<a class="bs-back" href="/">&larr; Dashboard</a>
		<Crest size="2.1rem" style="color:var(--color-purple-light)" />
		<div class="bs-titles">
			<h1>Broadsheet</h1>
			<p>Read-only · the subjects you are concerned with</p>
		</div>
		<label class="bs-term">
			<span>Term</span>
			<select bind:value={termId}>
				{#each terms as t (t.id)}
					<option value={t.id}>{t.academic_year} · Term {t.term_number}{t.is_current ? ' (current)' : ''}</option>
				{/each}
			</select>
		</label>
	</header>

	{#if !ready}
		<p class="bs-empty">Opening…</p>
	{:else if !hasProfile || scope.length === 0}
		<p class="bs-empty">
			Choose your subjects and classes on the <a href="/">dashboard</a> first, then your broadsheets appear here.
		</p>
	{:else}
		<nav class="bs-tabs" aria-label="Class">
			{#each scope as c (c.classId)}
				<button class="bs-tab" class:bs-tab-active={c.classId === activeClass} onclick={() => (activeClass = c.classId)}>
					{c.label}
				</button>
			{/each}
		</nav>

		{#if sheet}
			{#if sheet.subjects.length === 0}
				<p class="bs-empty">None of your subjects are studied in {scope.find((s) => s.classId === activeClass)?.label}.</p>
			{:else if sheet.rows.length === 0}
				<p class="bs-empty">There are no active students in this class.</p>
			{:else}
				{#if !anyScores}
					<p class="bs-note">No scores have been entered for this class and term yet.</p>
				{/if}
				<div class="bs-scroll">
					<table class="bs-table">
						<thead>
							<tr>
								<th rowspan="2" class="bs-sticky bs-n">#</th>
								<th rowspan="2" class="bs-sticky bs-name">Student</th>
								{#each sheet.subjects as s (s.id)}
									<th colspan="3" class="bs-subject">{s.name}</th>
								{/each}
								<th rowspan="2" class="bs-sum">Total</th>
								<th rowspan="2" class="bs-sum">Avg</th>
							</tr>
							<tr>
								{#each sheet.subjects as s (s.id)}
									<th class="bs-sub">CA</th><th class="bs-sub">Exam</th><th class="bs-sub bs-sub-total">Total</th>
								{/each}
							</tr>
						</thead>
						<tbody>
							{#each sheet.rows as row, i (row.student.id)}
								<tr>
									<td class="bs-sticky bs-n">{i + 1}</td>
									<td class="bs-sticky bs-name">{row.student.full_name}</td>
									{#each sheet.subjects as s (s.id)}
										{@const c = row.cells[s.id]}
										<td class="bs-num">{show(c.ca)}</td>
										<td class="bs-num">{show(c.exam)}</td>
										<td class="bs-num bs-total">{show(c.total)}</td>
									{/each}
									<td class="bs-num bs-total">{row.scoredSubjects > 0 ? show(row.grandTotal) : '–'}</td>
									<td class="bs-num">{row.scoredSubjects > 0 ? show(Math.round((row.grandTotal / row.scoredSubjects) * 10) / 10) : '–'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
				<p class="bs-foot">
					{sheet.rows.length} active student{sheet.rows.length === 1 ? '' : 's'} · "–" means not entered · Avg is
					the mean of the subject totals entered.
				</p>
			{/if}
		{/if}
	{/if}
</div>

<style>
	.bs-page {
		min-height: 100dvh;
		padding: var(--space-5);
		background: var(--color-cream);
		font-family: var(--font-sans);
		color: var(--color-ink, #1f1630);
	}
	.bs-header {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-4);
		margin-bottom: var(--space-5);
	}
	.bs-back {
		font-weight: 600;
		text-decoration: none;
		color: var(--color-purple-deep);
	}
	.bs-titles h1 {
		margin: 0;
		font-size: 1.4rem;
	}
	.bs-titles p {
		margin: 0;
		font-size: 0.85rem;
		opacity: 0.75;
	}
	.bs-term {
		margin-left: auto;
		display: flex;
		flex-direction: column;
		font-size: 0.8rem;
		gap: 2px;
	}
	.bs-term select {
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--color-purple-light);
		border-radius: var(--radius-md);
		font: inherit;
		background: #fff;
	}
	.bs-tabs {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-bottom: var(--space-4);
	}
	.bs-tab {
		padding: var(--space-2) var(--space-4);
		border: 1px solid var(--color-purple-light);
		border-radius: 999px;
		background: #fff;
		font: inherit;
		cursor: pointer;
	}
	.bs-tab-active {
		background: var(--color-purple-deep);
		border-color: var(--color-purple-deep);
		color: #fff;
	}
	.bs-empty,
	.bs-note,
	.bs-foot {
		font-size: 0.9rem;
		opacity: 0.85;
	}
	.bs-scroll {
		overflow: auto;
		max-height: 72dvh;
		border: 1px solid var(--color-purple-light);
		border-radius: var(--radius-md);
		background: #fff;
	}
	.bs-table {
		border-collapse: separate;
		border-spacing: 0;
		font-size: 0.85rem;
		min-width: 100%;
	}
	.bs-table th,
	.bs-table td {
		padding: 6px 8px;
		border-bottom: 1px solid #ece7f4;
		border-right: 1px solid #f3eff9;
		white-space: nowrap;
		text-align: center;
	}
	.bs-table thead th {
		position: sticky;
		top: 0;
		background: var(--color-purple-deep);
		color: #fff;
		z-index: 2;
	}
	.bs-table thead tr:nth-child(2) th {
		top: 2rem;
		background: #4a2b73;
		font-weight: 500;
		font-size: 0.75rem;
	}
	.bs-sticky {
		position: sticky;
		left: 0;
		background: #fff;
		z-index: 1;
	}
	.bs-table thead .bs-sticky {
		background: var(--color-purple-deep);
		z-index: 3;
	}
	.bs-n {
		width: 2.2rem;
		min-width: 2.2rem;
	}
	.bs-name {
		left: 2.2rem;
		text-align: left;
		min-width: 12rem;
		font-weight: 600;
	}
	.bs-num {
		font-variant-numeric: tabular-nums;
	}
	.bs-total {
		font-weight: 700;
		background: #faf8fd;
	}
	.bs-sum {
		min-width: 4rem;
	}
</style>
