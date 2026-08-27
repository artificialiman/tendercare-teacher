<script lang="ts">
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabase';

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
		goto('/roster');
	}
</script>

<svelte:head>
	<title>Sign in — Tendercare Teacher Dashboard</title>
</svelte:head>

<div class="login-page">
	<div class="login-card">
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
		min-height: 100dvh;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 1.5rem;
		font-family: var(--font-sans, system-ui);
	}
	.login-card {
		width: 100%;
		max-width: 360px;
		padding: 2rem;
		border: 1px solid #eee;
		border-radius: 12px;
	}
	h1 {
		font-size: 1.15rem;
		margin: 0 0 1.25rem;
		font-family: var(--font-serif, serif);
	}
	form {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		font-size: 0.85rem;
	}
	select,
	input {
		padding: 0.6rem 0.7rem;
		border: 1px solid #ccc;
		border-radius: 8px;
		font-size: 0.95rem;
	}
	button {
		padding: 0.65rem;
		border-radius: 8px;
		border: none;
		background: var(--color-purple, #6b46c1);
		color: white;
		font-weight: 600;
		cursor: pointer;
	}
	button:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.login-error {
		color: #900;
		font-size: 0.85rem;
		margin: 0;
	}
</style>
