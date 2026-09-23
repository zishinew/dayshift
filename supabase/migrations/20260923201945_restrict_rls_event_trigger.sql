-- Supabase's RLS event trigger should run only as an event trigger, not as an
-- exposed RPC callable by anonymous or signed-in clients.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
