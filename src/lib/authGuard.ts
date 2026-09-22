import { supabase } from '$lib/supabase';
import { goto } from '$app/navigation';

export type SessionCheck = { ok: true; role: string | null } | { ok: false };

/**
 * The same "no session -> redirect to /login" check attendance, score,
 * and roster's pages already each do independently in onMount -- this
 * exists so /admin's pages (which had none of this at all until now,
 * reachable by direct navigation with zero guard) get the identical
 * behavior, not a new pattern. Not wired into those three existing
 * pages retroactively in this pass -- they already work, this only
 * closes the actual gap.
 *
 * Reads session.user.app_metadata.role directly, same field
 * src/routes/+page.svelte already reads for its welcome message --
 * this is Supabase's natively-included nested app_metadata, not the
 * custom top-level JWT claim the Custom Access Token Hook (0018-0020)
 * promotes for server-side RLS/RPC checks. Client-side role display
 * and server-side RLS enforcement are deliberately two separate paths
 * here; this guard is UX only (a clean redirect instead of a raw RLS
 * error), never the actual security boundary -- RLS remains that,
 * unchanged by this file.
 */
export async function requireSession(): Promise<SessionCheck> {
	const {
		data: { session }
	} = await supabase.auth.getSession();
	if (!session) {
		goto('/login');
		return { ok: false };
	}
	const role = (session.user?.app_metadata?.role as string) ?? null;
	return { ok: true, role };
}

/**
 * For admin-only pages/actions: session must exist AND role must be
 * 'admin'. A valid 'staff' session is authenticated but not authorized
 * here -- redirects to the dashboard (/), not /login, since the actual
 * problem is permission, not being logged in.
 */
export async function requireAdmin(): Promise<SessionCheck> {
	const check = await requireSession();
	if (!check.ok) return check;
	if (check.role !== 'admin') {
		goto('/');
		return { ok: false };
	}
	return check;
}
