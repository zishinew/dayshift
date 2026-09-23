import { beforeEach, describe, expect, it, vi } from 'vitest';
import { applyLocal, readLocal } from './sync';
import { toSwiftDate, type Snapshot, type Task } from './model';

const userId = 'b732f153-74a9-4be0-9da1-61351720006e';
const task: Task = {
  id: 'ad40b4e6-3f21-4305-9ce7-5cadb79f3db8', title: 'math237 quiz',
  dueDate: toSwiftDate(new Date('2026-09-30T00:00:00Z')),
  createdAt: toSwiftDate(new Date('2026-09-23T00:00:00Z')),
  priority: 'Medium', isComplete: false, isEvent: true,
};

beforeEach(() => {
  const data = new Map<string, string>();
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => { data.set(key, value); },
  });
});

describe('offline change queue', () => {
  it('keeps only the latest pending edit per entity', () => {
    const first: Snapshot = { tasks: [task], classes: [] };
    applyLocal(userId, first);
    applyLocal(userId, { ...first, tasks: [{ ...task, title: 'final quiz' }] });
    const state = readLocal(userId);
    expect(state.pending).toHaveLength(1);
    expect(state.pending[0].payload?.task?.title).toBe('final quiz');
  });

  it('queues deletion as a tombstone', () => {
    applyLocal(userId, { tasks: [task], classes: [] });
    applyLocal(userId, { tasks: [], classes: [] });
    const state = readLocal(userId);
    expect(state.pending).toHaveLength(1);
    expect(state.pending[0].payload).toBeNull();
    expect(state.pending[0].entity_type).toBe('task');
  });
});
