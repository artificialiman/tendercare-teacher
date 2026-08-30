<script lang="ts">
	import { onMount } from 'svelte';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';
	import BarChart from '$lib/components/BarChart.svelte';
	import {
		listSubjectAverages,
		listClassAverages,
		listScoreEntryCompletion,
		listNewStudents,
		type SubjectAverage,
		type ClassAverage,
		type ClassEntryCompletion,
		type NewStudent
	} from '$lib/analytics';

	let loading = $state(true);
	let termLabel = $state('');

	let subjectAverages = $state<SubjectAverage[]>([]);
	let classAverages = $state<ClassAverage[]>([]);
	let completion = $state<ClassEntryCompletion[]>([]);
	let newStudents = $state<NewStudent[]>([]);
	let staffByType = $state<{ label: string; value: number }[]>([]);

	onMount(load);

	async function load() {
		loading = true;

		const { data: term } = await supabase
			.from('terms')
			.select('id, academic_year, term_number')
			.eq('is_current', true)
			.maybeSingle();

		if (!term) {
			loading = false;
			return;
		}
		termLabel = `${term.academic_year} · Term ${term.term_number}`;

		const [subjAvg, clsAvg, comp, recent, staffRes] = await Promise.all([
			listSubjectAverages(term.id),
			listClassAverages(term.id, term.academic_year),
			listScoreEntryCompletion(term.id),
			listNewStudents(60),
			supabase.from('staff').select('staff_type').eq('active', true)
		]);

		subjectAverages = subjAvg;
		classAverages = clsAvg;
		completion = comp.sort((a, b) => a.percent - b.percent);
		newStudents = recent;

		const typeLabels: Record<string, string> = {
			part_time: 'Part-time',
			full_time: 'Full-time',
			corps_member: 'Corps Member'
		};
		const byType = new Map<string, number>();
		for (const s of staffRes.data ?? []) {
			byType.set(s.staff_type, (byType.get(s.staff_type) ?? 0) + 1);
		}
		staffByType = [...byType.entries()].map(([type, value]) => ({
			label: typeLabels[type] ?? type,
			value
		}));

		loading = false;
	}

	const schoolAverage = $derived.by(() => {
		const rated = classAverages.filter((c) => c.average !== null);
		if (rated.length === 0) return null;
		return Math.round((rated.reduce((s, c) => s + (c.average ?? 0), 0) / rated.length) * 10) / 10;
	});

	const stageAverage = (stage: 'JSS' | 'SS') => {
		const rated = classAverages.filter((c) => c.stage === stage && c.average !== null);
		if (rated.length === 0) return null;
		return Math.round((rated.reduce((s, c) => s + (c.average ?? 0), 0) / rated.length) * 10) / 10;
	};
	const jssAverage = $derived(stageAverage('JSS'));
	const ssAverage = $derived(stageAverage('SS'));

	const topClass = $derived.by(() => {
		const rated = classAverages.filter((c) => c.average !== null);
		if (rated.length === 0) return null;
		return rated.reduce((best, c) => ((c.average ?? 0) > (best.average ?? 0) ? c : best));
	});

	const bySet = $derived.by(() => {
		const groups = new Map<number, ClassAverage[]>();
		for (const c of classAverages) {
			if (!groups.has(c.graduatingYear)) groups.set(c.graduatingYear, []);
			groups.get(c.graduatingYear)!.push(c);
		}
		return [...groups.entries()]
			.sort((a, b) => a[0] - b[0])
			.map(([year, classes]) => {
				const rated = classes.filter((c) => c.average !== null);
				const avg = rated.length
					? Math.round((rated.reduce((s, c) => s + (c.average ?? 0), 0) / rated.length) * 10) / 10
					: null;
				return { year, avg, classCount: classes.length };
			});
	});

	const classAverageBars = $derived(
		classAverages
			.filter((c) => c.average !== null)
			.sort((a, b) => a.classId.localeCompare(b.classId))
			.map((c) => ({ label: c.classLabel, value: c.average as number }))
	);

	function statusColor(percent: number): string {
		if (percent >= 80) return '#15803d';
		if (percent >= 40) return '#b45309';
		return '#b91c1c';
	}
</script>

<svelte:head>
	<title>Analytics — Tendercare Admin</title>
</svelte:head>

<div class="analytics">
	<Crest class="analytics__watermark" />

	<header class="analytics__header">
		<a href="/admin" class="analytics__back">&larr; Admin</a>
		<h1>Analytics</h1>
		<p class="analytics__term">{termLabel}</p>
	</header>

	{#if loading}
		<p class="analytics__loading">Loading…</p>
	{:else}
		<!-- Wrapped -->
		<div class="wrapped-row">
			<div class="wrapped-card wrapped-card--hero">
				<span class="wrapped-card__value">{schoolAverage ?? '—'}</span>
				<span class="wrapped-card__label">School Average</span>
			</div>
			<div class="wrapped-card">
				<span class="wrapped-card__value">{jssAverage ?? '—'}</span>
				<span class="wrapped-card__label">JSS Average</span>
			</div>
			<div class="wrapped-card">
				<span class="wrapped-card__value">{ssAverage ?? '—'}</span>
				<span class="wrapped-card__label">SS Average</span>
			</div>
			<div class="wrapped-card">
				<span class="wrapped-card__value">{topClass?.classLabel ?? '—'}</span>
				<span class="wrapped-card__label">Top Class{topClass ? ` · ${topClass.average}` : ''}</span>
			</div>
			<a href="/admin/staff" class="wrapped-card wrapped-card--link">
				<span class="wrapped-card__value">{staffByType.reduce((s, t) => s + t.value, 0)}</span>
				<span class="wrapped-card__label">Staff →</span>
			</a>
			<div class="wrapped-card">
				<span class="wrapped-card__value">{newStudents.length}</span>
				<span class="wrapped-card__label">New (60d)</span>
			</div>
		</div>

		<div class="analytics__grid">
			<BarChart title="Subject Performance" bars={subjectAverages.map((s) => ({ label: s.subjectName, value: s.average }))} color="var(--color-purple)" />
			<BarChart title="Class Averages" bars={classAverageBars} color="var(--color-purple-mid)" />
		</div>

		<section class="panel">
			<h2>By Set</h2>
			<div class="set-row">
				{#each bySet as s (s.year)}
					<div class="set-chip">
						<span class="set-chip__year">Set '{String(s.year).slice(-2)}</span>
						<span class="set-chip__value">{s.avg ?? '—'}</span>
						<span class="set-chip__count">{s.classCount} class{s.classCount === 1 ? '' : 'es'}</span>
					</div>
				{/each}
			</div>
		</section>

		<section class="panel">
			<h2>Score-Entry Completion</h2>
			<div class="completion-list">
				{#each completion as c (c.classId)}
					<div class="completion-row">
						<span class="completion-label">{c.classLabel}</span>
						<div class="completion-track">
							<div class="completion-fill" style="width:{c.percent}%;background:{statusColor(c.percent)};"></div>
						</div>
						<span class="completion-value" style="color:{statusColor(c.percent)};">{c.percent}%</span>
					</div>
				{/each}
			</div>
		</section>

		<section class="panel">
			<h2>New Students</h2>
			{#if newStudents.length === 0}
				<p class="empty-note">None in the last 60 days.</p>
			{:else}
				<div class="new-students-list">
					{#each newStudents as s (s.id)}
						<div class="new-student-row">
							<span>{s.full_name}</span>
							<span class="new-student-class">{s.class_id}</span>
						</div>
					{/each}
				</div>
			{/if}
		</section>
	{/if}
</div>

<style>
	.analytics {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		max-width: 1100px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
	}
	:global(.analytics__watermark) {
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
	.analytics__header,
	.wrapped-row,
	.analytics__grid,
	.panel {
		position: relative;
		z-index: 1;
	}
	.analytics__back {
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-purple-deep);
		text-decoration: none;
		opacity: 0.7;
	}
	.analytics__header h1 {
		font-family: var(--font-serif);
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		margin: var(--space-2) 0 0.15rem;
	}
	.analytics__term {
		opacity: 0.55;
		margin: 0 0 var(--space-6);
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.analytics__loading {
		opacity: 0.6;
		padding: var(--space-8) 0;
	}

	.wrapped-row {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
		gap: var(--space-3);
		margin-bottom: var(--space-8);
	}
	.wrapped-card {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		padding: var(--space-5) var(--space-4);
		border-radius: var(--radius-lg);
		background: var(--color-ink);
		color: white;
		text-decoration: none;
	}
	.wrapped-card--hero {
		background: var(--color-purple-deep);
		grid-column: span 2;
	}
	.wrapped-card--link {
		cursor: pointer;
	}
	.wrapped-card__value {
		font-family: var(--font-display);
		font-size: var(--text-3xl);
		color: var(--color-lemon);
		line-height: 1.1;
	}
	.wrapped-card--hero .wrapped-card__value {
		font-size: 3.2rem;
	}
	.wrapped-card__label {
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: rgba(255, 255, 255, 0.65);
	}

	.analytics__grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
		gap: var(--space-6);
		margin-bottom: var(--space-8);
	}

	.panel {
		margin-bottom: var(--space-8);
	}
	.panel h2 {
		font-family: var(--font-serif);
		font-size: var(--text-md);
		color: var(--color-purple-deep);
		margin: 0 0 var(--space-4);
	}

	.set-row {
		display: flex;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.set-chip {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.1rem;
		padding: var(--space-4);
		border-radius: var(--radius-md);
		background: var(--color-cream);
		border: 1px solid var(--color-cream-deep);
		min-width: 90px;
	}
	.set-chip__year {
		font-size: var(--text-xs);
		opacity: 0.6;
	}
	.set-chip__value {
		font-family: var(--font-serif);
		font-size: var(--text-xl);
		color: var(--color-purple-deep);
	}
	.set-chip__count {
		font-size: 0.68rem;
		opacity: 0.5;
	}

	.completion-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.completion-row {
		display: grid;
		grid-template-columns: 6rem 1fr 3rem;
		align-items: center;
		gap: var(--space-3);
	}
	.completion-label {
		font-size: var(--text-xs);
		opacity: 0.7;
	}
	.completion-track {
		background: var(--color-cream);
		border-radius: 6px;
		height: 0.55rem;
		overflow: hidden;
	}
	.completion-fill {
		height: 100%;
		border-radius: 6px;
	}
	.completion-value {
		font-size: var(--text-xs);
		font-weight: 700;
		text-align: right;
	}

	.empty-note {
		opacity: 0.5;
		font-size: var(--text-sm);
	}
	.new-students-list {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.new-student-row {
		display: flex;
		justify-content: space-between;
		font-size: var(--text-sm);
		padding: var(--space-2) 0;
		border-bottom: 1px solid var(--color-cream-deep);
	}
	.new-student-class {
		opacity: 0.5;
		font-size: var(--text-xs);
	}
</style>
