<script lang="ts">
	interface Bar {
		label: string;
		value: number;
	}
	interface Props {
		title: string;
		bars: Bar[];
		color?: string;
		suffix?: string;
	}
	let { title, bars, color = 'var(--color-purple)', suffix = '' }: Props = $props();

	const max = $derived(Math.max(1, ...bars.map((b) => b.value)));
</script>

<div class="barchart">
	<h3 class="barchart__title">{title}</h3>
	{#if bars.length === 0}
		<p class="barchart__empty">No data yet.</p>
	{:else}
		<div class="barchart__rows">
			{#each bars as bar (bar.label)}
				<div class="barchart__row">
					<span class="barchart__label">{bar.label}</span>
					<div class="barchart__track">
						<div
							class="barchart__fill"
							style="width:{(bar.value / max) * 100}%;background:{color};"
						></div>
					</div>
					<span class="barchart__value">{bar.value}{suffix}</span>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.barchart {
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		padding: var(--space-6);
	}
	.barchart__title {
		font-family: var(--font-serif);
		font-size: var(--text-md);
		color: var(--color-purple-deep);
		margin: 0 0 var(--space-5);
	}
	.barchart__empty {
		font-size: var(--text-sm);
		opacity: 0.5;
		margin: 0;
	}
	.barchart__rows {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.barchart__row {
		display: grid;
		grid-template-columns: 7rem 1fr 3rem;
		align-items: center;
		gap: var(--space-3);
	}
	.barchart__label {
		font-family: var(--font-sans);
		font-size: var(--text-xs);
		opacity: 0.7;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.barchart__track {
		background: var(--color-cream);
		border-radius: 6px;
		height: 0.6rem;
		overflow: hidden;
	}
	.barchart__fill {
		height: 100%;
		border-radius: 6px;
		transition: width 0.4s ease;
	}
	.barchart__value {
		font-family: var(--font-sans);
		font-size: var(--text-xs);
		font-weight: 600;
		text-align: right;
	}
</style>
