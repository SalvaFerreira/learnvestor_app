import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { requireEnv } from './http.ts';

/**
 * Service-role client. Bypasses RLS: use only in trusted server code and never return
 * its results to a caller without filtering them first.
 * SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the Edge Runtime.
 */
export function adminClient(): SupabaseClient {
  return createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
