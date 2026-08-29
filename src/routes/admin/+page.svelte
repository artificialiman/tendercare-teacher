<script lang="ts">
	import Crest from '$lib/components/Crest.svelte';
</script>

<svelte:head>
	<title>Tendercare Admin</title>
</svelte:head>

<div class="admin-home">
	<Crest class="admin-home__watermark" />

	<header class="admin-home__header">
		<Crest size="2.75rem" style="color:var(--color-purple-deep);" />
		<div>
			<h1>Admin</h1>
			<p>Staff, roles, and the numbers behind the school.</p>
		</div>
	</header>

	<div class="admin-home__grid">
		<a href="/admin/staff" class="admin-home__button admin-home__button--staff">
			<span class="admin-home__button-label">Staff &amp; Roles</span>
			<span class="admin-home__button-sub">Add, remove, and assign roles to teaching and support staff.</span>
		</a>
		<a href="/admin/analytics" class="admin-home__button admin-home__button--analytics">
			<span class="admin-home__button-label">Analytics</span>
			<span class="admin-home__button-sub">Enrollment, class averages, feed activity, and alumni tracking.</span>
		</a>
	</div>
</div>

<style>
	.admin-home {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		max-width: 1000px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-5);
		font-family: var(--font-sans);
		background: var(--color-white);
	}
	:global(.admin-home__watermark) {
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
	.admin-home__header,
	.admin-home__grid {
		position: relative;
		z-index: 1;
	}
	.admin-home__header {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		margin-bottom: var(--space-10);
	}
	.admin-home__header h1 {
		font-family: var(--font-serif);
		font-size: var(--text-2xl);
		color: var(--color-purple-deep);
		margin: 0 0 0.15rem;
	}
	.admin-home__header p {
		opacity: 0.65;
		margin: 0;
		font-size: var(--text-sm);
	}
	.admin-home__grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
		gap: var(--space-6);
	}
	.admin-home__button {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		justify-content: space-between;
		min-height: 200px;
		padding: var(--space-8) var(--space-6);
		border-radius: var(--radius-lg);
		text-decoration: none;
		color: white;
		position: relative;
		overflow: hidden;
		transition: transform 0.15s ease, box-shadow 0.15s ease;
	}
	.admin-home__button:hover {
		transform: translateY(-2px);
		box-shadow: 0 10px 28px rgba(58, 26, 92, 0.2);
	}
	.admin-home__button--staff {
		background: var(--color-purple-deep);
	}
	.admin-home__button--analytics {
		background: var(--color-ink);
	}
	.admin-home__button-label {
		font-family: var(--font-display);
		font-size: var(--text-3xl);
		letter-spacing: 0.04em;
		color: var(--color-lemon);
		line-height: 1;
	}
	.admin-home__button-sub {
		font-family: var(--font-sans);
		font-size: var(--text-sm);
		color: rgba(255, 255, 255, 0.7);
	}
</style>
