<script lang="ts">
	import Crest from '$lib/components/Crest.svelte';
</script>

<svelte:head>
	<title>Tendercare Staff Dashboard</title>
</svelte:head>

<div class="landing">
	<Crest class="landing-crest-watermark" aria-hidden="true" />
	<Crest class="landing-crest" size="4.5rem" />
	<h1>Tendercare Staff Dashboard</h1>
	<p>Roster management, scores, and academic records for staff and admin.</p>
	<a class="landing-cta" href="/roster">Go to Roster →</a>
</div>

<style>
	.landing {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		text-align: center;
		gap: 0.5rem;
		padding: 2rem 1.5rem;
		font-family: var(--font-sans, system-ui);
	}
	/* Letterhead-style background watermark, matching the pattern already
	   used on the portal's directory/result pages -- large, faint,
	   centered, non-interactive, sits behind everything else. */
	:global(.landing-crest-watermark) {
		position: absolute;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		width: min(70vw, 640px);
		height: auto;
		color: var(--color-purple-deep, #3a1a5c);
		opacity: 0.045;
		pointer-events: none;
		z-index: 0;
	}
	:global(.landing-crest) {
		position: relative;
		z-index: 1;
		color: var(--color-purple-deep, #3a1a5c);
		margin-bottom: 0.5rem;
	}
	.landing > :global(h1),
	.landing > :global(p),
	.landing > :global(.landing-cta) {
		position: relative;
		z-index: 1;
	}
	h1 {
		font-family: var(--font-serif, serif);
		font-size: 1.5rem;
		margin: 0;
	}
	p {
		opacity: 0.65;
		max-width: 42ch;
		margin: 0 0 0.5rem;
	}
	.landing-cta {
		display: inline-block;
		margin-top: 0.75rem;
		padding: 0.7rem 1.4rem;
		border-radius: 999px;
		background: var(--color-purple, #6b46c1);
		color: white;
		text-decoration: none;
		font-weight: 600;
		font-size: 0.9rem;
	}
</style>
