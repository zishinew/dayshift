export type Priority = 'High' | 'Medium' | 'Low';
export type RepeatUnit = 'day' | 'week' | 'month';
export type RepeatRule = { interval: number; unit: RepeatUnit; weekday?: number | null };
export type Task = {
  id: string;
  title: string;
  dueDate: number; // Swift JSONEncoder: seconds since 2001-01-01.
  priority: Priority;
  isComplete: boolean;
  createdAt: number;
  classCode?: string | null;
  repeatRule?: RepeatRule | null;
  isEvent: boolean;
};
export type ClassItem = { id: string; code: string; name: string };
export type Snapshot = { tasks: Task[]; classes: ClassItem[] };
export type Change = {
  change_id: string;
  user_id: string;
  entity_type: 'task' | 'class';
  entity_id: string;
  payload: { task?: Task; classItem?: ClassItem } | null;
};
export type ServerChange = Pick<Change, 'entity_type' | 'entity_id' | 'payload'> & { sequence: number };

const appleEpoch = Date.UTC(2001, 0, 1);
export const toSwiftDate = (date: Date) => (date.getTime() - appleEpoch) / 1000;
export const fromSwiftDate = (value: number) => new Date(appleEpoch + value * 1000);
export const startOfDay = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());
export const dayKey = (date: Date) => `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
export const dateOf = (task: Task) => fromSwiftDate(task.dueDate);
export const isTimed = (task: Task) => {
  const date = dateOf(task);
  return date.getHours() !== 0 || date.getMinutes() !== 0;
};
export const looksLikeEvent = (title: string) => /\b(quiz(?:zes)?|test(?:s)?|exam(?:s)?|midterm(?:s)?|final(?:s)?|assessment(?:s)?|presentation(?:s)?|appointment(?:s)?|meeting(?:s)?|interview(?:s)?|lecture(?:s)?|concert(?:s)?|flight(?:s)?)\b/i.test(title);

export function nextOccurrence(task: Task): Task | null {
  const rule = task.repeatRule;
  if (!rule) return null;
  const date = dateOf(task);
  if (rule.weekday != null) {
    const target = (rule.weekday + 6) % 7; // Swift 1 = Sunday; JS 0 = Sunday.
    const days = (target - date.getDay() + 7) % 7 || 7 * rule.interval;
    date.setDate(date.getDate() + days);
  } else if (rule.unit === 'day') date.setDate(date.getDate() + rule.interval);
  else if (rule.unit === 'week') date.setDate(date.getDate() + 7 * rule.interval);
  else date.setMonth(date.getMonth() + rule.interval);
  return { ...task, id: crypto.randomUUID(), dueDate: toSwiftDate(date), isComplete: false, createdAt: toSwiftDate(new Date()) };
}

export function repeatLabel(rule: RepeatRule): string {
  const weekdays = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
  if (rule.weekday != null) {
    const name = weekdays[Math.max(1, Math.min(7, rule.weekday)) - 1];
    return rule.interval === 1 ? `every ${name}` : rule.interval === 2 ? `every other ${name}` : `every ${rule.interval} weeks on ${name}`;
  }
  return `every ${rule.interval} ${rule.unit}${rule.interval === 1 ? '' : 's'}`;
}

export function sortedTasks(tasks: Task[], sort: SortMode): Task[] {
  return [...tasks].sort((a, b) => {
    if (sort === 'alphabetical') return a.title.localeCompare(b.title);
    if (sort === 'priority') return (['High', 'Medium', 'Low'].indexOf(a.priority) - ['High', 'Medium', 'Low'].indexOf(b.priority)) || a.dueDate - b.dueDate;
    if (sort === 'added') return b.createdAt - a.createdAt;
    return a.dueDate - b.dueDate;
  });
}
export type SortMode = 'date' | 'priority' | 'alphabetical' | 'added';

export function matchingTask(tasks: Task[], query: string): Task | undefined {
  const value = query.toLowerCase().replace(/^(the|my)\s+/, '').trim();
  const withoutDate = value.replace(/\s+(?:on|by|for|due)\s+(?:(?:next|this)\s+)?(?:sun(?:day)?|mon(?:day)?|tue(?:sday|s)?|wed(?:nesday|s)?|thu(?:rsday|rs)?|fri(?:day)?|sat(?:urday)?|tomorrow|today|next week|\d{1,2}\/\d{1,2}).*$/i, '').trim();
  const live = tasks.filter(task => !task.isComplete);
  return live.find(task => task.title.toLowerCase() === value)
    ?? live.find(task => task.title.toLowerCase().includes(value))
    ?? (withoutDate !== value ? live.find(task => task.title.toLowerCase() === withoutDate || task.title.toLowerCase().includes(withoutDate)) : undefined)
    ?? tasks.find(task => task.title.toLowerCase().includes(value));
}
