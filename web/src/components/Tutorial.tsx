'use client';

import { useEffect, useId, useLayoutEffect, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';

type Box = { x: number; y: number; width: number; height: number };
type Props = { step: number; taskId: string | null; onNext: () => void; onSkip: () => void };

const lessons = [
  { title: 'start with an event', body: 'type a quiz in the command bar. dayshift knows it belongs on your calendar, without a checkbox.', example: 'tutorial quiz tomorrow', prompt: 'type this below, then press return' },
  { title: 'now, a task', body: 'tasks have a checkbox. add one to see how the two sit together.', example: 'write tutorial notes tomorrow', prompt: 'type this below, then press return' },
  { title: 'edit in place', body: 'the title itself is editable. click your new task, change its name, and press return.', prompt: 'click the illuminated title' },
  { title: 'clear it away', body: 'right-click a title to delete the task immediately. there is no extra menu.', prompt: 'right-click the illuminated title' },
  { title: 'keep classes together', body: 'add several at once with “i have classes math237, cs136”. class names can complete with tab as you type.', prompt: 'continue when you’re ready' },
  { title: 'see the month', body: 'tasks and events share one calendar. scroll to move a month at a time; you can switch to arrows in settings.', prompt: 'you’re ready to go' },
];

const bounded = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

function spotlightBox(step: number, rect: DOMRect, width: number, height: number): Box {
  if (step < 2) return { x: -20, y: rect.top - 18, width: width + 40, height: height - rect.top + 38 };
  if (step < 4) return { x: rect.left - 16, y: rect.top - 11, width: rect.width + 32, height: rect.height + 22 };
  if (step === 4) return { x: rect.left - 14, y: rect.top - 12, width: rect.width + 28, height: Math.min(rect.height + 24, 245) };
  return { x: rect.left - 13, y: rect.top - 12, width: rect.width + 26, height: Math.min(rect.height + 24, height - rect.top + 12) };
}

function cardPosition(step: number, hole: Box, width: number, height: number): React.CSSProperties {
  const cardWidth = Math.min(380, width - 32);
  const cardHeight = step === 4 ? 258 : 238;
  if (width < 760) {
    const above = hole.y > cardHeight + 42;
    return { left: (width - cardWidth) / 2, top: bounded(above ? hole.y - cardHeight - 24 : hole.y + hole.height + 20, 70, height - cardHeight - 20) };
  }
  if (step < 2) return { left: (width - cardWidth) / 2, top: bounded(hole.y - cardHeight - 34, 74, height - cardHeight - 24) };
  if (step < 4) {
    const right = hole.x + hole.width + 34;
    return { left: right + cardWidth + 24 < width ? right : bounded(hole.x, 24, width - cardWidth - 24), top: bounded(hole.y - 25, 72, height - cardHeight - 22) };
  }
  if (step === 4) return { left: bounded(hole.x - cardWidth - 38, 24, width - cardWidth - 24), top: bounded(hole.y + 10, 72, height - cardHeight - 22) };
  return { left: 36, top: bounded(hole.y + hole.height - cardHeight - 8, 74, height - cardHeight - 24) };
}

export default function Tutorial({ step, taskId, onNext, onSkip }: Props) {
  const [spotlight, setSpotlight] = useState<{ step: number; box: Box } | null>(null);
  const [viewport, setViewport] = useState({ width: 1200, height: 800 });
  const maskId = useId().replace(/:/g, '');
  const reducedMotion = useReducedMotion();

  useLayoutEffect(() => {
    let frame = 0;
    let observer: ResizeObserver | null = null;
    let observed: Element | null = null;
    const selector = step < 2 || (step === 4 && window.innerWidth <= 560) ? '.command-bar'
      : step < 4 && taskId ? `[data-task-row-id="${taskId}"] .task-title, [data-task-row-id="${taskId}"] .title-editor`
      : step === 4 ? '.classes-panel' : '[data-calendar-active="true"] .calendar-inner';
    const measure = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const width = window.innerWidth, height = window.innerHeight;
        setViewport(previous => previous.width === width && previous.height === height ? previous : { width, height });
        const element = document.querySelector(selector);
        if (element && element !== observed) {
          observer?.disconnect();
          observer = new ResizeObserver(measure);
          observer.observe(element);
          observed = element;
        }
        const rect = element?.getBoundingClientRect();
        if (rect?.width && rect.height) setSpotlight({ step, box: spotlightBox(step, rect, width, height) });
      });
    };
    measure();
    const mutations = new MutationObserver(measure);
    mutations.observe(document.querySelector('.app-body') ?? document.body, { childList: true, subtree: true });
    window.addEventListener('resize', measure);
    window.addEventListener('scroll', measure, true);
    return () => {
      cancelAnimationFrame(frame);
      observer?.disconnect();
      mutations.disconnect();
      window.removeEventListener('resize', measure);
      window.removeEventListener('scroll', measure, true);
    };
  }, [step, taskId]);

  useEffect(() => {
    if (step < 2) document.querySelector<HTMLInputElement>('.command-line input')?.focus();
  }, [step]);

  const lesson = lessons[step];
  const box = spotlight?.step === step ? spotlight.box : null;
  const hole = box ?? { x: viewport.width / 2 - 150, y: viewport.height - 120, width: 300, height: 100 };
  const location = cardPosition(step, hole, viewport.width, viewport.height);
  return <motion.div className="tutorial-overlay" aria-label={`tutorial step ${step + 1} of 6`} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: reducedMotion ? 0 : 0.26 }}>
    <motion.svg className="tutorial-shade" viewBox={`0 0 ${viewport.width} ${viewport.height}`} preserveAspectRatio="none" aria-hidden="true" initial={false}>
      <defs>
        <filter id={`${maskId}-feather`} x="-30%" y="-60%" width="160%" height="220%"><feGaussianBlur stdDeviation={step < 2 ? '30 36' : '11'} /></filter>
        <mask id={`${maskId}-mask`} maskUnits="userSpaceOnUse">
          <rect width={viewport.width} height={viewport.height} fill="white" />
          <motion.rect fill="black" rx={step < 2 ? 0 : 16} filter={`url(#${maskId}-feather)`}
            initial={false} animate={hole} transition={reducedMotion ? { duration: 0 } : { type: 'spring', stiffness: 245, damping: 31, mass: 1.05 }} />
        </mask>
      </defs>
      <rect width={viewport.width} height={viewport.height} fill="black" fillOpacity="0.31" mask={`url(#${maskId}-mask)`} />
    </motion.svg>

    <button className="tutorial-skip" onClick={onSkip}>skip tutorial</button>
    <AnimatePresence mode="wait" initial={false}>
      <motion.section key={step} className="tutorial-card" style={location}
        initial={reducedMotion ? false : { opacity: 0, y: 9 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }}
        transition={{ duration: reducedMotion ? 0 : 0.25, ease: [0.22, 1, 0.36, 1] }}>
        <div className="tutorial-progress"><span>{String(step + 1).padStart(2, '0')} <i>/</i> 06</span><div className="tutorial-steps" aria-hidden="true">{lessons.map((_, index) => <b key={index} className={index <= step ? 'seen' : ''} />)}</div></div>
        <h2>{lesson.title}</h2>
        <p className="tutorial-body">{lesson.body}</p>
        {'example' in lesson && <p className="tutorial-example">{lesson.example}</p>}
        <div className="tutorial-footer"><p>{lesson.prompt}</p>{step >= 4 && <button onClick={onNext}>{step === 5 ? 'finish' : 'next'} <span aria-hidden="true">↗</span></button>}</div>
      </motion.section>
    </AnimatePresence>
  </motion.div>;
}
