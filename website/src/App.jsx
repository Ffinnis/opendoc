import React, {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import {
  IconContext,
  ArrowUpRightIcon,
  GithubLogoIcon,
  SunIcon,
  MoonIcon,
  CheckIcon,
  CopyIcon,
  CaretDownIcon,
  CommandIcon,
  PauseIcon,
  PlayIcon,
} from "@phosphor-icons/react";
import Widgets from "./Widgets.jsx";
import "./styles.css";

function Reveal({ children, className = "" }) {
  return (
    <div data-reveal className={className}>
      {children}
    </div>
  );
}

function ScrubText({ children, className = "" }) {
  return (
    <p className={className} data-scrub-text>
      <span>
        {children.split(" ").map((word, i) => (
          <React.Fragment key={i}>
            <span className="scrub-word">{word}</span>{" "}
          </React.Fragment>
        ))}
      </span>
    </p>
  );
}

const repo = "https://github.com/Ffinnis/opendoc";
const guide = `${repo}/blob/main/docs/Using-Open-Doc.md`;
const cliGuide = `${repo}/blob/main/Examples/Agent-CLI.md`;
const assetUrl = (name) => `${import.meta.env.BASE_URL}assets/${name}`;

function Download() {
  return (
    <a className="download" href={`${repo}/releases`}>
      <svg
        className="download-logo"
        width="21"
        height="24"
        viewBox="-2 -2 28 28"
        fill="currentColor"
        aria-hidden="true"
        focusable="false"
      >
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
      </svg>
      <span>Download for Mac</span>
    </a>
  );
}

const ThemeContext = createContext({ dark: false, toggle: () => {} });

function ThemeProvider({ children }) {
  const [theme, setTheme] = useState("system");
  const [systemDark, setSystemDark] = useState(false);
  const [ready, setReady] = useState(false);
  const dark = theme === "dark" || (theme === "system" && systemDark);
  useEffect(() => {
    try {
      const saved = localStorage.getItem("opendoc-theme");
      setTheme(saved === "light" || saved === "dark" ? saved : "system");
    } catch {}
    setReady(true);
    const query = matchMedia("(prefers-color-scheme: dark)");
    const update = () => setSystemDark(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    if (!ready) return;
    if (theme === "system") delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = theme;
  }, [theme, ready]);
  function toggle() {
    const next = dark ? "light" : "dark";
    setTheme(next);
    try {
      localStorage.setItem("opendoc-theme", next);
    } catch {}
  }
  return (
    <ThemeContext.Provider value={{ dark, toggle, ready }}>
      {children}
    </ThemeContext.Provider>
  );
}

function ThemeToggle() {
  const { dark, toggle } = useContext(ThemeContext);
  return (
    <button
      className="icon-button"
      onClick={toggle}
      aria-label={`Switch to ${dark ? "light" : "dark"} theme`}
    >
      {dark ? <SunIcon /> : <MoonIcon />}
    </button>
  );
}

function Brand() {
  return (
    <a className="brand" href="#top">
      <img src={assetUrl("opendoc.png")} width="38" height="38" alt="" />
      Open Doc
    </a>
  );
}

function DockImage({
  className = "",
  alt = "A populated Open Doc preview with colorful Mac apps, grouped folders, a clock, focus timer, and sticky note",
}) {
  return (
    <div className={`dock-art ${className}`}>
      <img
        src={assetUrl("populated-dock.webp")}
        srcSet={`${assetUrl("populated-dock-1680.webp")} 1680w, ${assetUrl("populated-dock.webp")} 2172w`}
        sizes="(max-width: 767px) 940px, 91vw"
        fetchPriority="low"
        width="2172"
        height="724"
        alt={alt}
      />
    </div>
  );
}

function ProductImage({ asset, alt }) {
  const { dark, ready } = useContext(ThemeContext);
  return (
    <picture>
      <source
        media={
          ready ? (dark ? "all" : "not all") : "(prefers-color-scheme: dark)"
        }
        srcSet={assetUrl(`${asset}-dark.webp`)}
      />
      <img
        src={assetUrl(`${asset}.webp`)}
        width="2172"
        height="724"
        alt={alt}
        loading="lazy"
        fetchPriority="low"
      />
    </picture>
  );
}

function Hero({ paused, onToggleMotion }) {
  return (
    <section className="hero" id="top" aria-labelledby="hero-title">
      <div className="hero-backdrop">
        <img
          src={assetUrl("coast.webp")}
          alt=""
          width="1672"
          height="941"
          fetchPriority="high"
        />
      </div>
      <header className="header wrap">
        <Brand />
        <nav aria-label="Main navigation">
          <a href="#features">Features</a>
          <a href={guide}>Read guide</a>
        </nav>
        <div className="header-right">
          <button
            className="icon-button motion-toggle"
            onClick={onToggleMotion}
            aria-label={paused ? "Enable animations" : "Pause animations"}
            aria-pressed={paused}
          >
            {paused ? <PlayIcon /> : <PauseIcon />}
          </button>
          <ThemeToggle />
          <a className="github" href={repo} aria-label="Open Doc on GitHub">
            <GithubLogoIcon weight="fill" />
            <span>GitHub</span>
          </a>
        </div>
      </header>
      <div className="hero-copy max-w-6xl">
        <h1 id="hero-title">
          <span className="hero-title-line">A dock of</span>
          <span className="hero-title-line">your own.</span>
        </h1>
        <p>Apps, folders, and widgets. Right where you need them.</p>
        <div className="hero-actions">
          <Download />
          <a className="secondary-action" href="#widgets">
            Try the widgets
            <ArrowUpRightIcon />
          </a>
        </div>
      </div>
      <div className="hero-dock-wrap">
        <div
          className="dock-scroll"
          tabIndex={0}
          role="region"
          aria-label="Example dock with apps and widgets"
        >
          <DockImage />
        </div>
      </div>
      <div className="hero-foot wrap">
        <span>Free and open source</span>
        <span>macOS 14+</span>
      </div>
    </section>
  );
}

const groups = [
  { label: "Everyday", description: "Keep related apps together." },
  {
    label: "Development",
    description:
      "Give your editor, terminal, and project tools a folder of their own.",
  },
  {
    label: "Creative",
    description:
      "Keep design and creative tools together, or create a separate dock for them.",
  },
];

function Organization() {
  const [active, setActive] = useState(0);
  function keyboard(event) {
    let next;
    if (event.key === "ArrowRight") next = (active + 1) % groups.length;
    else if (event.key === "ArrowLeft")
      next = (active + groups.length - 1) % groups.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = groups.length - 1;
    else return;
    event.preventDefault();
    setActive(next);
    document.getElementById(`group-${next}`)?.focus();
  }
  return (
    <section
      className="organization wrap section"
      id="features"
      aria-labelledby="organization-title"
    >
      <Reveal className="organization-visual">
        <div className="group-art">
          <ProductImage
            asset="app-groups"
            alt="Three complete app folders containing messaging, development, and creative tools"
          />
        </div>
        <div
          className="line-tabs"
          role="tablist"
          aria-label="App groups"
          onKeyDown={keyboard}
        >
          {groups.map((group, i) => (
            <button
              key={group.label}
              role="tab"
              id={`group-${i}`}
              tabIndex={active === i ? 0 : -1}
              aria-selected={active === i}
              aria-controls="group-description"
              onClick={() => setActive(i)}
            >
              {group.label}
            </button>
          ))}
        </div>
        <div
          className="group-description"
          key={active}
          id="group-description"
          role="tabpanel"
          tabIndex={0}
          aria-labelledby={`group-${active}`}
        >
          <p>{groups[active].description}</p>
        </div>
      </Reveal>
      <Reveal className="organization-copy">
        <h2 id="organization-title">
          A place for
          <br />
          every app.
        </h2>
        <ScrubText>
          Group your apps. Keep separate docks for work, personal projects, and
          everything in between.
        </ScrubText>
        <a className="inline-link" href={guide}>
          Read guide
          <ArrowUpRightIcon />
        </a>
      </Reveal>
    </section>
  );
}

function Appearance() {
  return (
    <section
      className="appearance wrap section"
      aria-labelledby="appearance-title"
    >
      <Reveal className="appearance-copy">
        <h2 id="appearance-title">
          Fits your screen.
          <br />
          Follows your taste.
        </h2>
        <div className="appearance-options">
          {[
            [
              "Position",
              "Bottom, left, or right. Give each dock its own place.",
            ],
            [
              "Glass & tint",
              "Choose glass style and tint. Native Liquid Glass on macOS 26, with blur on earlier versions.",
            ],
            [
              "Auto-hide",
              "Keep the dock out of the way until you move your pointer to its edge.",
            ],
          ].map(([title, body], i) => (
            <details name="appearance" key={title} open={i === 0}>
              <summary>
                {title}
                <CaretDownIcon />
              </summary>
              <p>{body}</p>
            </details>
          ))}
        </div>
      </Reveal>
      <Reveal className="appearance-image">
        <img
          src={assetUrl("settings-appearance.png")}
          width="700"
          height="576"
          alt="Open Doc's actual appearance settings for dock position, glass, tint, icon size, and auto-hide"
          loading="lazy"
        />
      </Reveal>
    </section>
  );
}

function Agents() {
  const [status, setStatus] = useState("idle");
  useEffect(() => {
    if (status !== "copied") return;
    const timer = setTimeout(() => setStatus("idle"), 2500);
    return () => clearTimeout(timer);
  }, [status]);
  async function copy() {
    try {
      await navigator.clipboard.writeText("opendoc schema");
      setStatus("copied");
    } catch {
      setStatus("error");
    }
  }
  return (
    <section
      className="agents wrap section"
      id="agents"
      aria-labelledby="agents-title"
    >
      <Reveal className="agents-heading">
        <span className="command-symbol">
          <CommandIcon size={30} />
        </span>
        <h2 id="agents-title">
          Ask for it.
          <br />
          Add it to your dock.
        </h2>
        <a className="inline-link" href={cliGuide}>
          Read the agent guide
          <ArrowUpRightIcon />
        </a>
      </Reveal>
      <Reveal className="agent-command">
        <p className="example-request">
          “Add a focus timer and a note for today.”
        </p>
        <div className="command-line">
          <code>opendoc schema</code>
          <button
            className="icon-button"
            onClick={copy}
            aria-label={status === "copied" ? "Command copied" : "Copy command"}
          >
            {status === "copied" ? <CheckIcon /> : <CopyIcon />}
          </button>
        </div>
        <p>
          Your agent can discover commands, validate edits, and update widgets.
        </p>
        <p className="copy-status" role="status">
          {status === "copied"
            ? "Copied to clipboard."
            : status === "error"
              ? "Select the command above to copy it."
              : "Launch Open Doc from Applications to install the CLI."}
        </p>
      </Reveal>
    </section>
  );
}

function Closing() {
  return (
    <section className="closing" aria-labelledby="closing-title">
      <Reveal className="closing-copy">
        <h2 id="closing-title">
          Make it{" "}
          <img
            className="inline-app-icon"
            src={assetUrl("opendoc.png")}
            width="96"
            height="96"
            alt=""
          />{" "}
          your dock.
        </h2>
        <p>Free. Open source. Built for macOS.</p>
        <Download />
        <span className="requirements">
          macOS 14+ · Apple silicon &amp; Intel
        </span>
        <details className="install-note">
          <summary>
            What happens to Apple’s Dock?
            <CaretDownIcon size={16} />
          </summary>
          <p>
            Open Doc imports your pinned apps and hides Apple’s Dock on first
            launch. Quit Open Doc or choose Restore Apple’s Dock to bring it
            back. Your original shortcuts stay unchanged.
          </p>
        </details>
      </Reveal>
      <footer className="footer wrap">
        <Brand />
        <nav aria-label="Footer navigation">
          <a href={repo}>GitHub</a>
          <a href={`${repo}/blob/main/LICENSE`}>MIT license</a>
          <a href={`${repo}/issues`}>Feedback</a>
        </nav>
      </footer>
    </section>
  );
}

export default function App() {
  const scope = useRef(null);
  const [paused, setPaused] = useState(false);
  const [Motion, setMotion] = useState(null);
  useEffect(() => {
    let alive = true;
    try {
      setPaused(localStorage.getItem("opendoc-motion-paused") === "true");
    } catch {}
    // Let the first view's font and backdrop finish before requesting motion.
    const backdrop = scope.current.querySelector(".hero-backdrop img");
    Promise.all([document.fonts.ready, backdrop.decode().catch(() => {})])
      .then(() => alive ? import("./motion.jsx") : null)
      .then((module) => {
        if (alive && module) setMotion(() => module.default);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, []);
  function toggleMotion() {
    const next = !paused;
    setPaused(next);
    try {
      localStorage.setItem("opendoc-motion-paused", String(next));
    } catch {}
  }
  return (
    <ThemeProvider>
      <IconContext.Provider value={{ size: 21, weight: "regular" }}>
        <a className="skip-link" href="#features">
          Skip to content
        </a>
        <main
          ref={scope}
          data-motion={paused ? "paused" : "enabled"}
          data-interactive={Motion ? "true" : undefined}
          className="w-full max-w-full"
        >
          <Hero paused={paused} onToggleMotion={toggleMotion} />
          <Organization />
          <Widgets />
          <Appearance />
          <Agents />
          <Closing />
          {Motion && <Motion scope={scope} paused={paused} />}
        </main>
      </IconContext.Provider>
    </ThemeProvider>
  );
}
