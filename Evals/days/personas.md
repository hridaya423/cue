# Persona days

Three workdays for the smart-paste benchmark. Each day is a Monday: 2026-10-19, 09:00 to 18:30.
Each persona presses ⌘V the way a real person does. The benchmark asks one question per paste:
did the right text land with no visible step, or did plain ⌘V happen as if Cue were absent?

Files:

- `surfaces.json` lists every place a persona copies from or pastes into.
- `pages/*.html` holds the web surfaces. Each page keeps the real accessible structure and nearby text.
- `recruiter.jsonl`, `engineer.jsonl`, `founder.jsonl` hold the traces.
- `check.py` validates all of it: `python3 -I Evals/days/check.py`.

## Renata Alvarez, technical recruiter

**Job.** Recruiter at Acme Robotics, a 40-person warehouse-robotics startup. She runs several searches at once.

**Apps.** Gmail and Greenhouse in Chrome. Google Calendar and a Calendly-style booking page. LinkedIn. Slack. Notes. Messages.

**Rhythm.** She clears the overnight replies between 09:00 and 09:30. She builds profiles, sends the same booking link three times, then sends cold outreach. A hiring sync takes 10:40 to 11:00. The CEO approves an offer at 11:00, and the offer letter must go out by 17:00. She debriefs a finished interview loop after lunch. She ends the day with confirmations and a list for tomorrow.

**What she copies and why.** Emails, phone numbers and LinkedIn URLs come out of candidate signatures. She copies the booking link, an outreach template, a reference-check template and the office address. Offer numbers come from a Slack message. Greenhouse URLs go to the hiring manager.

**What annoys her.** The booking link is the clip she needs most, and it is never the latest one. She pastes it into Dev, Samir and Imani in a row, then four hours later for Nikhil. Between those two moments she copies 19 other things. She also copies a whole Slack message when she needs one email out of it.

## Kofi Mensah, backend engineer

**Job.** Backend engineer at Halyard, a payments company. He owns the ledger service. Today he fixes HAL-482, a bug where a retried transfer inserts a second ledger entry. The fix ships and an incident channel opens in the afternoon.

**Apps.** Terminal.app and VS Code. Slack. GitHub pull requests. Linear. Sentry. A prod-access page that asks for a device code.

**Rhythm.** He reproduces the bug before 09:30. He reviews a teammate's pull request mid-morning. He opens his own pull request before lunch. The incident starts at 13:00. CI fails at 14:00. He merges, deploys and posts the result by 17:30.

**What he copies and why.** Commands, the Linear branch name, the SHA, constraint names, error lines, stack traces, request ids, JSON responses, a SQL query, and links to pull requests, commits, Sentry and Slack threads.

**What annoys him.** Terminal and editor fields tell Cue almost nothing. The terminal has no label. The editor label is a generic accessibility message. He often wants a command from hours ago. By 18:05 the repro `curl` command is the 29th clip in history.

## Ines Okoye, seed-stage founder

**Job.** CEO of Brindle, which sells demand forecasting to independent grocers. She is closing a seed round with a lead, a second fund and an angel.

**Apps.** Gmail, a Notion investor update, an investor CRM, a data room, a bank onboarding form, a payroll signup form, Stripe, Slack with her co-founder, Notes for wire details and company facts, Messages for the angel.

**Rhythm.** She builds the quarterly update from Stripe numbers first. The lead investor asks for wire details at 09:25. She logs investors in the CRM and sends her scheduling link to three people. After lunch she fills bank and payroll forms field by field from a Notes block. The signature pages come in at 14:15. The update goes out at 15:35. She closes with investor replies and the checklist.

**What she copies and why.** Wire details, a company facts block, investor emails and phones, her calendar link, the deck and data-room links, Stripe figures, the DocuSign link, and a Bcc list.

**What annoys her.** She keeps one Notes file of facts and re-enters them in every form. The same wire block goes to two different people, once at 09:28 and again at 16:25. The Notes block holds six facts for the forms, so each form field needs its own copy.

## Trace conventions

- A copy moves its text to the front of history. A repeat copy dedupes, as `Clip.id` is a hash of the text.
- `latest` means the wanted string is clip 1. `earlier` means the wanted string is a whole clip, 2 or more back. `part` means the wanted string is a strict substring of a clip.
- `plain` marks a field where nothing in history fits and the latest clip is what the persona expects: OTP boxes, a search box, a command palette. `choose` marks two acceptable answers where a human would also pause.
- `secure` events have no copy before them. A password manager fills the field. The benchmark only checks that Cue stays out of it. Each secure event carries an extra `why` key for readers.
- Part strings are mostly email, phone or URL spans, which `SpanExtractor` can find. Some are not: offer salary `185,000`, a constraint name, a SHA, a request id, an account number. Cue cannot extract these today. The traces keep them because the persona really does this.
- Each day has about one `earlier` clip beyond `OptionBuilder.recentWindow` (20 clips, no pins): the `curl` repro 29 back, the wire block 23 back, the careers URL 21 back. Cue cannot return these. Spotlight can. `check.py` reports the count.
- `value_before` for Terminal and VS Code is the line the persona typed. Real Terminal AXValue is the scrollback, and `ContextCaptor` keeps only its first 200 characters. A driver that wants exact parity must decide what to put in those fields.
- Web pages carry every copied string on the page as a selectable `.clip` block, so a live driver can select the real text.

## Counts

| persona | events | copies | pastes | latest | earlier | part | plain | choose | secure |
|---|---|---|---|---|---|---|---|---|---|
| recruiter | 77 | 31 | 46 | 28 (61%) | 8 (17%) | 5 (11%) | 2 | 2 | 1 |
| engineer | 76 | 31 | 45 | 28 (62%) | 8 (18%) | 5 (11%) | 2 | 1 | 1 |
| founder | 75 | 32 | 43 | 29 (67%) | 5 (12%) | 5 (12%) | 2 | 1 | 1 |

## Fidelity: what is checked and what is memory

Most accessible names below come from memory of each product, not from a live inspection.
I could not verify them in this session. The Cue live lane should dump the real AX tree with the `--dump-ax` flag of CueDay before it trusts any of them.

| surface | structure used | status |
|---|---|---|
| Gmail compose | `input[aria-label="To recipients"]` role combobox, `input[name=subjectbox][aria-label=Subject]`, `div[aria-label="Message Body"][role=textbox][contenteditable]`, `aria-label="Search mail"` | partly sourced: three forum and playbook pages agree on `Message Body`, `subjectbox` and `To recipients`. `Cc recipients` and `Bcc recipients` follow the same pattern but are not sourced |
| Greenhouse | `<label for>` with First Name, Last Name, Email, Phone, Website | the public application page confirms the label names. The internal ATS forms (add candidate, offer, note) are Greenhouse-like and invented |
| GitHub | `Comment body` and `Add a title` | memory only. The login page fetched with curl does use `<label for="login_field">`, which matches the pattern |
| Slack | `contenteditable` role textbox, `aria-label` `Message #channel` or `Message Person` | follows the brief. Real Slack may say `Message to #channel`. Whether Slack exposes a placeholder to AX is unknown. The pages use `data-placeholder` only |
| Linear, Notion, Calendly, Google Calendar, Attio, DocSend, Gusto, Stripe | role and label guesses | memory only |
| Terminal.app | `AXTextArea`, no label | follows the brief. My memory says Terminal may expose `AXDescription` of `shell`. Check it |
| VS Code editor | label `The editor is not accessible at this time. Press Option+F1 for more options.` | memory of the Monaco default when no screen reader is detected. Electron may report `Editor content` once an AX client attaches |
| VS Code SCM and search | `Source Control Input`; `Search: Type Search Term and press Enter to search` with placeholder `Search` | memory only. Monaco placeholders are decorations, so the SCM placeholder is empty |

Pages are static HTML. They contain no scripts and no external requests. `check.py` enforces both.

## Sources

- Gmail selectors: [Keyboard Maestro forum, automate Gmail compose](https://forum.keyboardmaestro.com/t/how-do-i-automate-fill-of-gmail-compose-form/5287), [Keyboard Maestro forum, fill Gmail body](https://forum.keyboardmaestro.com/t/javascript-to-fill-in-gmail-body-with-variable/9364), [a Gmail skill listing with the three selectors](https://playbooks.com/skills/different-ai/agent-bank/gmail-chrome).
- Greenhouse application fields: [public job-board page](https://job-boards.greenhouse.io/pandadoc/jobs/7276406). Its HTML uses `<label for>` plus `aria-label` on inputs. The search found no raw markup for the application form itself.
- GitHub sign-in label: fetched a GitHub sign-in page with curl. Its labels are `login_field` and `password`.
- Searches for Slack, GitHub pull request, and VS Code markup returned nothing usable.

## Surprises

- `ClipboardMonitor` has no filter for concealed or transient pasteboard types (`org.nspasteboard.ConcealedType` and similar). A password-manager copy would land in `history.json` as plain text. The traces avoid this by never copying a password.
- The day is Monday so that `Thu 10/22` and `Mon Nov 16` in the clips are real weekdays.
