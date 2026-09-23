-- An append-only log gives every device the same order of edits, including
-- deletions. Client-generated change IDs make retries safe after a disconnect.
create table public.dayshift_changes (
    sequence bigint generated always as identity primary key,
    change_id uuid not null,
    user_id uuid not null references auth.users(id) on delete cascade,
    entity_type text not null check (entity_type in ('task', 'class')),
    entity_id uuid not null,
    payload jsonb,
    created_at timestamptz not null default now(),
    unique (user_id, change_id)
);

create index dayshift_changes_user_sequence_idx
    on public.dayshift_changes (user_id, sequence);

alter table public.dayshift_changes enable row level security;
revoke all on public.dayshift_changes from anon, authenticated;
grant select, insert on public.dayshift_changes to authenticated;
grant usage on sequence public.dayshift_changes_sequence_seq to authenticated;

create policy "read own changes"
    on public.dayshift_changes for select to authenticated
    using ((select auth.uid()) = user_id);

create policy "append own changes"
    on public.dayshift_changes for insert to authenticated
    with check ((select auth.uid()) = user_id);
