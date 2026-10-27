// Deletes the caller's account and, through ON DELETE CASCADE, all of their data.
// Required by the App Store / Google Play (in-app account deletion) and by GDPR.
// Store subscriptions are managed by Apple/Google: the app tells the user to cancel there.

import { corsHeaders, json } from '../_shared/http.ts';
import { adminClient } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, cors);

  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'unauthorized' }, 401, cors);

  const admin = adminClient();
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return json({ error: 'unauthorized' }, 401, cors);

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    console.error('delete-account failed', deleteError);
    return json({ error: 'delete_failed' }, 500, cors);
  }
  return json({ status: 'deleted' }, 200, cors);
});
