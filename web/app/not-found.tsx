import type { Metadata } from "next";
import { Header } from "@/components/Header";

export const metadata: Metadata = {
  title: "Nothing here fits | Cue",
  description: "This page doesn't exist. Head back to Cue.",
};

const showPath = `{const t=decodeURIComponent(location.pathname);document.getElementById("lost-path").textContent=t.length>40?t.slice(0,39)+"…":t}`;

export default function NotFound() {
  return (
    <>
      <Header home="/" />
      <main id="main" className="lost" tabIndex={-1}>
        <div className="lost__copy">
          <h1 className="lost__title">Nothing here fits.</h1>
          <p className="lost__lede">That page isn&apos;t in the clipboard.</p>
          <a className="button button--large button--paper" href="/">Back to Cue</a>
        </div>
        <div className="lost__stage" aria-hidden="true">
          <div className="lost__sheet">
            <span className="lost__field"><span className="lost__ph">Page</span><span className="lost__caret" /></span>
            <span className="lost__strip" id="lost-path" suppressHydrationWarning>/</span>
          </div>
        </div>
      </main>
      <script dangerouslySetInnerHTML={{ __html: showPath }} />
    </>
  );
}
