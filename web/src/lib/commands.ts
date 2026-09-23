import * as chrono from 'chrono-node';
import { looksLikeEvent, startOfDay, toSwiftDate, type Priority, type RepeatRule, type Task } from './model';

export type Command =
  | { kind: 'add'; task: Task }
  | { kind: 'classes'; codes: string[] }
  | { kind: 'delete' | 'complete' | 'reopen' | 'stopRepeat' | 'clearTime' | 'clearClass'; query: string }
  | { kind: 'rename'; query: string; title: string }
  | { kind: 'priority'; query: string; priority: Priority }
  | { kind: 'move'; query: string; date: Date }
  | { kind: 'repeat'; query: string; rule: RepeatRule }
  | { kind: 'time'; query: string; hour: number; minute: number }
  | { kind: 'class'; query: string; code: string }
  | { kind: 'clearCompleted' | 'today' | 'calendar' | 'nextMonth' | 'previousMonth' | 'help' | 'undo' | 'redo' };

const classPattern = /[a-z]{2,8}\s?\d{2,4}[a-z]?/gi;
const weekdayNames = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
const weekdays: Record<string, string> = {
  sun: 'sunday', sund: 'sunday', mon: 'monday', mond: 'monday',
  tue: 'tuesday', tues: 'tuesday', tu: 'tuesday', wed: 'wednesday', weds: 'wednesday',
  thu: 'thursday', thur: 'thursday', thurs: 'thursday',
  fri: 'friday', frid: 'friday', sat: 'saturday', satur: 'saturday',
  wensday: 'wednesday', wednesday: 'wednesday', tusday: 'tuesday', thurday: 'thursday',
};

function normalize(input: string): string {
  let value = input.trim().replace(/[.!?]+$/, '').replace(/\s+/g, ' ');
  value = value.replace(/\b(sun|sund|mon|mond|tue|tues|tu|wed|weds|thu|thur|thurs|fri|frid|sat|satur|wensday|tusday|thurday)\b/gi,
    match => weekdays[match.toLowerCase()] ?? match);
  value = value.replace(/\b(\d{1,2})(?::(\d{2}))?\s+(am|pm)\b/gi,
    (_all, hour, minute, suffix) => `${hour}${minute ? `:${minute}` : ''}${suffix}`);
  // Mirror the Mac app's preference: bare 1–6 means afternoon; 12 is noon.
  value = value.replace(/\b(at|by|due at)\s+(\d{1,2})(?::(\d{2}))?\b(?!\s*(?:am|pm)|:)/gi, (all, prep, hour, minute) => {
    const numeric = Number(hour);
    if (numeric > 12) return all;
    const suffix = numeric <= 6 || numeric === 12 ? 'pm' : 'am';
    return `${prep} ${hour}${minute ? `:${minute}` : ''}${suffix}`;
  });
  return value;
}

function cleanQuery(query: string) {
  return query.replace(/^(?:the|my|a|an)\s+/i, '').replace(/^(?:task|event)\s+/i, '').trim();
}
function timeFrom(input: string): { hour: number; minute: number } | null {
  const match = input.match(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/i);
  if (!match) return null;
  let hour = Number(match[1]);
  const minute = Number(match[2] ?? 0);
  if (hour > 23 || minute > 59) return null;
  if (match[3]) hour = (hour % 12) + (match[3].toLowerCase() === 'pm' ? 12 : 0);
  else if (hour <= 6 || hour === 12) hour = hour === 12 ? 12 : hour + 12;
  return { hour, minute };
}
function parseDate(input: string, now: Date): Date | null {
  const result = chrono.parse(normalize(input), now, { forwardDate: true })[0];
  if (!result) return null;
  const date = result.start.date();
  if (!result.start.isCertain('hour')) date.setHours(0, 0, 0, 0);
  return date;
}
function parseRule(input: string): RepeatRule | null {
  const match = input.match(/\bevery\s+(?:(other|second|\d+)\s+)?(day|daily|week|weekly|month|monthly|sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?\b/i);
  if (!match) return null;
  const interval = match[1] === 'other' || match[1] === 'second' ? 2 : Number(match[1] ?? 1);
  if (!Number.isFinite(interval) || interval < 1) return null;
  const word = match[2].toLowerCase();
  const weekdayIndex = weekdayNames.findIndex(day => word.startsWith(day));
  if (weekdayIndex >= 0) return { interval, unit: 'week', weekday: weekdayIndex + 1 };
  return { interval, unit: word.startsWith('day') || word === 'daily' ? 'day' : word.startsWith('month') ? 'month' : 'week' };
}
function priorityIn(input: string): Priority {
  if (/\b(high priority|urgent|important|critical)\b/i.test(input)) return 'High';
  if (/\b(low priority|not urgent)\b/i.test(input)) return 'Low';
  return 'Medium';
}

export function interpret(raw: string, now = new Date()): Command {
  const value = normalize(raw);
  const lower = value.toLowerCase();
  if (/^(help|commands|\?)$/.test(lower)) return { kind: 'help' };
  if (/^(undo)$/.test(lower)) return { kind: 'undo' };
  if (/^(redo)$/.test(lower)) return { kind: 'redo' };
  if (/^(today|show today|go to today)$/.test(lower)) return { kind: 'today' };
  if (/^(calendar|show calendar|open calendar)$/.test(lower)) return { kind: 'calendar' };
  if (/^(next month|show next month)$/.test(lower)) return { kind: 'nextMonth' };
  if (/^(previous month|prev month|show previous month)$/.test(lower)) return { kind: 'previousMonth' };
  if (/^(clear|delete|remove) completed$/.test(lower)) return { kind: 'clearCompleted' };

  if (/^(?:add|create|i have|my classes are|have)\s+classes?\b/i.test(value)) {
    const codes = [...new Set((value.match(classPattern) ?? []).map(code => code.replace(/\s/g, '').toUpperCase()))];
    if (codes.length) return { kind: 'classes', codes };
  }

  let match: RegExpMatchArray | null;
  if ((match = value.match(/^(?:rename|change (?:the )?(?:name|title) of)\s+(.+?)\s+(?:to|as)\s+(.+)$/i)))
    return { kind: 'rename', query: cleanQuery(match[1]), title: match[2].trim() };
  if ((match = value.match(/^(?:make|set|change|update)\s+(.+?)\s+(?:to\s+)?(high|medium|low)(?:\s+priority)?$/i)))
    return { kind: 'priority', query: cleanQuery(match[1]), priority: (match[2][0].toUpperCase() + match[2].slice(1).toLowerCase()) as Priority };
  if ((match = value.match(/^(?:set|change)\s+(?:the\s+)?priority\s+(?:of|for)\s+(.+?)\s+to\s+(high|medium|low)$/i)))
    return { kind: 'priority', query: cleanQuery(match[1]), priority: (match[2][0].toUpperCase() + match[2].slice(1).toLowerCase()) as Priority };
  if ((match = value.match(/^(?:stop repeating|don't repeat|do not repeat)\s+(.+)$/i)))
    return { kind: 'stopRepeat', query: cleanQuery(match[1]) };
  if ((match = value.match(/^(?:repeat|make)\s+(.+?)\s+(?:repeat\s+)?(every\s+.+)$/i))) {
    const rule = parseRule(match[2]);
    if (rule) return { kind: 'repeat', query: cleanQuery(match[1]), rule };
  }
  if ((match = value.match(/^(?:move|reschedule|postpone|push|set (?:the )?date (?:of|for))\s+(.+?)\s+(?:to|for|until|on)\s+(.+)$/i))) {
    const date = parseDate(match[2], now);
    if (date) return { kind: 'move', query: cleanQuery(match[1]), date };
  }
  if ((match = value.match(/^(.+?)\s+(?:is|will be|should be)\s+due\s+(?:on|by|for)?\s*(.+)$/i))) {
    const date = parseDate(match[2], now);
    if (date) return { kind: 'move', query: cleanQuery(match[1]), date };
  }
  if ((match = value.match(/^(?:set|change|update)\s+(?:the\s+)?time\s+(?:of|for)\s+(.+?)\s+(?:to|at)\s+(.+)$/i))) {
    const time = timeFrom(match[2]);
    if (time) return { kind: 'time', query: cleanQuery(match[1]), ...time };
  }
  if ((match = value.match(/^(?:remove|clear|delete)\s+(?:the\s+)?time\s+(?:from|for|of)\s+(.+)$/i)))
    return { kind: 'clearTime', query: cleanQuery(match[1]) };
  if ((match = value.match(/^(?:assign|set class of)\s+(.+?)\s+to\s+(?:class\s+)?([a-z]{2,8}\s?\d{2,4}[a-z]?)$/i)))
    return { kind: 'class', query: cleanQuery(match[1]), code: match[2].replace(/\s/g, '').toUpperCase() };
  if ((match = value.match(/^(?:remove|clear)\s+(?:the\s+)?class\s+(?:from|for|of)\s+(.+)$/i)))
    return { kind: 'clearClass', query: cleanQuery(match[1]) };
  if ((match = value.match(/^(?:complete|finish|finished|check off|mark (?:as )?done)\s+(.+)$/i)))
    return { kind: 'complete', query: cleanQuery(match[1]) };
  if ((match = value.match(/^(.+?)\s+(?:is|was)\s+(?:done|finished|complete)$/i)))
    return { kind: 'complete', query: cleanQuery(match[1]) };
  if ((match = value.match(/^(?:reopen|uncheck|uncomplete|restore)\s+(.+)$/i)))
    return { kind: 'reopen', query: cleanQuery(match[1]) };
  if ((match = value.match(/^(?:delete|remove|cancel|erase|drop|get rid of)\s+(.+)$/i)))
    return { kind: 'delete', query: cleanQuery(match[1]) };

  let title = value.replace(/^(?:add|create|schedule|i have|i need to|remind me to)\s+(?:a|an|the|task|event)?\s*/i, '').trim();
  const repeatMatch = title.match(/\b(?:repeating|repeat|recurring)\s+(every\s+.+)$/i) ?? title.match(/\b(every\s+.+)$/i);
  const rule = repeatMatch ? parseRule(repeatMatch[1]) : null;
  if (repeatMatch) title = title.slice(0, repeatMatch.index).trim();
  title = normalize(title);
  const dateResult = chrono.parse(title, now, { forwardDate: true })[0];
  const date = dateResult?.start.date() ?? (rule?.weekday != null ? nextWeekday(now, rule.weekday) : startOfDay(now));
  if (dateResult && !dateResult.start.isCertain('hour')) date.setHours(0, 0, 0, 0);
  if (dateResult) title = (title.slice(0, dateResult.index) + title.slice(dateResult.index + dateResult.text.length)).replace(/\s+(?:on|at|by|due|for)\s*$/i, '').trim();
  title = title.replace(/\b(high|low|medium) priority\b/gi, '').replace(/\b(urgent|critical)\b/gi, '').replace(/\s+/g, ' ').trim();
  if (!title) title = value;
  const code = (title.match(classPattern) ?? [])[0]?.replace(/\s/g, '').toUpperCase();
  const task: Task = {
    id: crypto.randomUUID(), title: title.toLowerCase(), dueDate: toSwiftDate(date),
    priority: priorityIn(value), isComplete: false, createdAt: toSwiftDate(now),
    classCode: code ?? null, repeatRule: rule, isEvent: looksLikeEvent(title),
  };
  return { kind: 'add', task };
}

function nextWeekday(now: Date, swiftWeekday: number) {
  const date = startOfDay(now);
  const target = (swiftWeekday + 6) % 7;
  const days = (target - date.getDay() + 7) % 7 || 7;
  date.setDate(date.getDate() + days);
  return date;
}
