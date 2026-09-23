'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, CircleUserRound, X } from 'lucide-react';
import type { User } from '@supabase/supabase-js';
import { interpret, type Command } from '@/lib/commands';
import { applyLocal, readLocal, syncNow } from '@/lib/sync';
import { supabase } from '@/lib/supabase';
import {
  dateOf, dayKey, fromSwiftDate, isTimed, matchingTask, nextOccurrence, repeatLabel,
  sortedTasks, startOfDay, toSwiftDate,
  type ClassItem, type Priority, type RepeatRule, type Snapshot, type SortMode, type Task,
} from '@/lib/model';

type Page = 'todo' | 'calendar';
type Modal = 'settings' | 'login' | 'signup' | 'account' | null;
type Popover = { id: string; kind: 'date' | 'priority' | 'repeat' } | null;
type Appearance = {
  text: string; background: string; font: string; size: number; spacing: number;
  hints: boolean; scrollCalendar: boolean;
};
const defaultAppearance: Appearance = {
  text: '#171717', background: '#ffffff', font: 'Times New Roman', size: 18,
  spacing: 9, hints: true, scrollCalendar: true,
};
const guestKey = 'dayshift:web:guest';
const appearanceKey = 'dayshift:web:appearance';
const emptySnapshot = (): Snapshot => ({ tasks: [], classes: [] });
const formatDate = (date: Date, options: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat('en-US', options).format(date).toLowerCase();
const dateLabel = (date: Date) => formatDate(date, { weekday: 'short', month: 'short', day: 'numeric' });
const timeLabel = (date: Date) => formatDate(date, { hour: 'numeric', minute: '2-digit' });
const nextMonth = (date: Date, amount: number) => new Date(date.getFullYear(), date.getMonth() + amount, 1);
const isSameDay = (a: Date, b: Date) => dayKey(a) === dayKey(b);

function readJSON<T>(key: string, fallback: T): T {
  try { return JSON.parse(localStorage.getItem(key) ?? '') as T; } catch { return fallback; }
}
function colorLuminance(hex: string) {
  const rgb = hex.replace('#', '').match(/.{2}/g)?.map(part => parseInt(part, 16) / 255) ?? [1, 1, 1];
  return rgb.reduce((sum, component, index) => sum + component * [0.2126, 0.7152, 0.0722][index], 0);
}

export default function Dayshift() {
  const [snapshot, setSnapshot] = useState<Snapshot>(emptySnapshot);
  const [user, setUser] = useState<User | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [page, setPage] = useState<Page>('todo');
  const [modal, setModal] = useState<Modal>(null);
  const [profileOpen, setProfileOpen] = useState(false);
  const [popover, setPopover] = useState<Popover>(null);
  const [input, setInput] = useState('');
  const [feedback, setFeedback] = useState('');
  const [month, setMonth] = useState(startOfDay(new Date()));
  const [selectedDate, setSelectedDate] = useState(startOfDay(new Date()));
  const [sort, setSort] = useState<SortMode>('date');
  const [appearance, setAppearance] = useState<Appearance>(defaultAppearance);
  const [syncStatus, setSyncStatus] = useState('local only');
  const [authError, setAuthError] = useState('');
  const [authEmail, setAuthEmail] = useState('');
  const [authPassword, setAuthPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [fadingIds, setFadingIds] = useState<Set<string>>(new Set());
  const [showTutorial, setShowTutorial] = useState(false);
  const [tutorialStep, setTutorialStep] = useState(0);
  const [tutorialTaskId, setTutorialTaskId] = useState<string | null>(null);
  const tutorialQuizId = useRef<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const syncBusy = useRef(false);
  const undoStack = useRef<Snapshot[]>([]);
  const redoStack = useRef<Snapshot[]>([]);
  const completionTimers = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());
  const activeUserId = useRef<string | null>(null);

  const pull = useCallback(async (id: string) => {
    if (syncBusy.current || !supabase || activeUserId.current !== id) return;
    syncBusy.current = true;
    setSyncStatus('syncing');
    try {
      const result = await syncNow(id);
      if (activeUserId.current === id) {
        setSnapshot(result.snapshot);
        setSyncStatus(result.pending.length ? `${result.pending.length} waiting to sync` : 'synced');
      }
    } catch {
      if (activeUserId.current === id) setSyncStatus('offline · changes saved here');
    } finally { syncBusy.current = false; }
  }, []);

  useEffect(() => {
    setAppearance(readJSON(appearanceKey, defaultAppearance));
    setSnapshot(readJSON(guestKey, emptySnapshot()));
    if (!localStorage.getItem('dayshift:web:tutorial-complete')) setShowTutorial(true);
    if (!supabase) { setAuthReady(true); return; }
    supabase.auth.getUser().then(({ data }) => {
      setUser(data.user); setAuthReady(true);
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      setAuthReady(true);
    });
    return () => listener.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!authReady) return;
    activeUserId.current = user?.id ?? null;
    undoStack.current = []; redoStack.current = [];
    if (!user) {
      setSnapshot(readJSON(guestKey, emptySnapshot()));
      setSyncStatus('local only');
      return;
    }
    const saved = readLocal(user.id);
    setSnapshot(saved.snapshot);
    void pull(user.id).then(async () => {
      const marker = `dayshift:web:guest-imported:${user.id}`;
      if (activeUserId.current !== user.id || localStorage.getItem(marker)) return;
      const guest = readJSON(guestKey, emptySnapshot());
      if (guest.tasks.length || guest.classes.length) {
        const current = readLocal(user.id).snapshot;
        const taskIds = new Set(current.tasks.map(task => task.id));
        const classCodes = new Set(current.classes.map(item => item.code));
        const merged = {
          tasks: [...current.tasks, ...guest.tasks.filter(task => !taskIds.has(task.id))],
          classes: [...current.classes, ...guest.classes.filter(item => !classCodes.has(item.code))],
        };
        applyLocal(user.id, merged);
        setSnapshot(merged);
        await pull(user.id);
      }
      localStorage.setItem(marker, 'true');
    });
    const interval = setInterval(() => void pull(user.id), 15_000);
    const onVisible = () => { if (document.visibilityState === 'visible') void pull(user.id); };
    document.addEventListener('visibilitychange', onVisible);
    return () => { clearInterval(interval); document.removeEventListener('visibilitychange', onVisible); };
  }, [authReady, user?.id, pull]);

  useEffect(() => { localStorage.setItem(appearanceKey, JSON.stringify(appearance)); }, [appearance]);
  useEffect(() => {
    document.documentElement.style.setProperty('--ink', appearance.text);
    document.documentElement.style.setProperty('--paper', appearance.background);
    document.documentElement.style.setProperty('--font-family', `"${appearance.font}", Georgia, serif`);
    document.documentElement.style.setProperty('--scale', String(appearance.size / 18));
    document.documentElement.style.setProperty('--row-space', `${appearance.spacing}px`);
    document.documentElement.style.colorScheme = colorLuminance(appearance.background) < 0.35 ? 'dark' : 'light';
  }, [appearance]);

  const commit = useCallback((next: Snapshot, keepHistory = true) => {
    setSnapshot(previous => {
      if (JSON.stringify(previous) === JSON.stringify(next)) return previous;
      if (keepHistory) { undoStack.current.push(previous); redoStack.current = []; }
      if (activeUserId.current) {
        applyLocal(activeUserId.current, next);
        queueMicrotask(() => void pull(activeUserId.current!));
      } else localStorage.setItem(guestKey, JSON.stringify(next));
      return next;
    });
  }, [pull]);

  const updateTask = useCallback((id: string, update: (task: Task) => Task | null) => {
    const tasks = snapshot.tasks.flatMap(task => task.id === id ? (updated => updated ? [updated] : [])(update(task)) : [task]);
    commit({ ...snapshot, tasks });
    setPopover(null);
  }, [snapshot, commit]);

  const removeTask = useCallback((id: string) => {
    completionTimers.current.get(id) && clearTimeout(completionTimers.current.get(id));
    completionTimers.current.delete(id);
    updateTask(id, () => null);
  }, [updateTask]);

  const completeTask = useCallback((task: Task, complete: boolean) => {
    if (task.isEvent) return;
    const updated = { ...task, isComplete: complete };
    const next = complete ? nextOccurrence(task) : null;
    commit({ ...snapshot, tasks: snapshot.tasks.map(item => item.id === task.id ? updated : item).concat(next ? [next] : []) });
    if (complete) {
      const timer = setTimeout(() => {
        setFadingIds(current => new Set(current).add(task.id));
        const fadeTimer = setTimeout(() => {
          setSnapshot(current => {
            const without = { ...current, tasks: current.tasks.filter(item => item.id !== task.id) };
            if (activeUserId.current) { applyLocal(activeUserId.current, without); void pull(activeUserId.current); }
            else localStorage.setItem(guestKey, JSON.stringify(without));
            return without;
          });
          setFadingIds(current => { const next = new Set(current); next.delete(task.id); return next; });
          completionTimers.current.delete(task.id);
        }, 400);
        completionTimers.current.set(task.id, fadeTimer);
      }, 2000);
      completionTimers.current.set(task.id, timer);
    } else {
      const timer = completionTimers.current.get(task.id);
      if (timer) clearTimeout(timer);
      completionTimers.current.delete(task.id);
      setFadingIds(current => { const next = new Set(current); next.delete(task.id); return next; });
    }
  }, [snapshot, commit, pull]);

  const undo = useCallback(() => {
    const previous = undoStack.current.pop();
    if (!previous) return;
    redoStack.current.push(snapshot);
    completionTimers.current.forEach(timer => clearTimeout(timer)); completionTimers.current.clear();
    setFadingIds(new Set());
    commit(previous, false);
  }, [snapshot, commit]);
  const redo = useCallback(() => {
    const next = redoStack.current.pop();
    if (!next) return;
    undoStack.current.push(snapshot);
    commit(next, false);
  }, [snapshot, commit]);

  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z') {
        event.preventDefault(); if (event.shiftKey) redo(); else undo();
      }
      if (event.key === 'Escape') { setPopover(null); setProfileOpen(false); setModal(null); }
    };
    document.addEventListener('keydown', keys);
    return () => document.removeEventListener('keydown', keys);
  }, [undo, redo]);

  const execute = (command: Command) => {
    if (command.kind === 'undo') { undo(); return 'undone'; }
    if (command.kind === 'redo') { redo(); return 'redone'; }
    if (command.kind === 'help') { setModal('settings'); return 'type anything in ordinary language'; }
    if (command.kind === 'today') { setSelectedDate(startOfDay(new Date())); setPage('todo'); return 'today'; }
    if (command.kind === 'calendar') { setPage('calendar'); return 'calendar'; }
    if (command.kind === 'nextMonth' || command.kind === 'previousMonth') {
      setMonth(current => nextMonth(current, command.kind === 'nextMonth' ? 1 : -1)); setPage('calendar'); return 'calendar';
    }
    if (command.kind === 'classes') {
      const existing = new Set(snapshot.classes.map(item => item.code));
      const additions = command.codes.filter(code => !existing.has(code)).map(code => ({ id: crypto.randomUUID(), code, name: '' }));
      commit({ ...snapshot, classes: [...snapshot.classes, ...additions] });
      return `saved ${command.codes.join(', ').toLowerCase()}`;
    }
    if (command.kind === 'add') {
      commit({ ...snapshot, tasks: [command.task, ...snapshot.tasks] });
      setPage('todo');
      if (showTutorial && tutorialStep === 0 && command.task.isEvent) {
        tutorialQuizId.current = command.task.id; setTutorialStep(1);
      } else if (showTutorial && tutorialStep === 1 && !command.task.isEvent) {
        setTutorialTaskId(command.task.id); setTutorialStep(2);
      }
      return `added “${command.task.title}”`;
    }
    if (command.kind === 'clearCompleted') {
      commit({ ...snapshot, tasks: snapshot.tasks.filter(task => !task.isComplete) }); return 'cleared completed tasks';
    }
    if (!('query' in command)) return '';
    const task = matchingTask(snapshot.tasks, command.query);
    if (!task) return `couldn’t find “${command.query}”`;
    switch (command.kind) {
      case 'delete': removeTask(task.id); return `removed “${task.title}”`;
      case 'complete': completeTask(task, true); return task.isEvent ? 'events do not have checkboxes' : `completed “${task.title}”`;
      case 'reopen': completeTask(task, false); return `reopened “${task.title}”`;
      case 'rename': updateTask(task.id, item => ({ ...item, title: command.title.toLowerCase() })); return `renamed to “${command.title}”`;
      case 'priority': updateTask(task.id, item => ({ ...item, priority: command.priority })); return `${task.title} · ${command.priority.toLowerCase()}`;
      case 'move': updateTask(task.id, item => ({ ...item, dueDate: toSwiftDate(command.date) })); return `moved “${task.title}” to ${dateLabel(command.date)}`;
      case 'repeat': updateTask(task.id, item => ({ ...item, repeatRule: command.rule })); return `${task.title} · ${repeatLabel(command.rule)}`;
      case 'stopRepeat': updateTask(task.id, item => ({ ...item, repeatRule: null })); return `stopped repeating “${task.title}”`;
      case 'time': {
        const date = dateOf(task); date.setHours(command.hour, command.minute, 0, 0);
        updateTask(task.id, item => ({ ...item, dueDate: toSwiftDate(date) })); return `${task.title} · ${timeLabel(date)}`;
      }
      case 'clearTime': {
        updateTask(task.id, item => ({ ...item, dueDate: toSwiftDate(startOfDay(dateOf(item))) })); return `removed time from “${task.title}”`;
      }
      case 'class': updateTask(task.id, item => ({ ...item, classCode: command.code })); return `${task.title} · ${command.code.toLowerCase()}`;
      case 'clearClass': updateTask(task.id, item => ({ ...item, classCode: null })); return `removed class from “${task.title}”`;
    }
  };

  const submit = () => {
    if (!input.trim()) return;
    setFeedback(execute(interpret(input)) ?? '');
    setInput('');
    inputRef.current?.focus();
  };

  const classSuggestion = useMemo(() => {
    const tail = input.trim().split(/\s+/).at(-1)?.toLowerCase() ?? '';
    if (!tail || snapshot.classes.some(item => input.toLowerCase().includes(item.code.toLowerCase()))) return null;
    return snapshot.classes.find(item => item.code.toLowerCase().startsWith(tail)) ?? null;
  }, [input, snapshot.classes]);
  const acceptSuggestion = () => {
    if (!classSuggestion) return;
    const tail = input.match(/[a-z0-9]+$/i);
    if (tail && classSuggestion.code.toLowerCase().startsWith(tail[0].toLowerCase()))
      setInput(input.slice(0, -tail[0].length) + classSuggestion.code.toLowerCase());
    else setInput(input.trimEnd() + ' ' + classSuggestion.code.toLowerCase());
  };

  const today = startOfDay(new Date());
  const activeTasks = snapshot.tasks.filter(task => !task.isComplete || completionTimers.current.has(task.id));
  const todayTasks = sortedTasks(activeTasks.filter(task => isSameDay(dateOf(task), today)), sort);
  const futureTasks = sortedTasks(activeTasks.filter(task => dateOf(task) >= new Date(today.getTime() + 86400000)), sort);
  const selectedTasks = sortedTasks(activeTasks.filter(task => isSameDay(dateOf(task), selectedDate)), sort);
  const viewingToday = isSameDay(selectedDate, today);
  const displayedTasks = viewingToday ? todayTasks : selectedTasks;
  const suggestion = input.trim() ? classSuggestion ? `tab ↹ add ${classSuggestion.code.toLowerCase()}` : preview(interpret(input)) : 'try “quiz next wednesday” or “move quiz to friday”';

  const submitAuth = async () => {
    if (!supabase) { setAuthError('supabase is not configured'); return; }
    setBusy(true); setAuthError('');
    try {
      if (modal === 'signup') {
        const { data, error } = await supabase.auth.signUp({ email: authEmail, password: authPassword });
        if (error) throw error;
        if (!data.session) setAuthError('check your email to confirm your account, then log in.');
        else { setModal(null); setAuthPassword(''); }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email: authEmail, password: authPassword });
        if (error) throw error;
        setModal(null); setAuthPassword('');
      }
    } catch (error) { setAuthError(error instanceof Error ? error.message : 'could not sign in'); }
    finally { setBusy(false); }
  };

  const openModal = (target: Modal) => { setProfileOpen(false); setPopover(null); setAuthError(''); setModal(target); };
  const changeAppearance = <K extends keyof Appearance>(key: K, value: Appearance[K]) => setAppearance(current => ({ ...current, [key]: value }));

  return <div className="app-shell" onClick={() => { if (popover) setPopover(null); if (profileOpen) setProfileOpen(false); }}>
    <header className="app-header">
      <div className="header-center" aria-label="view">
        <button className={page === 'todo' ? 'active' : ''} onClick={() => setPage('todo')}>todo</button>
        <span className="header-slash">/</span>
        <button className={page === 'calendar' ? 'active' : ''} onClick={() => setPage('calendar')}>calendar</button>
      </div>
      <div className="profile-wrap" onClick={event => event.stopPropagation()}>
        <button className="profile-trigger" aria-label="profile" aria-expanded={profileOpen} onClick={() => { setProfileOpen(!profileOpen); setPopover(null); }}><CircleUserRound size={24} strokeWidth={1.5} /></button>
        {profileOpen && <div className="profile-menu">
          <p className="subtle small truncate">{user?.email?.toLowerCase() ?? 'not signed in'}</p>
          {user ? <button onClick={() => openModal('account')}>account</button> : <><button onClick={() => openModal('login')}>log in</button><button onClick={() => openModal('signup')}>sign up</button></>}
          <button onClick={() => openModal('settings')}>settings</button>
          {user && <><p className="subtle small">{syncStatus}</p><button onClick={async () => { setProfileOpen(false); await supabase?.auth.signOut(); }}>sign out</button></>}
        </div>}
      </div>
    </header>

    <div className="app-body">
      <main className={page === 'calendar' ? 'main-panel calendar-main' : 'main-panel'}>
        {page === 'todo' ? <div className="todo-content">
          <div className="date-heading-row"><h1>{formatDate(selectedDate, { weekday: 'long', month: 'long', day: 'numeric' })}</h1><div className="sort-wrap"><span className="subtle">sort</span><select aria-label="sort tasks" value={sort} onChange={event => setSort(event.target.value as SortMode)}><option value="date">date</option><option value="priority">priority</option><option value="alphabetical">alphabetical</option><option value="added">added</option></select></div></div>
          {displayedTasks.length ? <TaskSections tasks={displayedTasks} showDate={false} row={renderTask} /> : <p className="empty-state">{viewingToday ? 'no tasks today' : 'nothing scheduled'}</p>}
          {viewingToday && <section className="upcoming-section"><h2>upcoming</h2>{futureTasks.length ? <TaskSections tasks={futureTasks} showDate row={renderTask} /> : <p className="empty-state small">nothing upcoming</p>}</section>}
          {!viewingToday && <button className="quiet-link back-today" onClick={() => setSelectedDate(today)}>back to today</button>}
        </div> : <Calendar month={month} setMonth={setMonth} tasks={activeTasks} selectedDate={selectedDate} onSelect={date => { setSelectedDate(date); setPage('todo'); }} scroll={appearance.scrollCalendar} />}
      </main>
      <aside className="classes-panel"><h2>classes</h2>{snapshot.classes.length ? [...snapshot.classes].sort((a, b) => a.code.localeCompare(b.code)).map(item => {
        const items = activeTasks.filter(task => !task.isComplete && task.classCode?.toLowerCase() === item.code.toLowerCase() && dateOf(task) >= today).sort((a, b) => a.dueDate - b.dueDate);
        return <div className="class-row" key={item.id}><div>{item.code.toLowerCase()}</div><p className="subtle small">{items.length} {items.length === 1 ? 'task' : 'tasks'}{items[0] ? ` · next ${dateLabel(dateOf(items[0]))}` : ''}</p></div>;
      }) : <p className="subtle small">no classes</p>}</aside>
    </div>

    <div className="command-bar"><div className="command-line"><input ref={inputRef} aria-label="command" value={input} placeholder="type anything…" onChange={event => { setInput(event.target.value); setFeedback(''); }} onKeyDown={event => { if (event.key === 'Enter') submit(); if (event.key === 'Tab' && classSuggestion) { event.preventDefault(); acceptSuggestion(); } }} /><span className="subtle small return-label">return ↵</span></div>{appearance.hints && <p className="command-hint">{feedback || suggestion}</p>}</div>

    {modal && <div className="modal-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) setModal(null); }}><div className="modal-card" role="dialog" aria-modal="true" aria-label={modal}><button className="modal-close" aria-label="close" onClick={() => setModal(null)}><X size={18} strokeWidth={1.5} /></button>
      {modal === 'settings' ? <><h2>settings</h2><p className="modal-section-label">appearance</p><SettingColor label="text colour" value={appearance.text} onChange={value => changeAppearance('text', value)} /><SettingColor label="background colour" value={appearance.background} onChange={value => changeAppearance('background', value)} /><div className="setting-row"><label htmlFor="font">font</label><select id="font" value={appearance.font} onChange={event => changeAppearance('font', event.target.value)}>{['Times New Roman', 'Baskerville', 'Georgia', 'Palatino'].map(font => <option key={font}>{font}</option>)}</select></div><div className="setting-row"><label htmlFor="size">text size</label><input id="size" type="range" min="14" max="24" value={appearance.size} onChange={event => changeAppearance('size', Number(event.target.value))} /><span>{appearance.size}</span></div><div className="setting-row"><label htmlFor="spacing">row spacing</label><input id="spacing" type="range" min="4" max="20" value={appearance.spacing} onChange={event => changeAppearance('spacing', Number(event.target.value))} /><span>{appearance.spacing}</span></div><div className="setting-row"><label htmlFor="hints">command hints</label><input id="hints" type="checkbox" checked={appearance.hints} onChange={event => changeAppearance('hints', event.target.checked)} /></div><div className="setting-row"><label htmlFor="calendar-mode">calendar navigation</label><select id="calendar-mode" value={appearance.scrollCalendar ? 'scroll' : 'arrows'} onChange={event => changeAppearance('scrollCalendar', event.target.value === 'scroll')}><option value="scroll">scroll</option><option value="arrows">arrows</option></select></div><div className="modal-actions"><button onClick={() => setAppearance(defaultAppearance)}>restore defaults</button><button onClick={() => { setModal(null); setShowTutorial(true); setTutorialStep(0); }}>show tutorial again</button></div></>
        : modal === 'account' ? <><h2>account</h2><p className="account-email">{user?.email?.toLowerCase()}</p><p className="subtle">{syncStatus}</p><p className="subtle account-copy">your tasks and classes sync with the mac app when you use the same account.</p><button className="solid-button" onClick={() => void pull(user!.id)}>sync now</button></>
        : <><h2>{modal === 'signup' ? 'sign up' : 'log in'}</h2><form className="auth-form" onSubmit={event => { event.preventDefault(); void submitAuth(); }}><input type="email" autoComplete="email" required placeholder="email" aria-label="email" value={authEmail} onChange={event => setAuthEmail(event.target.value)} /><input type="password" autoComplete={modal === 'signup' ? 'new-password' : 'current-password'} minLength={6} required placeholder="password" aria-label="password" value={authPassword} onChange={event => setAuthPassword(event.target.value)} /><button className="solid-button" type="submit" disabled={busy}>{busy ? 'one moment…' : modal === 'signup' ? 'create account' : 'log in'}</button></form>{authError && <p className="auth-error">{authError}</p>}<p className="auth-switch subtle">{modal === 'signup' ? 'already have an account?' : 'new to dayshift?'} <button onClick={() => { setAuthError(''); setModal(modal === 'signup' ? 'login' : 'signup'); }}>{modal === 'signup' ? 'log in' : 'sign up'}</button></p><p className="subtle account-copy">{modal === 'signup' ? 'check your email to confirm your account, then sign in.' : 'your synced tasks will appear here after you sign in.'}</p></>}
    </div></div>}

    {showTutorial && <Tutorial step={tutorialStep} taskId={tutorialTaskId} onNext={() => { if (tutorialStep === 5) finishTutorial(); else { setTutorialStep(step => step + 1); if (tutorialStep === 4) setPage('calendar'); } }} onSkip={finishTutorial} />}
  </div>;

  function renderTask(task: Task, showDate: boolean) {
    return <TaskRow key={task.id} task={task} fading={fadingIds.has(task.id)} showDate={showDate} popover={popover} setPopover={setPopover} onToggle={() => completeTask(task, !task.isComplete)} onDelete={() => { removeTask(task.id); if (showTutorial && tutorialStep === 3 && task.id === tutorialTaskId) setTutorialStep(4); }} onRename={title => { updateTask(task.id, item => ({ ...item, title: title.toLowerCase() })); if (showTutorial && tutorialStep === 2 && task.id === tutorialTaskId) setTutorialStep(3); }} onDate={date => { const previous = dateOf(task); date.setHours(previous.getHours(), previous.getMinutes()); updateTask(task.id, item => ({ ...item, dueDate: toSwiftDate(date) })); }} onTime={time => { const date = dateOf(task); if (time === '') date.setHours(0, 0); else { const [h, m] = time.split(':').map(Number); date.setHours(h, m); } updateTask(task.id, item => ({ ...item, dueDate: toSwiftDate(date) })); }} onPriority={priority => updateTask(task.id, item => ({ ...item, priority }))} onRepeat={rule => updateTask(task.id, item => ({ ...item, repeatRule: rule }))} />;
  }

  function finishTutorial() {
    const sampleIds = new Set([tutorialQuizId.current, tutorialTaskId].filter((id): id is string => !!id));
    if (sampleIds.size) commit({ ...snapshot, tasks: snapshot.tasks.filter(task => !sampleIds.has(task.id) || !task.title.includes('tutorial')) });
    localStorage.setItem('dayshift:web:tutorial-complete', 'true');
    setShowTutorial(false);
  }
}

function TaskSections({ tasks, showDate, row }: { tasks: Task[]; showDate: boolean; row: (task: Task, showDate: boolean) => React.ReactNode }) {
  const events = tasks.filter(task => task.isEvent);
  const todos = tasks.filter(task => !task.isEvent);
  return <div className="task-sections">{events.length > 0 && <div className="task-group"><h3>events</h3>{events.map(task => row(task, showDate))}</div>}{todos.length > 0 && <div className="task-group"><h3>tasks</h3>{todos.map(task => row(task, showDate))}</div>}</div>;
}

function TaskRow({ task, fading, showDate, popover, setPopover, onToggle, onDelete, onRename, onDate, onTime, onPriority, onRepeat }: {
  task: Task; fading: boolean; showDate: boolean; popover: Popover; setPopover: (value: Popover) => void;
  onToggle: () => void; onDelete: () => void; onRename: (title: string) => void;
  onDate: (date: Date) => void; onTime: (time: string) => void; onPriority: (priority: Priority) => void;
  onRepeat: (rule: RepeatRule | null) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(task.title);
  const [editingTime, setEditingTime] = useState(false);
  const date = dateOf(task);
  const open = (kind: NonNullable<Popover>['kind']) => (event: React.MouseEvent) => {
    event.stopPropagation(); setPopover(popover?.id === task.id && popover.kind === kind ? null : { id: task.id, kind });
  };
  const saveTitle = () => { if (title.trim() && title.trim() !== task.title) onRename(title.trim()); else setTitle(task.title); setEditing(false); };
  return <div className={`task-row ${fading ? 'fading' : ''}`} onContextMenu={event => { event.preventDefault(); onDelete(); }}>
    {!task.isEvent && <button className="task-checkbox" aria-label={`mark ${task.title} ${task.isComplete ? 'incomplete' : 'complete'}`} onClick={onToggle}>{task.isComplete && <span>✓</span>}</button>}
    <div className={`task-copy ${task.isEvent ? 'event-copy' : ''}`}>
      {editing ? <input className="title-editor" autoFocus value={title} onChange={event => setTitle(event.target.value)} onBlur={saveTitle} onKeyDown={event => { if (event.key === 'Enter') saveTitle(); if (event.key === 'Escape') { setTitle(task.title); setEditing(false); } }} /> : <button className="task-title" data-task-id={task.id} title="click to rename · right-click to delete" onClick={() => setEditing(true)}>{task.title.toLowerCase()}</button>}
      <div className="task-meta">
        <div className="detail-wrap"><button onClick={open('date')}>{!showDate && isSameDay(date, new Date()) ? 'today' : dateLabel(date)}</button>{popover?.id === task.id && popover.kind === 'date' && <div className="detail-popover date-popover" onClick={event => event.stopPropagation()}><MiniCalendar date={date} onChoose={onDate} /><input aria-label="due time" type="time" value={isTimed(task) ? `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}` : ''} onChange={event => onTime(event.target.value)} />{isTimed(task) && <button onClick={() => onTime('')}>remove time</button>}</div>}</div>
        {isTimed(task) && <><span>·</span>{editingTime ? <input className="time-editor" type="time" autoFocus value={`${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`} onChange={event => { onTime(event.target.value); setEditingTime(false); }} onBlur={() => setEditingTime(false)} /> : <button onClick={() => setEditingTime(true)}>{timeLabel(date)}</button>}</>}
        <span>·</span>
        <div className="detail-wrap"><button onClick={open('priority')}>{task.priority.toLowerCase()}</button>{popover?.id === task.id && popover.kind === 'priority' && <div className="detail-popover options">{(['High', 'Medium', 'Low'] as Priority[]).map(value => <button key={value} onClick={() => onPriority(value)}>{value.toLowerCase()}</button>)}</div>}</div>
        {task.repeatRule && <span>·</span>}
        <div className="detail-wrap"><button onClick={open('repeat')}>{task.repeatRule ? repeatLabel(task.repeatRule) : 'repeat'}</button>{popover?.id === task.id && popover.kind === 'repeat' && <div className="detail-popover options">{[null, { interval: 1, unit: 'day' }, { interval: 1, unit: 'week' }, { interval: 2, unit: 'week' }, { interval: 1, unit: 'month' }].map((rule, index) => <button key={index} onClick={() => onRepeat(rule as RepeatRule | null)}>{rule ? repeatLabel(rule as RepeatRule) : 'never'}</button>)}</div>}</div>
        {task.classCode && <><span>·</span><span>{task.classCode.toLowerCase()}</span></>}
      </div>
    </div>
  </div>;
}

function Calendar({ month, setMonth, tasks, selectedDate, onSelect, scroll }: { month: Date; setMonth: React.Dispatch<React.SetStateAction<Date>>; tasks: Task[]; selectedDate: Date; onSelect: (date: Date) => void; scroll: boolean }) {
  const wheelLock = useRef(false);
  const [direction, setDirection] = useState(0);
  const move = (amount: number) => { setDirection(amount); setMonth(current => nextMonth(current, amount)); };
  const onWheel = (event: React.WheelEvent) => {
    if (!scroll || Math.abs(event.deltaY) < 2 || wheelLock.current) return;
    wheelLock.current = true; move(event.deltaY > 0 ? 1 : -1);
    setTimeout(() => { wheelLock.current = false; }, 420);
  };
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  const leading = first.getDay();
  const days = Array.from({ length: 42 }, (_, index) => new Date(month.getFullYear(), month.getMonth(), index - leading + 1));
  return <div className="calendar-viewport" onWheel={onWheel}><div className={`calendar-content ${direction ? `slide-${direction > 0 ? 'up' : 'down'}` : ''}`} key={`${month.getFullYear()}-${month.getMonth()}`}>
    <div className="calendar-title">{!scroll && <button aria-label="previous month" onClick={() => move(-1)}><ChevronLeft size={18} /></button>}<h1>{formatDate(month, { month: 'long', year: 'numeric' })}</h1>{!scroll && <button aria-label="next month" onClick={() => move(1)}><ChevronRight size={18} /></button>}</div>
    <div className="calendar-grid">{['s', 'm', 't', 'w', 't', 'f', 's'].map((day, index) => <div className="weekday" key={index}>{day}</div>)}{days.map(date => {
      const items = tasks.filter(task => isSameDay(dateOf(task), date)).slice(0, 2);
      return <button className={`calendar-day ${date.getMonth() === month.getMonth() ? '' : 'outside'} ${isSameDay(date, selectedDate) ? 'selected' : ''}`} key={dayKey(date)} onClick={() => onSelect(date)}><span>{date.getDate()}</span>{items.map(item => <small key={item.id}>{item.title.toLowerCase()}</small>)}</button>;
    })}</div>
  </div></div>;
}

function MiniCalendar({ date, onChoose }: { date: Date; onChoose: (date: Date) => void }) {
  const [month, setMonth] = useState(new Date(date.getFullYear(), date.getMonth(), 1));
  const leading = month.getDay();
  const days = Array.from({ length: 42 }, (_, index) => new Date(month.getFullYear(), month.getMonth(), index - leading + 1));
  return <div className="mini-calendar"><div className="mini-header"><button aria-label="previous month" onClick={() => setMonth(nextMonth(month, -1))}>←</button><span>{formatDate(month, { month: 'long', year: 'numeric' })}</span><button aria-label="next month" onClick={() => setMonth(nextMonth(month, 1))}>→</button></div><div className="mini-grid">{['s', 'm', 't', 'w', 't', 'f', 's'].map((day, index) => <span className="mini-weekday" key={index}>{day}</span>)}{days.map(day => <button key={dayKey(day)} className={`${day.getMonth() === month.getMonth() ? '' : 'outside'} ${isSameDay(day, date) ? 'selected' : ''}`} onClick={() => onChoose(day)}>{day.getDate()}</button>)}</div></div>;
}

function SettingColor({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  const [open, setOpen] = useState(false);
  const [hue, saturation, lightness] = hexToHsl(value);
  const wheel = useRef<HTMLDivElement>(null);
  const choose = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!wheel.current) return;
    const bounds = wheel.current.getBoundingClientRect();
    const x = event.clientX - bounds.left - bounds.width / 2;
    const y = event.clientY - bounds.top - bounds.height / 2;
    const nextHue = (Math.atan2(x, -y) * 180 / Math.PI + 360) % 360;
    const nextSaturation = Math.min(100, Math.round(Math.hypot(x, y) / (bounds.width / 2) * 100));
    onChange(hslToHex(nextHue, nextSaturation, lightness));
  };
  return <div className="setting-row colour-row"><label>{label}</label><div className="colour-control"><button className="colour-trigger" aria-label={`choose ${label}`} aria-expanded={open} onClick={() => setOpen(!open)}><span className="colour-swatch" style={{ background: value }} />{value}</button>{open && <div className="colour-popout"><div ref={wheel} className="colour-wheel" onPointerDown={event => { event.currentTarget.setPointerCapture(event.pointerId); choose(event); }} onPointerMove={event => { if (event.buttons) choose(event); }}><span className="wheel-pointer" style={{ left: `${50 + 44 * saturation / 100 * Math.sin(hue * Math.PI / 180)}%`, top: `${50 - 44 * saturation / 100 * Math.cos(hue * Math.PI / 180)}%`, background: value }} /></div><label className="lightness-row">lightness <input aria-label={`${label} lightness`} type="range" min="0" max="100" value={lightness} onChange={event => onChange(hslToHex(hue, saturation, Number(event.target.value)))} /></label><button className="colour-done" onClick={() => setOpen(false)}>done</button></div>}</div></div>;
}

function hexToHsl(hex: string): [number, number, number] {
  const [r, g, b] = (hex.match(/[a-f\d]{2}/gi) ?? ['00', '00', '00']).map(part => parseInt(part, 16) / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
  let hue = 0;
  if (delta) {
    if (max === r) hue = ((g - b) / delta) % 6;
    else if (max === g) hue = (b - r) / delta + 2;
    else hue = (r - g) / delta + 4;
    hue = (hue * 60 + 360) % 360;
  }
  const lightness = (max + min) / 2;
  const saturation = delta ? delta / (1 - Math.abs(2 * lightness - 1)) : 0;
  return [hue, Math.round(saturation * 100), Math.round(lightness * 100)];
}

function hslToHex(hue: number, saturation: number, lightness: number): string {
  const s = saturation / 100, l = lightness / 100;
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const x = chroma * (1 - Math.abs((hue / 60) % 2 - 1));
  const m = l - chroma / 2;
  const rgb = hue < 60 ? [chroma, x, 0] : hue < 120 ? [x, chroma, 0] : hue < 180 ? [0, chroma, x] : hue < 240 ? [0, x, chroma] : hue < 300 ? [x, 0, chroma] : [chroma, 0, x];
  return `#${rgb.map(channel => Math.round((channel + m) * 255).toString(16).padStart(2, '0')).join('')}`;
}

function Tutorial({ step, taskId, onNext, onSkip }: { step: number; taskId: string | null; onNext: () => void; onSkip: () => void }) {
  const [target, setTarget] = useState<DOMRect | null>(null);
  useEffect(() => {
    const measure = () => {
      const selector = step < 2 ? '.command-bar' : step < 4 && taskId ? `[data-task-id="${taskId}"]` : step === 4 ? '.classes-panel' : '.calendar-main';
      setTarget(document.querySelector(selector)?.getBoundingClientRect() ?? null);
    };
    measure();
    const frame = requestAnimationFrame(measure);
    window.addEventListener('resize', measure);
    window.addEventListener('scroll', measure, true);
    return () => { cancelAnimationFrame(frame); window.removeEventListener('resize', measure); window.removeEventListener('scroll', measure, true); };
  }, [step, taskId]);
  const titles = ['add a sample event', 'now add a task', 'rename a task', 'remove a task', 'keep classes together', 'your month at a glance'];
  const body = [
    'the command bar understands ordinary language. try “tutorial quiz tomorrow”; dayshift recognises it as an event.',
    'try “write tutorial notes tomorrow”. tasks have checkboxes; events do not.',
    'click a task title to rename it. press return to save.',
    'right-click a task or event to remove it immediately.',
    'add classes with “i have classes math237, cs136”. press tab to accept a suggested class later.',
    'your calendar keeps the same quiet layout. scroll to move between months, or choose arrows in settings.',
  ];
  const viewportWidth = typeof window === 'undefined' ? 1200 : window.innerWidth;
  const viewportHeight = typeof window === 'undefined' ? 800 : window.innerHeight;
  const x = target ? target.left + target.width / 2 : viewportWidth / 2;
  const y = target ? target.top + target.height / 2 : viewportHeight / 2;
  const wide = step < 2 || step === 5;
  const cardStyle: React.CSSProperties = step < 2 ? { bottom: Math.min(viewportHeight - 290, (target?.height ?? 90) + 55), left: '50%', transform: 'translateX(-50%)' }
    : step < 4 ? { top: Math.min(viewportHeight - 230, Math.max(80, y - 65)), left: Math.max(20, Math.min(viewportWidth - 460, (target?.right ?? 150) + 44)) }
    : { top: Math.min(viewportHeight - 230, Math.max(90, y - 30)), left: step === 4 ? Math.max(24, (target?.left ?? viewportWidth) - 485) : Math.max(24, viewportWidth / 2 - 220) };
  return <div className="tutorial-overlay" style={{ '--spot-x': `${x}px`, '--spot-y': `${y}px`, '--spot-w': `${wide ? Math.max(270, (target?.width ?? 400) * .7) : Math.max(95, (target?.width ?? 120) * .9)}px`, '--spot-h': `${step < 2 ? 150 : step === 4 ? Math.max(180, (target?.height ?? 200) * .62) : step === 5 ? 330 : 72}px` } as React.CSSProperties}>
    <div className="tutorial-dimmer" /><button className="tutorial-skip" onClick={onSkip}>skip tutorial</button><div className="tutorial-card" style={cardStyle}><p className="subtle small">{step + 1} of 6</p><h2>{titles[step]}</h2><p>{body[step]}</p>{step < 4 ? <p className="subtle tutorial-prompt">{step < 2 ? 'type it below and press return' : step === 2 ? 'click the title to continue' : 'right-click the title to continue'}</p> : <button className="quiet-link" onClick={onNext}>{step === 5 ? 'finish' : 'next'} →</button>}</div></div>;
}

function preview(command: Command): string {
  switch (command.kind) {
    case 'add': return `add “${command.task.title}” · ${dateLabel(fromSwiftDate(command.task.dueDate))} · ${command.task.priority.toLowerCase()}`;
    case 'classes': return `add ${command.codes.join(', ').toLowerCase()}`;
    case 'move': return `move “${command.query}” to ${dateLabel(command.date)}`;
    case 'priority': return `set “${command.query}” to ${command.priority.toLowerCase()} priority`;
    case 'rename': return `rename “${command.query}” to “${command.title}”`;
    case 'repeat': return `repeat “${command.query}” ${repeatLabel(command.rule)}`;
    case 'delete': return `remove “${command.query}”`;
    case 'complete': return `complete “${command.query}”`;
    default: return command.kind.replace(/[A-Z]/g, letter => ` ${letter.toLowerCase()}`);
  }
}
