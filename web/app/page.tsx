import { Header } from "@/components/Header";
import { Mark, Runs } from "@/components/Mark";
import Motion from "@/components/Motion";

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Cue",
  operatingSystem: "macOS 15 or later",
  applicationCategory: "UtilitiesApplication",
  description: "A clipboard for Mac that pastes the part of what you copied that fits the focused field.",
  downloadUrl: "https://cue.app/downloads/Cue.dmg",
};

const tape = (placeholder: string, text: string) => (
  <span className="pii">
    <span className="pii__c"><span>{placeholder}</span></span>
    <span className="pii__t">{text}</span>
  </span>
);

export default function Home() {
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
      <div className="intro" aria-hidden="true">
        <div className="intro__ground" />
        <div className="intro__mark" />
        <div className="intro__track"><div className="intro__fill" /></div>
      </div>

      <Header />

      <main id="main" tabIndex={-1}>
        <section className="lead" id="top" aria-labelledby="hero-title">
          <div className="lead__copy">
            <h1 id="hero-title" className="lead__title">A better instinct for&nbsp;paste.</h1>
            <p className="lead__lede">Cue reads the field you&apos;re in and pastes the part of your clipboard that fits.</p>
            <a className="button button--large button--paper" href="/downloads/Cue.dmg" download>Download for Mac</a>
          </div>

          <figure className="desk" aria-label="In a chat channel, Nadia writes: Can you loop in Priya on the brief? Her email is priya.shah@kiln.studio and her number is 020 7946 0321. The message is copied. In the To field of a new email, only the address priya.shah@kiln.studio is pasted.">
            <div className="doc chat" aria-hidden="true">
              <div className="chat__bar">
                <span className="win__lights"><i /><i /><i /></span>
                <span className="chat__search">Search Kiln Studio</span>
              </div>
              <div className="chat__side">
                <p className="chat__ws">Kiln Studio</p>
                <span className="chat__ch"># general</span>
                <span className="chat__ch is-on"># kiln-brief</span>
                <span className="chat__ch"># design</span>
                <span className="chat__dm"><i />Nadia Brooks</span>
                <span className="chat__dm"><i />Ola Bassey</span>
              </div>
              <div className="chat__main">
                <p className="chat__head"><span># kiln-brief</span><span className="chat__people"><i /><i /><i />4</span></p>
                <p className="chat__day"><span>Today</span></p>
                <div className="chat__msg">
                  <span className="chat__face chat__face--o">O</span>
                  <p className="chat__meta"><b>Ola Bassey</b><span>10:31</span></p>
                  <p className="chat__text">Draft&apos;s in the folder. Final copy by Thursday.</p>
                  <span className="chat__react">👍 2</span>
                </div>
                <div className="chat__msg">
                  <span className="chat__face">N</span>
                  <p className="chat__meta"><b>Nadia Brooks</b><span>10:42</span></p>
                  <p className="chat__text chat__pick">Can you loop in Priya on the brief? Her email is <span className="cut">priya.shah@kiln.studio</span> and her number is 020&nbsp;7946&nbsp;0321.</p>
                </div>
                <p className="chat__box"><span className="chat__fmt"><b>B</b><i>I</i><s>S</s></span><span>Message #kiln-brief</span></p>
              </div>
            </div>
            <div className="form mail" aria-hidden="true">
              <p className="mail__bar"><span>New Message</span><i /><i /><i /></p>
              <span className="form__field mail__row"><span className="form__label">To</span><span className="form__box"><span className="form__value" /></span><span className="mail__cc">Cc Bcc</span></span>
              <span className="mail__row">The Kiln brief</span>
              <span className="mail__body">Hi Priya,<br /><br />Nadia said you&apos;d want the brief before Thursday. It&apos;s attached.</span>
              <span className="mail__foot">
                <span className="form__send"><span>Send</span><i /></span>
                <svg viewBox="0 0 24 24"><path d="M7 16.5 12 5l5 11.5M8.8 12.5h6.4M5 20h14" /></svg>
                <svg viewBox="0 0 24 24"><path d="M21 11.5 12.5 20a5 5 0 0 1-7-7L14 4.5a3.3 3.3 0 0 1 4.7 4.7l-8.6 8.6a1.7 1.7 0 0 1-2.4-2.4l7.8-7.8" /></svg>
                <svg viewBox="0 0 24 24"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" /></svg>
                <svg className="mail__trash" viewBox="0 0 24 24"><path d="M4 7h16M9 7V4.5h6V7M6.5 7l1 13h9l1-13M10 11v5.5M14 11v5.5" /></svg>
              </span>
            </div>
            <span className="keys" aria-hidden="true"><kbd>⌘</kbd><kbd>C</kbd></span>
            <span className="keys" aria-hidden="true"><kbd>⌘</kbd><kbd>V</kbd></span>
            <span className="ptr" aria-hidden="true">
              <svg className="ptr__arrow" viewBox="0 0 24 24"><path d="M5 2.5v16.2l3.9-3.7 2.4 5.7 2.9-1.2-2.4-5.6h5.6z" /></svg>
              <svg className="ptr__beam" viewBox="0 0 24 24"><path className="o" d="M9 3.5c1.6 0 2.5.5 3 1.3.5-.8 1.4-1.3 3-1.3M9 20.5c1.6 0 2.5-.5 3-1.3.5.8 1.4 1.3 3 1.3M12 4.8v14.4M10.3 12h3.4" /><path d="M9 3.5c1.6 0 2.5.5 3 1.3.5-.8 1.4-1.3 3-1.3M9 20.5c1.6 0 2.5-.5 3-1.3.5.8 1.4 1.3 3 1.3M12 4.8v14.4M10.3 12h3.4" /></svg>
            </span>
          </figure>
        </section>

        <section className="pv" id="privacy" aria-labelledby="pv-title">
          <div className="pv__hold">
            <div className="pv__copy">
              <h2 className="pv__title" id="pv-title">Private by default.</h2>
              <ul className="pv__rules">
                <li>Password fields stay unread.</li>
                <li>Hosted models see placeholders, not names.</li>
                <li>Images and files pass straight through.</li>
                <li>History stays on your Mac.</li>
              </ul>
            </div>
            <figure className="pv__paper" aria-label="A copied note as a hosted model sees it: Call [GIVEN_NAME_1] [SURNAME_1] on [PHONE_1] about the return, or write to [BUILDING_NUMBER_1] [STREET_NAME_1], [CITY_1].">
              <div className="pv__sheet">
                <p className="pv__note" aria-hidden="true">
                  Call {tape("[GIVEN_NAME_1]", "Maya")} {tape("[SURNAME_1]", "Okafor")} on {tape("[PHONE_1]", "020 7946 0321")}
                  <br className="pv__br" /> about the return, or write to<br className="pv__br" /> {tape("[BUILDING_NUMBER_1]", "14")}{" "}
                  {tape("[STREET_NAME_1]", "Kiln Yard")}, {tape("[CITY_1]", "London")}.
                </p>
              </div>
            </figure>
          </div>
          <div className="pv__seam" aria-hidden="true">
            {Array.from({ length: 9 }, (_, i) => <i key={i} />)}
          </div>
          <div className="pv__local">
            <div className="pv__local-copy">
              <p className="pv__close-line">Or keep every decision on your&nbsp;Mac.</p>
              <p className="pv__fig">
                <span className="pv__fig-num">0.7&nbsp;GB</span>
                <span className="pv__fig-label">The memory the recommended model uses.</span>
              </p>
            </div>
            <figure className="pv__lap">
              <img
                src="/media/local.webp"
                srcSet="/media/local-800.webp 800w, /media/local.webp 1589w"
                sizes="(max-width: 899px) 100vw, 62vw"
                width={1589}
                height={990}
                loading="lazy"
                decoding="async"
                alt="A laptop folded from white paper. Its cobalt screen shows the Cue mark."
              />
              <svg className="pv__screen" viewBox="0 0 1589 990" aria-hidden="true" focusable="false">
                <g transform="matrix(0.8888 -0.0708 -0.2080 0.9579 903.0 422.9)"><Runs /></g>
              </svg>
            </figure>
          </div>
        </section>
      </main>

      <footer className="close" aria-labelledby="close-title">
        <div className="close__copy">
          <h2 id="close-title" className="close__title">Paste the part that fits.</h2>
          <a className="button button--large" href="/downloads/Cue.dmg" download>Download for Mac</a>
        </div>
        <Mark className="close__mark" />
        <div className="close__bar">
          <a className="logo" href="#top" aria-label="Cue, back to top"><Mark className="logo__svg" /></a>
          <nav className="nav" aria-label="Footer">
            <a className="nav__link" href="#privacy">Privacy</a>
          </nav>
        </div>
      </footer>

      <Motion />
    </>
  );
}
