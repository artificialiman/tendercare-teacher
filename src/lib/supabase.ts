import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

// Client-side Supabase client, used with the 'staff' JWT role (see
// supabase/migrations/0002_rls_policies.sql). Writes to `students` from
// this client are the ONLY place a student gets added or removed — every
// other app in the suite only ever reads `students` where active = true.
export const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY);
