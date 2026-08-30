<script lang="ts">
	/**
	 * Any button that changes a student's class/department/status funnels
	 * through this instead of firing on a single click. Direct instruction:
	 * the friction of going through the steps is what makes staff sure
	 * about the decision -- minimum 3 button presses before the action
	 * actually runs, not a single click with a "are you sure" afterthought.
	 */
	interface Props {
		label: string;
		confirmLabel?: string;
		finalLabel?: string;
		variant?: 'primary' | 'danger' | 'neutral';
		disabled?: boolean;
		onconfirm: () => void | Promise<void>;
	}
	let {
		label,
		confirmLabel = `Confirm: ${label}?`,
		finalLabel = 'Yes, do it',
		variant = 'neutral',
		disabled = false,
		onconfirm
	}: Props = $props();

	// step 0 = idle (showing `label`), 1 = showing `confirmLabel`, 2 = showing `finalLabel`.
	// A click at step 2 is the 3rd press overall and is the one that runs onconfirm.
	let step = $state(0);
	let running = $state(false);

	function press() {
		if (disabled || running) return;
		if (step < 2) {
			step += 1;
			return;
		}
		running = true;
		Promise.resolve(onconfirm()).finally(() => {
			running = false;
			step = 0;
		});
	}

	function cancel(e: MouseEvent) {
		e.stopPropagation();
		step = 0;
	}
</script>

<span class="confirm-button-wrap">
	<button
		type="button"
		class="confirm-button confirm-button--{variant}"
		class:is-armed={step > 0}
		{disabled}
		onclick={press}
	>
		{#if running}
			…
		{:else if step === 0}
			{label}
		{:else if step === 1}
			{confirmLabel}
		{:else}
			{finalLabel}
		{/if}
	</button>
	{#if step > 0 && !running}
		<button type="button" class="confirm-button-cancel" onclick={cancel} title="Cancel">×</button>
	{/if}
</span>

<style>
	.confirm-button-wrap {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
	}
	.confirm-button {
		font-size: var(--text-xs);
		font-weight: 600;
		padding: 0.3rem 0.6rem;
		border-radius: var(--radius-sm);
		border: 1px solid transparent;
		cursor: pointer;
		white-space: nowrap;
	}
	.confirm-button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.confirm-button--neutral {
		color: var(--color-purple-deep);
		background: transparent;
		border-color: var(--color-cream-deep);
	}
	.confirm-button--primary {
		color: white;
		background: var(--color-purple-deep);
	}
	.confirm-button--danger {
		color: var(--color-wine);
		background: transparent;
		border-color: var(--color-cream-deep);
	}
	.confirm-button.is-armed {
		box-shadow: 0 0 0 2px var(--color-lemon-warm);
	}
	.confirm-button--danger.is-armed {
		background: var(--color-wine);
		color: white;
		border-color: var(--color-wine);
	}
	.confirm-button-cancel {
		background: none;
		border: none;
		color: var(--color-ash-dark);
		font-size: var(--text-sm);
		cursor: pointer;
		padding: 0 0.25rem;
		line-height: 1;
	}
</style>
