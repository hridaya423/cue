import { Mark } from "./Mark";

export function Header({ home = "" }: { home?: string }) {
  return (
    <header className="site-header is-flood">
      <a className="logo" href={`${home}#top`} aria-label="Cue, back to top">
        <Mark className="logo__svg" />
      </a>
      <nav className="nav" aria-label="Main">
        <a className="nav__link" href={`${home}#privacy`}>Privacy</a>
        <a className="button button--small" href="/downloads/Cue.dmg" download>Download</a>
      </nav>
    </header>
  );
}
