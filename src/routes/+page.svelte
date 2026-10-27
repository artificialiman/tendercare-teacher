<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';
	import {
		listActiveStaff,
		getActiveStaff,
		setActiveStaffId,
		clearActiveStaffId,
		listMyAssignments,
		type StaffMember,
		type Assignment
	} from '$lib/teacherIdentity';
	import { getCurrentTerm, sheetProgress, type SheetProgress } from '$lib/scores';

	let checkingSession = $state(true);

	// picker state (shown when no staff identity is picked yet)
	let picking = $state(false);
	let pickerStaff = $state<StaffMember[]>([]);
	let pickerError = $state('');

	// dashboard state (shown once a staff identity is picked)
	let activeStaff = $state<StaffMember | null>(null);
	let assignments = $state<Assignment[]>([]);
	let progressByAssignment = $state<Map<string, SheetProgress>>(new Map());
	let termLabel = $state('');
	let loadingDashboard = $state(true);
	let dashboardError = $state('');

	onMount(async () => {
		const {
			data: { session }
		} = await supabase.auth.getSession();
		if (!session) {
			goto('/login');
			return;
		}
		checkingSession = false;
		await loadIdentity();
	});

	async function loadIdentity() {
		try {
			const staff = await getActiveStaff();
			if (!staff) {
				picking = true;
				pickerStaff = await listActiveStaff();
				return;
			}
			activeStaff = staff;
			await loadDashboard(staff.id);
		} catch (e) {
			pickerError = e instanceof Error ? e.message : 'Failed to load staff list';
			picking = true;
		}
	}

	async function pick(staff: StaffMember) {
		setActiveStaffId(staff.id);
		activeStaff = staff;
		picking = false;
		await loadDashboard(staff.id);
	}

	function switchTeacher() {
		clearActiveStaffId();
		activeStaff = null;
		assignments = [];
		progressByAssignment = new Map();
		loadIdentity();
	}

	async function loadDashboard(staffId: string) {
		loadingDashboard = true;
		dashboardError = '';
		try {
			const term = await getCurrentTerm();
			termLabel = term ? `${term.academic_year} · Term ${term.term_number}` : 'No current term set';

			assignments = await listMyAssignments(staffId);

			if (term && assignments.length > 0) {
				const entries = await Promise.all(
					assignments.map(async (a) => {
						const p = await sheetProgress(a.subject_id, a.class_id, term.id);
						return [`${a.subject_id}:${a.class_id}`, p] as const;
					})
				);
				progressByAssignment = new Map(entries);
			}
		} catch (e) {
			dashboardError =
				e instanceof Error
					? e.message
					: 'Failed to load assignments — staff_subjects/staff_classes may not exist on this project yet.';
		} finally {
			loadingDashboard = false;
		}
	}

	const inProgress = $derived(
		assignments
			.map((a) => ({ a, p: progressByAssignment.get(`${a.subject_id}:${a.class_id}`) }))
			.filter((row): row is { a: Assignment; p: SheetProgress } => !!row.p && row.p.filled > 0)
	);
</script>

<svelte:head>
	<title>Tendercare Teacher</title>
</svelte:head>

{#if checkingSession}
	<p class="session-check">Checking session…</p>
{:else if picking}
	<div class="landing">
		<Crest class="landing-watermark" size="min(70vw, 640px)" />
		<header class="landing-header">
			<Crest class="landing-crest" size="3.5rem" />
			<h1>Tendercare Teacher</h1>
			<p>Pick your name to open your dashboard.</p>
		</header>
		{#if pickerError}
			<div class="page-error" role="alert">{pickerError}</div>
		{/if}
		<div class="teacher-picker">
			{#each pickerStaff as s (s.id)}
				<button class="teacher-picker-btn" onclick={() => pick(s)}>
					<span>
						<span class="teacher-picker-name">{s.full_name}</span><br />
						<span class="teacher-picker-role"
							>{s.staff_type.replace('_', '-')}{s.is_class_teacher ? ' · Class teacher' : ''}</span
						>
					</span>
					<span class="teacher-picker-arrow">&rarr;</span>
				</button>
			{/each}
			{#if pickerStaff.length === 0 && !pickerError}
				<p class="progress-empty">No active staff on file yet — ask admin to add you.</p>
			{/if}
		</div>
	</div>
{:else if activeStaff}
	<div class="dashboard">
		<Crest class="dashboard-watermark" size="min(60vw, 560px)" />

		<div class="shell-bar">
			<div class="shell-left">
				<Crest size="2.1rem" style="color:var(--color-purple-light)" />
				<div class="shell-titles">
					<div class="shell-title">Tendercare Teacher</div>
					<div class="shell-subtitle">{termLabel}</div>
				</div>
			</div>
			<div class="shell-right">
				<span class="shell-role-pill">{activeStaff.full_name}</span>
				<button class="shell-switch" onclick={switchTeacher}>Switch</button>
			</div>
		</div>

		<section class="welcome-section">
			<h1>Welcome back, {activeStaff.full_name}</h1>
			<p>
				{assignments.length} subject-class assignment{assignments.length === 1 ? '' : 's'}{activeStaff.is_class_teacher
					? ' · Class teacher'
					: ''}.
			</p>
		</section>

		{#if dashboardError}
			<div class="page-error" role="alert">{dashboardError}</div>
		{/if}

		<div class="mode-grid">
			<a class="mode-card" href="/attendance">
				<span class="mode-card-icon">👥</span>
				<span class="mode-card-title">Attendance &amp; Bio Edit</span>
				<span class="mode-card-desc"
					>Add or remove students in your own classes, attach a portrait, and edit per-term remarks.</span
				>
			</a>
			<a class="mode-card" href="/score">
				<span class="mode-card-icon">📝</span>
				<span class="mode-card-title">Score Entry</span>
				<span class="mode-card-desc"
					>Open a subject-class broadsheet. CA + Exam auto-totals, live row/column highlight.</span
				>
			</a>
		</div>

		<p class="section-label">Broadsheets in progress</p>
		<div class="progress-list">
			{#if loadingDashboard}
				<p class="progress-empty">Loading…</p>
			{:else if inProgress.length === 0}
				<p class="progress-empty">Nothing started yet — open Score Entry to begin a sheet.</p>
			{:else}
				{#each inProgress as { a, p } (a.subject_id + a.class_id)}
					<a
						class="progress-row"
						href={`/score/sheet?subject=${a.subject_id}&class=${encodeURIComponent(a.class_id)}`}
					>
						<span class="progress-row-label">
							<span class="progress-row-title">{a.subject_name} · {a.class_label}</span>
							<span class="progress-row-sub">{p.filled} of {p.total} students scored</span>
						</span>
						<span class="progress-bar-track"
							><span class="progress-bar-fill" style="width:{p.pct}%"></span></span
						>
						<span class="progress-pct">{p.pct}%</span>
						<span class="progress-continue">Continue &rarr;</span>
					</a>
				{/each}
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

	.landing {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: var(--space-16) var(--space-5);
		background: var(--color-cream);
		font-family: var(--font-sans);
	}
	:global(.landing-watermark) {
		position: absolute;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		color: var(--color-purple-deep);
		opacity: 0.045;
		pointer-events: none;
		z-index: 0;
	}
	.landing-header {
		position: relative;
		z-index: 1;
		text-align: center;
		max-width: 46ch;
		margin-bottom: var(--space-8);
	}
	:global(.landing-crest) {
		color: var(--color-purple-deep);
		margin: 0 auto var(--space-3);
		display: block;
	}
	.landing-header h1 {
		font-family: var(--font-serif);
		font-weight: 400;
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		margin: 0 0 var(--space-2);
	}
	.landing-header p {
		opacity: 0.7;
		font-size: var(--text-sm);
		margin: 0;
	}
	.teacher-picker {
		position: relative;
		z-index: 1;
		width: 100%;
		max-width: 480px;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.teacher-picker-btn {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		padding: 0.85rem 1.1rem;
		text-align: left;
		cursor: pointer;
	}
	.teacher-picker-btn:hover {
		border-color: var(--color-purple-light);
	}
	.teacher-picker-name {
		font-family: var(--font-serif);
		font-weight: 600;
		font-size: var(--text-md);
		color: var(--color-ink);
	}
	.teacher-picker-role {
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
	}
	.teacher-picker-arrow {
		color: var(--color-purple-light);
		font-size: var(--text-lg);
	}

	.dashboard {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		max-width: 980px;
		margin: 0 auto;
		font-family: var(--font-sans);
		background: var(--color-offwhite);
	}
	:global(.dashboard-watermark) {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		color: var(--color-purple-deep);
		opacity: 0.035;
		pointer-events: none;
		z-index: 0;
	}
	.shell-bar {
		position: relative;
		z-index: 1;
		background: var(--color-purple-deep);
		color: var(--color-white);
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.75rem 1.5rem;
	}
	.shell-left {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}
	.shell-titles {
		line-height: 1.25;
	}
	.shell-title {
		font-family: var(--font-serif);
		font-size: 1rem;
		font-weight: 600;
	}
	.shell-subtitle {
		font-size: 0.68rem;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		opacity: 0.55;
	}
	.shell-right {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}
	.shell-role-pill {
		background: var(--color-purple);
		color: var(--color-white);
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		padding: 0.35rem 0.85rem;
		border-radius: var(--radius-full);
	}
	.shell-switch {
		border: 1px solid rgba(255, 255, 255, 0.3);
		color: var(--color-white);
		background: none;
		font-size: 0.75rem;
		font-weight: 600;
		padding: 0.4rem 0.9rem;
		border-radius: var(--radius-md);
		cursor: pointer;
	}
	.shell-switch:hover {
		background: rgba(255, 255, 255, 0.08);
	}

	.welcome-section,
	.page-error,
	.mode-grid,
	.section-label,
	.progress-list {
		position: relative;
		z-index: 1;
		max-width: 900px;
		margin-left: auto;
		margin-right: auto;
		padding-left: var(--space-5);
		padding-right: var(--space-5);
	}
	.welcome-section {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		padding: var(--space-6);
		margin-top: var(--space-6);
		margin-bottom: var(--space-6);
	}
	.welcome-section h1 {
		font-family: var(--font-serif);
		font-weight: 400;
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		margin: 0 0 var(--space-1);
	}
	.welcome-section p {
		opacity: 0.7;
		font-size: var(--text-sm);
		margin: 0;
		max-width: 60ch;
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
	.mode-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-4);
		margin-bottom: var(--space-8);
	}
	@media (max-width: 620px) {
		.mode-grid {
			grid-template-columns: 1fr;
		}
	}
	.mode-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		text-align: left;
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		padding: var(--space-6);
		text-decoration: none;
		color: inherit;
		transition:
			transform 0.2s ease,
			box-shadow 0.2s ease,
			border-color 0.2s ease;
	}
	.mode-card:hover {
		transform: translateY(-2px);
		box-shadow: var(--shadow-md);
		border-color: var(--color-purple-light);
	}
	.mode-card-icon {
		font-size: 1.6rem;
	}
	.mode-card-title {
		font-family: var(--font-serif);
		font-weight: 600;
		font-size: 1.3rem;
		color: var(--color-ink);
	}
	.mode-card-desc {
		font-size: var(--text-sm);
		color: var(--color-ash-dark);
		line-height: 1.5;
	}
	.section-label {
		font-size: var(--text-xs);
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-purple);
		margin: 0 auto var(--space-3);
	}
	.progress-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding-bottom: var(--space-12);
	}
	.progress-row {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-md);
		padding: var(--space-3) var(--space-4);
		text-decoration: none;
		color: inherit;
	}
	.progress-row-label {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.progress-row-title {
		font-size: var(--text-sm);
		font-weight: 600;
	}
	.progress-row-sub {
		font-size: var(--text-xs);
		color: var(--color-ash-dark);
	}
	.progress-bar-track {
		width: 120px;
		height: 8px;
		background: var(--color-cream-deep);
		border-radius: var(--radius-full);
		overflow: hidden;
		flex-shrink: 0;
	}
	.progress-bar-fill {
		height: 100%;
		background: var(--color-purple);
		border-radius: var(--radius-full);
	}
	.progress-pct {
		width: 3.2rem;
		text-align: right;
		font-size: var(--text-xs);
		font-weight: 700;
		color: var(--color-purple-deep);
		flex-shrink: 0;
	}
	.progress-empty {
		font-size: var(--text-sm);
		color: var(--color-ash-dark);
		padding: var(--space-4) 0;
	}
	.progress-continue {
		font-size: var(--text-xs);
		font-weight: 600;
		color: var(--color-purple-deep);
		flex-shrink: 0;
	}
</style>
