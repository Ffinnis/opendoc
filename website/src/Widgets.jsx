import { useEffect, useRef, useState } from "react";
import "./widgets.css";
import {
  ArrowLeftIcon,
  ArrowRightIcon,
  PlayIcon,
  PauseIcon,
  ArrowCounterClockwiseIcon,
  ClockIcon,
  TimerIcon,
  NoteIcon,
  CheckSquareIcon,
  CalendarBlankIcon,
} from "@phosphor-icons/react";

const examples = [
  {
    name: "Focus timer",
    detail: "Start a focus session without opening another app.",
  },
  {
    name: "Sticky note",
    detail: "Write a reminder. This demo saves it in your browser.",
  },
  { name: "Clock", detail: "Your local time, always in view." },
];

function FocusTimer() {
  const [remaining, setRemaining] = useState(25 * 60);
  const [running, setRunning] = useState(false);
  const endAt = useRef(0);
  useEffect(() => {
    if (!running) return;
    const tick = () => {
      const next = Math.max(0, Math.ceil((endAt.current - Date.now()) / 1000));
      setRemaining(next);
      if (!next) setRunning(false);
    };
    tick();
    const interval = setInterval(tick, 250);
    return () => clearInterval(interval);
  }, [running]);
  function toggle() {
    if (running) {
      setRunning(false);
      return;
    }
    const seconds = remaining || 25 * 60;
    setRemaining(seconds);
    endAt.current = Date.now() + seconds * 1000;
    setRunning(true);
  }
  function reset() {
    setRunning(false);
    setRemaining(25 * 60);
  }
  const value = `${String(Math.floor(remaining / 60)).padStart(2, "0")}:${String(remaining % 60).padStart(2, "0")}`;
  return (
    <>
      <div className="timer-face">
        <span
          className="timer-ring"
          style={{ "--progress": `${(remaining / 1500) * 360}deg` }}
          aria-hidden="true"
        />
        <div>
          <span
            className="widget-value"
            aria-label={`${Math.floor(remaining / 60)} minutes ${remaining % 60} seconds remaining`}
          >
            {value}
          </span>
          <span className="widget-caption">
            {remaining === 0
              ? "Session complete"
              : running
                ? "Focusing"
                : "Focus"}
          </span>
        </div>
      </div>
      <div className="widget-actions">
        <button
          onClick={toggle}
          aria-label={running ? "Pause focus timer" : "Start focus timer"}
        >
          {running ? <PauseIcon weight="fill" /> : <PlayIcon weight="fill" />}
          <span>
            {running ? "Pause" : remaining === 1500 ? "Start focus" : "Resume"}
          </span>
        </button>
        <button
          className="reset-timer"
          onClick={reset}
          aria-label="Reset focus timer"
        >
          <ArrowCounterClockwiseIcon />
        </button>
      </div>
    </>
  );
}

function StickyNote() {
  const [note, setNote] = useState("Ship something good.");
  const [storage, setStorage] = useState("loading");
  useEffect(() => {
    try {
      setNote(
        localStorage.getItem("opendoc-demo-note") ?? "Ship something good.",
      );
      setStorage("ready");
    } catch {
      setStorage("unavailable");
    }
  }, []);
  function edit(event) {
    const value = event.target.value;
    setNote(value);
    try {
      localStorage.setItem("opendoc-demo-note", value);
      setStorage("ready");
    } catch {
      setStorage("unavailable");
    }
  }
  return (
    <>
      <label className="sr-only" htmlFor="demo-note">
        Your sticky note
      </label>
      <textarea
        id="demo-note"
        value={note}
        onChange={edit}
        maxLength={160}
        spellCheck="false"
        placeholder="Write something to remember."
      />
      <span className="note-hint">
        {storage === "unavailable"
          ? "Saved for this visit"
          : "Click to edit. Saved here."}
      </span>
    </>
  );
}

function LocalClock() {
  const [now, setNow] = useState(null);
  useEffect(() => {
    const update = () => setNow(new Date());
    update();
    const timer = setInterval(update, 1000);
    return () => clearInterval(timer);
  }, []);
  return (
    <>
      <div>
        <span className="widget-value">
          {now
            ? new Intl.DateTimeFormat(undefined, {
                hour: "2-digit",
                minute: "2-digit",
                hour12: false,
              }).format(now)
            : "16:14"}
        </span>
        <span className="widget-caption">Local time</span>
      </div>
      <span className="clock-date">
        {now
          ? new Intl.DateTimeFormat(undefined, {
              weekday: "long",
              month: "short",
              day: "numeric",
            }).format(now)
          : "Your day, at a glance"}
      </span>
    </>
  );
}

export default function Widgets() {
  const [active, setActive] = useState(0);
  const shelf = useRef(null);
  function select(index) {
    setActive(index);
    const target = shelf.current?.children[index];
    if (!target) return;
    if (matchMedia("(max-width: 767px)").matches) {
      shelf.current.scrollTo({
        left: target.offsetLeft - shelf.current.offsetLeft,
        behavior:
          matchMedia("(prefers-reduced-motion: reduce)").matches ||
          document.querySelector('[data-motion="paused"]')
            ? "instant"
            : "smooth",
      });
    }
  }
  function keyboard(event) {
    const index =
      event.key === "ArrowRight"
        ? (active + 1) % 3
        : event.key === "ArrowLeft"
          ? (active + 2) % 3
          : event.key === "Home"
            ? 0
            : event.key === "End"
              ? 2
              : null;
    if (index === null) return;
    event.preventDefault();
    select(index);
    document.getElementById(`widget-tab-${index}`)?.focus();
  }
  useEffect(() => {
    const root = shelf.current;
    const observer = new IntersectionObserver(
      (entries) => {
        if (!matchMedia("(max-width: 767px)").matches) return;
        const visible = entries.find((entry) => entry.isIntersecting);
        if (visible) setActive(Number(visible.target.dataset.index));
      },
      { root, threshold: 0.75 },
    );
    [...root.children].forEach((card) => observer.observe(card));
    return () => observer.disconnect();
  }, []);
  return (
    <section
      className="widgets section"
      id="widgets"
      aria-labelledby="widgets-title"
    >
      <div className="widget-landscape" />
      <div className="wrap">
        <div data-reveal>
          <h2 id="widgets-title">
            Small widgets.
            <br />
            Less switching.
          </h2>
          <p className="intro">
            A timer, a note, a quick check. Keep useful things in the dock.
          </p>
        </div>
        <div className="widget-stage">
          <div
            className="live-shelf"
            ref={shelf}
            role="group"
            aria-label="Interactive widget examples"
          >
            <article
              className="live-widget focus-widget"
              data-index="0"
              data-active={active === 0}
              aria-label="Focus timer example"
              onFocus={() => setActive(0)}
            >
              <FocusTimer />
            </article>
            <article
              className="live-widget note-widget"
              data-index="1"
              data-active={active === 1}
              aria-label="Sticky note example"
              onFocus={() => setActive(1)}
            >
              <StickyNote />
            </article>
            <article
              className="live-widget clock-widget"
              data-index="2"
              data-active={active === 2}
              aria-label="Clock example"
            >
              <LocalClock />
            </article>
          </div>
        </div>
        <div className="widget-controls">
          <div
            className="line-tabs"
            role="tablist"
            aria-label="Widget examples"
            onKeyDown={keyboard}
          >
            {examples.map((example, i) => (
              <button
                key={example.name}
                role="tab"
                id={`widget-tab-${i}`}
                tabIndex={active === i ? 0 : -1}
                aria-selected={active === i}
                aria-controls="widget-description"
                onClick={() => select(i)}
              >
                {example.name}
              </button>
            ))}
          </div>
          <div className="carousel-arrows">
            <button
              className="icon-button"
              aria-label="Previous widget"
              onClick={() => select((active + 2) % 3)}
            >
              <ArrowLeftIcon />
            </button>
            <button
              className="icon-button"
              aria-label="Next widget"
              onClick={() => select((active + 1) % 3)}
            >
              <ArrowRightIcon />
            </button>
          </div>
        </div>
        <p
          className="widget-description"
          id="widget-description"
          role="tabpanel"
          aria-labelledby={`widget-tab-${active}`}
          aria-live="polite"
        >
          {examples[active].detail}
        </p>
        <p className="demo-caption">
          Try them here. Add them to your Mac with Open Doc.
        </p>
        <noscript>
          <p className="demo-caption">
            Enable JavaScript to try these widgets. Downloads and guides work
            without it.
          </p>
        </noscript>
        <div
          className="widget-marquee"
          role="group"
          aria-label="Available widgets: clocks, focus timers, sticky notes, checklists, calendars"
        >
          <div className="marquee-track" aria-hidden="true">
            {[0, 1].map((copy) => (
              <div className="marquee-set" key={copy}>
                {[
                  [ClockIcon, "Clocks"],
                  [TimerIcon, "Focus timers"],
                  [NoteIcon, "Sticky notes"],
                  [CheckSquareIcon, "Checklists"],
                  [CalendarBlankIcon, "Calendars"],
                ].map(([Icon, label]) => (
                  <span key={label}>
                    <Icon />
                    {label}
                  </span>
                ))}
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
