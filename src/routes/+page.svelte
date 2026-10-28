<script lang="ts">
	import Crest from '$lib/components/Crest.svelte';
	import { students, classes, currentTerm } from '$lib/teacherData';

	// Read straight from the hardcoded data -- no session, no fetch.
	const activeStudents = students.filter((s) => s.active).length;
	const classCount = classes.length;
	const repeatingCount = students.filter((s) => s.repeating).length;
	const currentTermLabel = `${currentTerm.academic_year} · Term ${currentTerm.term_number}`;
</script>

<svelte:head>
	<title>Tendercare Staff Dashboard</title>
</svelte:head>

<div class="dashboard">
	<Crest class="dashboard-watermark" />

	<header class="dashboard-header">
		<Crest class="dashboard-crest" size="2.75rem" />
		<div>
			<h1>Welcome back.</h1>
			<p>Roster, records, and results for Tendercare Comprehensive College.</p>
		</div>
	</header>

	<div class="stats-grid">
		<div class="stat-card">
			<span class="stat-label">Active Students</span>
			<span class="stat-value">{activeStudents}</span>
		</div>
		<div class="stat-card">
			<span class="stat-label">Classes</span>
			<span class="stat-value">{classCount}</span>
		</div>
		<div class="stat-card">
			<span class="stat-label">Current Term</span>
			<span class="stat-value stat-value--text">{currentTermLabel}</span>
		</div>
		<div class="stat-card">
			<span class="stat-label">Repeating</span>
			<span class="stat-value">{repeatingCount}</span>
		</div>
	</div>

	<div class="feature-grid">
		<a href="/attendance" class="feature-card feature-card--live">
			<span class="feature-icon">👥</span>
			<h3>Attendance & Bio Edit</h3>
			<p>Add or remove students by class, link a portrait, review repeat status and remarks.</p>
		</a>

		<a href="/score" class="feature-card feature-card--live">
			<span class="feature-icon">📝</span>
			<h3>Score Entry</h3>
			<p>Enter CA and Exam scores per subject, per class.</p>
		</a>

		<div class="feature-card feature-card--soon" aria-disabled="true">
			<span class="feature-icon">📚</span>
			<h3>Lesson Notes &amp; Materials</h3>
			<p>Teaching materials and curriculum guides. Coming soon — not built yet.</p>
			<span class="soon-badge">Coming soon</span>
		</div>
	</div>
</div>

<style>
	.dashboard {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		max-width: 1000px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
	}
	:global(.dashboard-watermark) {
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
	.dashboard-header,
	.stats-grid,
	.feature-grid {
		position: relative;
		z-index: 1;
	}
	.dashboard-header {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		margin-bottom: var(--space-8);
	}
	:global(.dashboard-crest) {
		color: var(--color-purple-deep);
		flex-shrink: 0;
	}
	.dashboard-header h1 {
		font-family: var(--font-serif);
		font-size: var(--text-xl);
		color: var(--color-purple-deep);
		font-weight: 600;
		margin: 0 0 0.15rem;
		text-transform: capitalize;
	}
	.dashboard-header p {
		opacity: 0.65;
		margin: 0;
		font-size: var(--text-sm);
	}
	.stats-grid {
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
	.stat-value--text {
		font-family: var(--font-sans);
		font-size: var(--text-md);
		font-weight: 600;
	}
	.feature-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: var(--space-5);
	}
	.feature-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-6);
		border-radius: var(--radius-lg);
		border: 1px solid var(--color-cream-deep);
		text-decoration: none;
		color: inherit;
		position: relative;
	}
	.feature-card--live {
		background: var(--color-white);
		box-shadow: 0 2px 10px rgba(58, 26, 92, 0.06);
		cursor: pointer;
		transition: box-shadow 0.15s ease, transform 0.15s ease;
	}
	.feature-card--live:hover {
		box-shadow: 0 8px 24px rgba(58, 26, 92, 0.14);
		transform: translateY(-2px);
	}
	.feature-card--soon {
		background: var(--color-cream);
		opacity: 0.7;
	}
	.feature-icon {
		font-size: 1.6rem;
	}
	.feature-card h3 {
		font-family: var(--font-serif);
		color: var(--color-purple-deep);
		font-size: var(--text-md);
		margin: 0;
	}
	.feature-card p {
		font-size: var(--text-sm);
		opacity: 0.65;
		margin: 0;
	}
	.soon-badge {
		position: absolute;
		top: var(--space-4);
		right: var(--space-4);
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		background: var(--color-ash-light);
		color: var(--color-ink-soft);
		padding: 0.2rem 0.5rem;
		border-radius: 20px;
		font-weight: 600;
	}
</style>
