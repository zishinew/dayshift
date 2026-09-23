import type { Change, ClassItem, ServerChange, Snapshot, Task } from './model';
import { supabase } from './supabase';

type LocalState = { cursor: number; pending: Change[]; snapshot: Snapshot };
const empty = (): LocalState => ({ cursor: 0, pending: [], snapshot: { tasks: [], classes: [] } });
const storageKey = (userId: string) => `dayshift:web:${userId}`;
export function readLocal(userId: string): LocalState {
  try {
    const value = localStorage.getItem(storageKey(userId));
    return value ? JSON.parse(value) as LocalState : empty();
  } catch { return empty(); }
}
function saveLocal(userId: string, state: LocalState) {
  localStorage.setItem(storageKey(userId), JSON.stringify(state));
}
export function applyLocal(userId: string, snapshot: Snapshot): LocalState {
  const state = readLocal(userId);
  const changes: Change[] = [];
  const compare = <T extends Task | ClassItem>(kind: 'task' | 'class', before: T[], after: T[]) => {
    const oldItems = new Map(before.map(item => [item.id, item]));
    const newItems = new Map(after.map(item => [item.id, item]));
    for (const id of new Set([...oldItems.keys(), ...newItems.keys()])) {
      if (JSON.stringify(oldItems.get(id)) === JSON.stringify(newItems.get(id))) continue;
      const item = newItems.get(id);
      changes.push({
        change_id: crypto.randomUUID(), user_id: userId, entity_type: kind, entity_id: id,
        payload: item ? kind === 'task' ? { task: item as Task } : { classItem: item as ClassItem } : null,
      });
    }
  };
  compare('task', state.snapshot.tasks, snapshot.tasks);
  compare('class', state.snapshot.classes, snapshot.classes);
  const changedKeys = new Set(changes.map(c => `${c.entity_type}:${c.entity_id}`));
  state.pending = state.pending.filter(c => !changedKeys.has(`${c.entity_type}:${c.entity_id}`)).concat(changes);
  state.snapshot = snapshot;
  saveLocal(userId, state);
  return state;
}

function applyRows(snapshot: Snapshot, rows: ServerChange[], pending: Change[]): Snapshot {
  const blocked = new Set(pending.map(c => `${c.entity_type}:${c.entity_id}`));
  const tasks = new Map(snapshot.tasks.map(item => [item.id, item]));
  const classes = new Map(snapshot.classes.map(item => [item.id, item]));
  for (const row of rows) {
    if (blocked.has(`${row.entity_type}:${row.entity_id}`)) continue;
    if (row.entity_type === 'task') {
      const task = row.payload?.task;
      if (task) tasks.set(row.entity_id, task); else tasks.delete(row.entity_id);
    } else {
      const classItem = row.payload?.classItem;
      if (classItem) classes.set(row.entity_id, classItem); else classes.delete(row.entity_id);
    }
  }
  return { tasks: [...tasks.values()], classes: [...classes.values()] };
}

export async function syncNow(userId: string): Promise<LocalState> {
  if (!supabase) throw new Error('supabase is not configured');
  // Download first, like the Mac client. Pending local edits take precedence until uploaded.
  for (;;) {
    const cursor = readLocal(userId).cursor;
    const { data, error } = await supabase.from('dayshift_changes')
      .select('sequence,entity_type,entity_id,payload')
      .eq('user_id', userId).gt('sequence', cursor).order('sequence', { ascending: true }).limit(500);
    if (error) throw error;
    const rows = (data ?? []) as ServerChange[];
    if (!rows.length) break;
    const state = readLocal(userId);
    state.snapshot = applyRows(state.snapshot, rows.filter(row => row.sequence > state.cursor), state.pending);
    state.cursor = Math.max(state.cursor, rows.at(-1)!.sequence);
    saveLocal(userId, state);
    if (rows.length < 500) break;
  }
  while (readLocal(userId).pending.length) {
    const state = readLocal(userId);
    const batch = state.pending.slice(0, 100);
    const { error } = await supabase.from('dayshift_changes').upsert(batch, {
      onConflict: 'user_id,change_id', ignoreDuplicates: true,
    });
    if (error) throw error;
    const latest = readLocal(userId);
    const uploaded = new Set(batch.map(change => change.change_id));
    latest.pending = latest.pending.filter(change => !uploaded.has(change.change_id));
    saveLocal(userId, latest);
  }
  // Include server-assigned sequences from this upload and any concurrent devices.
  for (;;) {
    const cursor = readLocal(userId).cursor;
    const { data, error } = await supabase.from('dayshift_changes')
      .select('sequence,entity_type,entity_id,payload')
      .eq('user_id', userId).gt('sequence', cursor).order('sequence', { ascending: true }).limit(500);
    if (error) throw error;
    const rows = (data ?? []) as ServerChange[];
    if (!rows.length) break;
    const state = readLocal(userId);
    state.snapshot = applyRows(state.snapshot, rows.filter(row => row.sequence > state.cursor), state.pending);
    state.cursor = Math.max(state.cursor, rows.at(-1)!.sequence);
    saveLocal(userId, state);
    if (rows.length < 500) break;
  }
  return readLocal(userId);
}
