import { describe, expect, it } from 'vitest';
import { interpret } from './commands';
import { fromSwiftDate, matchingTask, toSwiftDate } from './model';

const now = new Date(2026, 8, 23, 9, 0, 0);

describe('mac-compatible data', () => {
  it('encodes dates as seconds since the Apple epoch', () => {
    expect(toSwiftDate(new Date('2001-01-01T00:00:00.000Z'))).toBe(0);
    expect(fromSwiftDate(toSwiftDate(now)).getTime()).toBe(now.getTime());
  });
});

describe('natural-language commands', () => {
  it('adds quiz as an event on a short weekday', () => {
    const command = interpret('i have a math237 quiz next wed', now);
    expect(command.kind).toBe('add');
    if (command.kind === 'add') {
      expect(command.task.isEvent).toBe(true);
      expect(command.task.classCode).toBe('MATH237');
      expect(command.task.title).toContain('quiz');
      expect(fromSwiftDate(command.task.dueDate).getHours()).toBe(0);
    }
  });

  it('adds multiple classes at once', () => {
    expect(interpret('i have classes math237, cs136, stat230', now)).toEqual({
      kind: 'classes', codes: ['MATH237', 'CS136', 'STAT230'],
    });
  });

  it('understands spaced pm', () => {
    const command = interpret('quiz tomorrow at 7 pm', now);
    expect(command.kind).toBe('add');
    if (command.kind === 'add') expect(fromSwiftDate(command.task.dueDate).getHours()).toBe(19);
  });

  it('uses pm for bare early hours and noon for 12', () => {
    for (const [hour, expected] of [[2, 14], [12, 12]]) {
      const command = interpret(`quiz tomorrow at ${hour}`, now);
      expect(command.kind).toBe('add');
      if (command.kind === 'add') expect(fromSwiftDate(command.task.dueDate).getHours()).toBe(expected);
    }
  });

  it('moves and renames existing tasks', () => {
    expect(interpret('rename math237 quiz to final review', now)).toEqual({ kind: 'rename', query: 'math237 quiz', title: 'final review' });
    expect(interpret('move quiz to friday', now).kind).toBe('move');
  });

  it('recognizes repeating weekdays and deletion', () => {
    expect(interpret('make math237 quiz repeat every other tues', now)).toEqual({
      kind: 'repeat', query: 'math237 quiz', rule: { interval: 2, unit: 'week', weekday: 3 },
    });
    expect(interpret('remove the quiz', now)).toEqual({ kind: 'delete', query: 'quiz' });
  });

  it('finds an item even when a delete command mentions its date', () => {
    const added = interpret('quiz next tuesday', now);
    expect(added.kind).toBe('add');
    if (added.kind === 'add') {
      const command = interpret('remove the quiz on next tuesday', now);
      expect(command.kind).toBe('delete');
      if (command.kind === 'delete') expect(matchingTask([added.task], command.query)?.id).toBe(added.task.id);
    }
  });
});
