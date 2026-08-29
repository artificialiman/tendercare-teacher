<script lang="ts">
	import { onMount } from 'svelte';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';
	import BarChart from '$lib/components/BarChart.svelte';

	let loading = $state(true);

	let enrollmentByClass = $state<{ label: string; value: number }[]>([]);
	let staffByType = $state<{ label: string; value: number }[]>([]);
	let classAverages = $state<{ label: string; value: number }[]>([]);
	let repeating = $state(0);
	let pardoned = $state(0);
	let feedByWeek = $state<{ label: string; value: number }[]>([]);
	let alumniTotal = $state(0);
	let alumniRecycled = $state(0);
	let alumniPending = $state(0);

	onMount(load);

	async function load() {
		loading = true;

		const [studentsRes, staffRes, scoresRes, feedRes, archiveRes] = await Promise.all([
			supabase.from('students').select('class_id, active, repeating, repeat_pardoned_at'),
			supabase.from('staff').select('staff_type').eq('active', true),
			supabase.from('scores').select('student_id, ca, exam, students!inner(class_id)'),
			supabase.from('feed_comments').select('created_at'),
			supabase.from('alumni_archive').select('reissued_to')
		]);

		const students = studentsRes.data ?? [];
		const activeStudents = students.filter((s) => s.active);

		const byClass = new Map<string, number>();
		for (const s of activeStudents) {
			byClass.set(s.class_id, (byClass.get(s.class_id) ?? 0) + 1);
		}
		enrollmentByClass = [...byClass.entries()]
			.sort((a, b) => b[1] - a[1])
			.map(([label, value]) => ({ label, value }));

		repeating = activeStudents.filter((s) => s.repeating).length;
		pardoned = students.filter((s) => s.repeat_pardoned_at).length;

		const staffTypeLabels: Record<string, string> = {
			part_time: 'Part-time',
			full_time: 'Full-time',
			corps_member: 'Corps Member'
		};
		const byType = new Map<string, number>();
		for (const s of staffRes.data ?? []) {
			byType.set(s.staff_type, (byType.get(s.staff_type) ?? 0) + 1);
		}
		staffByType = [...byType.entries()].map(([type, value]) => ({
			label: staffTypeLabels[type] ?? type,
			value
		}));

		const scoreRows = (scoresRes.data ?? []) as any[];
		const classTotals = new Map<string, { sum: number; count: number }>();
		for (const row of scoreRows) {
			const cls = row.students?.class_id;
			if (!cls || row.ca == null || row.exam == null) continue;
			const total = Number(row.ca) + Number(row.exam);
			const entry = classTotals.get(cls) ?? { sum: 0, count: 0 };
			entry.sum += total;
			entry.count += 1;
			classTotals.set(cls, entry);
		}
		classAverages = [...classTotals.entries()]
			.map(([label, { sum, count }]) => ({ label, value: Math.round(sum / count) }))
			.sort((a, b) => b.value - a.value);

		const weekBuckets = new Map<string, number>();
		for (const row of feedRes.data ?? []) {
			const d = new Date(row.created_at);
			const weekStart = new Date(d);
			weekStart.setDate(d.getDate() - d.getDay());
			const key = weekStart.toISOString().slice(0, 10);
			weekBuckets.set(key, (weekBuckets.get(key) ?? 0) + 1);
		}
		feedByWeek = [...weekBuckets.entries()]
			.sort((a, b) => a[0].localeCompare(b[0]))
			.slice(-6)
			.map(([label, value]) => ({ label, value }));

		const archive = archiveRes.data ?? [];
		alumniTotal = archive.length;
		alumniRecycled = archive.filter((a) => a.reissued_to).length;
		alumniPending = alumniTotal - alumniRecycled;

		loading = false;
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
		<p>Live from Supabase — refreshes on load.</p>
	</header>

	{#if loading}
		<p class="analytics__loading">Loading…</p>
	{:else}
		<div class="analytics__stats">
			<div class="stat-card">
				<span class="stat-label">Active Students</span>
				<span class="stat-value">{enrollmentByClass.reduce((sum, b) => sum + b.value, 0)}</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Repeating</span>
				<span class="stat-value">{repeating}</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Pardoned (all-time)</span>
				<span class="stat-value">{pardoned}</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Alumni Recycled</span>
				<span class="stat-value">{alumniRecycled} / {alumniTotal}</span>
			</div>
		</div>

		<div class="analytics__grid">
			<BarChart title="Enrollment by Class" bars={enrollmentByClass} color="var(--color-purple)" />
			<BarChart title="Staff by Type" bars={staffByType} color="var(--color-wine)" />
			<BarChart
				title="Class Average (CA + Exam)"
				bars={classAverages}
				color="var(--color-lemon-warm)"
			/>
			<BarChart title="Feed Activity by Week" bars={feedByWeek} color="var(--color-purple-mid)" />
		</div>

		<div class="analytics__alumni-note">
			<strong>{alumniPending}</strong> alumni ID{alumniPending === 1 ? '' : 's'} archived and eligible
			for future recycling once one year has passed since graduation — assign from
			<code>alumni_archive</code> via <code>create_student(..., p_id =&gt; '…')</code> when
			admitting a JSS1 intake or transfer-in.
		</div>
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
	.analytics__stats,
	.analytics__grid,
	.analytics__alumni-note {
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
	.analytics__header p {
		opacity: 0.6;
		margin: 0 0 var(--space-8);
		font-size: var(--text-sm);
	}
	.analytics__loading {
		opacity: 0.6;
		padding: var(--space-8) 0;
	}
	.analytics__stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
		gap: var(--space-4);
		margin-bottom: var(--space-8);
	}
	.stat-card {
		background: var(--color-cream);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		padding: var(--space-4) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.stat-label {
		font-size: var(--text-xs);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		opacity: 0.6;
	}
	.stat-value {
		font-family: var(--font-display);
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		letter-spacing: 0.02em;
	}
	.analytics__grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
		gap: var(--space-6);
		margin-bottom: var(--space-8);
	}
	.analytics__alumni-note {
		font-size: var(--text-sm);
		opacity: 0.7;
		background: var(--color-cream);
		border-radius: var(--radius-md);
		padding: var(--space-4) var(--space-5);
	}
	.analytics__alumni-note code {
		background: var(--color-cream-deep);
		padding: 0.1rem 0.35rem;
		border-radius: 4px;
		font-size: 0.85em;
	}
</style>
