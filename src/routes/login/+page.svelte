<script lang="ts">
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';
	import Crest from '$lib/components/Crest.svelte';

	/**
	 * Interim login — two fixed accounts (staff@tendercare.local,
	 * admin@tendercare.local), passwords set via Supabase Auth directly
	 * (see supabase/migrations/0003_staff_auth_roles.sql for how the
	 * 'staff'/'admin' RLS role claim gets attached to each).
	 *
	 * This is a placeholder auth UI, not a placeholder auth mechanism —
	 * the session it creates is a real Supabase Auth session, and RLS
	 * genuinely enforces the role. What's temporary is *who* can get a
	 * session (two shared logins, not per-staff accounts) and *how*
	 * (a role dropdown instead of real identity) — both replaceable
	 * later without touching RLS or roster.ts.
	 */

	let role = $state<'staff' | 'admin'>('staff');
	let password = $state('');
	let loading = $state(false);
	let error = $state('');

	const ROLE_EMAILS: Record<'staff' | 'admin', string> = {
		staff: 'staff@tendercare.local',
		admin: 'admin@tendercare.local'
	};

	async function handleLogin(e: SubmitEvent) {
		e.preventDefault();
		loading = true;
		error = '';
		const { error: authError } = await supabase.auth.signInWithPassword({
			email: ROLE_EMAILS[role],
			password
		});
		loading = false;
		if (authError) {
			error = 'Incorrect password.';
			return;
		}
		goto('/');
	}
</script>

<svelte:head>
	<title>Sign in — Tendercare Teacher Dashboard</title>
</svelte:head>

<div class="login-page">
	<Crest class="login-watermark" aria-hidden="true" />
	<div class="login-card">
		<Crest class="login-crest" size="3rem" />
		<h1>Tendercare Staff Sign-in</h1>
		<form onsubmit={handleLogin}>
			<label>
				<span>I am signing in as</span>
				<select bind:value={role}>
					<option value="staff">Staff</option>
					<option value="admin">Admin</option>
				</select>
			</label>
			<label>
				<span>Password</span>
				<input type="password" bind:value={password} required autocomplete="current-password" />
			</label>
			{#if error}
				<p class="login-error" role="alert">{error}</p>
			{/if}
			<button type="submit" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
		</form>
	</div>
</div>

<style>
	.login-page {
		position: relative;
		overflow: hidden;
		min-height: 100dvh;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-6);
		font-family: var(--font-sans);
		background: var(--color-cream);
	}
	/* Same large, faint, centered letterhead-style watermark used across
	   the result sheets and the portal/web directory pages -- this app
	   was the one place in the suite missing it. */
	:global(.login-watermark) {
		position: absolute;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		width: min(70vw, 640px);
		height: auto;
		color: var(--color-purple-deep);
		opacity: 0.045;
		pointer-events: none;
		z-index: 0;
	}
	.login-card {
		position: relative;
		z-index: 1;
		width: 100%;
		max-width: 360px;
		padding: var(--space-8);
		background: var(--color-white);
		border: 1px solid var(--color-cream-deep);
		border-radius: var(--radius-lg);
		box-shadow: 0 12px 40px rgba(58, 26, 92, 0.1);
		text-align: center;
	}
	:global(.login-crest) {
		color: var(--color-purple-deep);
		margin: 0 auto var(--space-4);
	}
	h1 {
		font-size: var(--text-lg);
		margin: 0 0 var(--space-5);
		font-family: var(--font-serif);
		font-weight: 600;
		color: var(--color-purple-deep);
	}
	form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		text-align: left;
	}
	label {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		font-size: var(--text-xs);
		font-family: var(--font-sans);
		color: var(--color-ink-soft);
	}
	select,
	input {
		padding: var(--space-3);
		border: 1px solid var(--color-ash-light);
		border-radius: var(--radius-md);
		font-size: var(--text-base);
		font-family: var(--font-sans);
	}
	select:focus,
	input:focus {
		outline: none;
		border-color: var(--color-purple);
		box-shadow: 0 0 0 3px var(--color-purple-ghost);
	}
	button {
		padding: var(--space-3);
		border-radius: var(--radius-md);
		border: none;
		background: var(--color-purple-deep);
		color: var(--color-white);
		font-weight: 600;
		font-family: var(--font-sans);
		cursor: pointer;
	}
	button:hover:not(:disabled) {
		background: var(--color-purple);
	}
	button:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.login-error {
		color: var(--color-wine);
		font-size: var(--text-xs);
		margin: 0;
	}
</style>
