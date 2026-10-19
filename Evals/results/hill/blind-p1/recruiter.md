# recruiter: one workday, paste by paste

## step 1 — Creating Marisol's profile from her reply, first name
Field: gh_add_candidate#first_name · wanted: {"paste": "Marisol"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Marisol"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Marisol"

## step 2 — Last name
Field: gh_add_candidate#last_name · wanted: {"paste": "Reyes"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Reyes"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Reyes"

## step 3 — Email from her signature
Field: gh_add_candidate#email · wanted: {"paste": "marisol.reyes@example.org"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "marisol.reyes@example.org"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "marisol.reyes@example.org"

## step 4 — Phone from her signature
Field: gh_add_candidate#phone · wanted: {"paste": "(212) 555-0176"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "(212) 555-0176"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "(212) 555-0176"

## step 5 — LinkedIn goes in the website field
Field: gh_add_candidate#website · wanted: {"paste": "https://www.linkedin.com/in/marisol-reyes-4c82a1"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://www.linkedin.com/in/marisol-reyes-4c82a1"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://www.linkedin.com/in/marisol-reyes-4c82a1"

## step 6 — Saving Jonas's panel message on Marisol's profile
Field: gh_cand_marisol#note · wanted: {"paste": "@Renata Marisol can do the onsite Thu 10/22 after 2pm PT or any time Fri 10/23. Panel is Wen Zhao (wen.zhao@acme.example), Ilya Morozov (ilya.morozov@acme.example) and me. Please book the Birch room, we need the whiteboard."}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "@Renata Marisol can do the onsite Thu 10/22 after 2pm PT or any time Fri 10/23. Panel is Wen Zhao (wen.zhao@acme.example), Ilya Morozov (ilya.morozov@acme.ex\u2026"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "@Renata Marisol can do the onsite Thu 10/22 after 2pm PT or any time Fri 10/23. Panel is Wen Zhao (wen.zhao@acme.example), Ilya Morozov (ilya.morozov@acme.ex\u2026"

## step 7 — Inviting the panel to the onsite hold
Field: gcal_event#guests · wanted: {"paste": "wen.zhao@acme.example"}
- **A**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 7.22 s; landed: "@Renata Marisol can do the onsite Thu 10/22 after 2pm PT or any time Fri 10/23. Panel is Wen Zhao (wen.zhao@acme.example), Ilya Morozov (ilya.morozov@acme.ex\u2026"
- **B**: pressed ⌘Space ⌘4 type:rena Return ⌘V trim×4; waited 0 ms for the app; total ≈ 6.66 s; landed: "wen.zhao@acme.example"

## step 8 — Second panelist
Field: gcal_event#guests · wanted: {"paste": "ilya.morozov@acme.example"}
- **A**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 7.22 s; landed: "@Renata Marisol can do the onsite Thu 10/22 after 2pm PT or any time Fri 10/23. Panel is Wen Zhao (wen.zhao@acme.example), Ilya Morozov (ilya.morozov@acme.ex\u2026"
- **B**: pressed ⌘Space ⌘4 type:rena Return ⌘V trim×4; waited 0 ms for the app; total ≈ 6.66 s; landed: "ilya.morozov@acme.example"

## step 9 — Adding Marisol to the hold
Field: gcal_event#guests · wanted: {"paste": "marisol.reyes@example.org"}
- **A**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 4.75 s; landed: "@Renata Marisol can do the onsite Thu 10/22 after 2pm PT or any time Fri 10/23. Panel is Wen Zhao (wen.zhao@acme.example), Ilya Morozov (ilya.morozov@acme.ex\u2026"
- **B**: pressed ⌘Space ⌘4 type:exam Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "marisol.reyes@example.org"

## step 10 — Panelists get her LinkedIn in the invite description
Field: gcal_event#description · wanted: {"paste": "https://www.linkedin.com/in/marisol-reyes-4c82a1"}
- **A**: pressed ⌘Space ⌘4 type:http Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "https://www.linkedin.com/in/marisol-reyes-4c82a1"
- **B**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 4.75 s; landed: "@Renata Marisol can do the onsite Thu 10/22 after 2pm PT or any time Fri 10/23. Panel is Wen Zhao (wen.zhao@acme.example), Ilya Morozov (ilya.morozov@acme.ex\u2026"

## step 11 — Sending Dev the phone-screen booking link
Field: gmail_reply_dev#reply · wanted: {"paste": "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"

## step 12 — Same link for Samir
Field: gmail_reply_samir#reply · wanted: {"paste": "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"

## step 13 — Same link for Imani
Field: gmail_reply_imani#reply · wanted: {"paste": "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"

## step 14 — Nikhil's email from LinkedIn contact info
Field: gmail_compose#to · wanted: {"paste": "nikhil.rao@example.net"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "nikhil.rao@example.net"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "nikhil.rao@example.net"

## step 15 — Outreach template, placeholders get edited by hand
Field: gmail_compose#body · wanted: {"paste": "Hi {first_name},\n\nI'm Renata, a recruiter at Acme Robotics. We build warehouse picking arms, we're 40 people, and we're hiring a Senior Backend Engineer to own our fleet telemetry pipeline.\n\nYour work on streaming ingestion at {company} stood out. Would you be open to a 30 minute intro call this week or next?\n\nBest,\nRenata"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Hi {first_name},\n\nI'm Renata, a recruiter at Acme Robotics. We build warehouse picking arms, we're 40 people, and we're hiring a Senior Backend Engineer to o\u2026"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Hi {first_name},\n\nI'm Renata, a recruiter at Acme Robotics. We build warehouse picking arms, we're 40 people, and we're hiring a Senior Backend Engineer to o\u2026"

## step 16 — Adding the JD link under the template
Field: gmail_compose#body · wanted: {"paste": "https://acme.example/careers/senior-backend-engineer?gh_src=7c41d0b2"}
- **A**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 0.84 s; landed: "Hi {first_name},\n\nI'm Renata, a recruiter at Acme Robotics. We build warehouse picking arms, we're 40 people, and we're hiring a Senior Backend Engineer to o\u2026"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://acme.example/careers/senior-backend-engineer?gh_src=7c41d0b2"

## step 17 — Adding the phone from his signature
Field: gh_cand_dev#phone · wanted: {"paste": "+1 (415) 555-0143"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "+1 (415) 555-0143"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "+1 (415) 555-0143"

## step 18 — Answering her comp question from the band in her notes
Field: gmail_reply_imani#reply · wanted: {"paste": "$165,000 - $205,000 base plus equity, 4 weeks PTO, 2 remote days a week"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "$165,000 - $205,000 base plus equity, 4 weeks PTO, 2 remote days a week"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "$165,000 - $205,000 base plus equity, 4 weeks PTO, 2 remote days a week"

## step 19 — Reference's email from Tobias's reply
Field: gmail_compose#to · wanted: {"paste": "elise.mahoney@example.org"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "elise.mahoney@example.org"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "elise.mahoney@example.org"

## step 20 — Reference-check template
Field: gmail_compose#body · wanted: {"paste": "Hi Elise,\n\nTobias Lindqvist gave us your name as a reference for a Senior Backend Engineer role at Acme Robotics. Would you have 15 minutes for a call this week?\n\nThank you,\nRenata"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Hi Elise,\n\nTobias Lindqvist gave us your name as a reference for a Senior Backend Engineer role at Acme Robotics. Would you have 15 minutes for a call this w\u2026"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Hi Elise,\n\nTobias Lindqvist gave us your name as a reference for a Senior Backend Engineer role at Acme Robotics. Would you have 15 minutes for a call this w\u2026"

## step 21 — Base salary from Leila's approval
Field: gh_offer_aiko#salary · wanted: {"paste": "185,000"}
- **A**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 7.22 s; landed: "Approved for Aiko Tanaka (EM): base $185,000, 40,000 options (0.11%), $15,000 sign-on, start date Monday Nov 16. Offer letter has to go out by 5pm today."
- **B**: pressed ⌘Space ⌘4 type:appr Return ⌘V trim×4; waited 0 ms for the app; total ≈ 6.66 s; landed: "185,000"

## step 22 — Recording the approval on the offer
Field: gh_offer_aiko#notes · wanted: {"paste": "Approved for Aiko Tanaka (EM): base $185,000, 40,000 options (0.11%), $15,000 sign-on, start date Monday Nov 16. Offer letter has to go out by 5pm today."}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Approved for Aiko Tanaka (EM): base $185,000, 40,000 options (0.11%), $15,000 sign-on, start date Monday Nov 16. Offer letter has to go out by 5pm today."
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Approved for Aiko Tanaka (EM): base $185,000, 40,000 options (0.11%), $15,000 sign-on, start date Monday Nov 16. Offer letter has to go out by 5pm today."

## step 23 — Inviting Aiko to the offer call
Field: gcal_event#guests · wanted: {"paste": "aiko.tanaka@example.com"}
- **A**: pressed ⌘Space ⌘4 type:engi Return ⌘V trim×4; waited 0 ms for the app; total ≈ 6.66 s; landed: "aiko.tanaka@example.com"
- **B**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 7.22 s; landed: "Aiko Tanaka Engineering Manager, Quillfeather Inc. aiko.tanaka@example.com M: +1 (646) 555-0138"

## step 24 — Link in the email confirming the call
Field: gmail_reply_aiko#reply · wanted: {"paste": "https://meet.google.com/kqz-fhvw-dpm"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://meet.google.com/kqz-fhvw-dpm"
- **B**: pressed ⌘V; waited 12 ms for the app; total ≈ 0.29 s; landed: "https://meet.google.com/kqz-fhvw-dpm"

## step 25 — Giving Jonas Aiko's cell for his congratulations call
Field: slack_dm_jonas#message · wanted: {"paste": "+1 (646) 555-0138"}
- **A**: pressed ⌘Space ⌘4 type:engi Return ⌘V trim×4; waited 0 ms for the app; total ≈ 6.66 s; landed: "+1 (646) 555-0138"
- **B**: pressed ⌘V ⌘Z; waited 1 ms for the app; total ≈ 7.22 s; landed: "https://meet.google.com/kqz-fhvw-dpm"

## step 26 — Finding Imani's original application, name goes in the search box
Field: gmail_inbox#search · wanted: {"plain": true}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Imani Brooks"
- **B**: pressed ⌘V; waited 2 ms for the app; total ≈ 0.28 s; landed: "Imani Brooks"

## step 27 — 
Field: sso_login#password · wanted: {"plain": true}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Imani Brooks"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Imani Brooks"

## step 28 — SMS code from the short-code thread
Field: sso_login#otp · wanted: {"plain": true}
- **A**: pressed ⌘V; waited 2 ms for the app; total ≈ 0.28 s; landed: "482913"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "482913"

## step 29 — Booking on Dev's behalf, his email
Field: calendly_book#email · wanted: {"paste": "dev.patel@example.com"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "dev.patel@example.com"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "dev.patel@example.com"

## step 30 — His phone for the interviewer, from his signature this morning
Field: calendly_book#notes · wanted: {"paste": "+1 (415) 555-0143"}
- **A**: pressed ⌘Space ⌘4 type:0143 Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "+1 (415) 555-0143"
- **B**: pressed ⌘V ⌘Z; waited 43 ms for the app; total ≈ 4.79 s; landed: "dev.patel@example.com"

## step 31 — Elise's number for the reference call hold
Field: gcal_event#description · wanted: {"paste": "312-555-0199"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "312-555-0199"
- **B**: pressed ⌘V; waited 25 ms for the app; total ≈ 0.31 s; landed: "312-555-0199"

## step 32 — Adding Elise as a guest
Field: gcal_event#guests · wanted: {"paste": "elise.mahoney@example.org"}
- **A**: pressed ⌘Space ⌘4 type:maho Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "elise.mahoney@example.org"
- **B**: pressed ⌘V ⌘Z; waited 28 ms for the app; total ≈ 4.78 s; landed: "312-555-0199"

## step 33 — Debrief notes, Wen first
Field: gh_cand_tobias#note · wanted: {"paste": "My take on Tobias: great on the pipeline design question, he talked through backpressure and idempotent consumers without being asked. Solid Python, a bit light on Go but says he has shipped it. Strong hire from me."}
- **A**: pressed ⌘V; waited 46 ms for the app; total ≈ 0.33 s; landed: "My take on Tobias: great on the pipeline design question, he talked through backpressure and idempotent consumers without being asked. Solid Python, a bit li\u2026"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "My take on Tobias: great on the pipeline design question, he talked through backpressure and idempotent consumers without being asked. Solid Python, a bit li\u2026"

## step 34 — Ilya's feedback under Wen's
Field: gh_cand_tobias#note · wanted: {"paste": "Ilya on Tobias: agree with Wen. System design was crisp, he asked about our failure modes before drawing anything. I would hire. Level: senior."}
- **A**: pressed ⌘V; waited 44 ms for the app; total ≈ 0.32 s; landed: "Ilya on Tobias: agree with Wen. System design was crisp, he asked about our failure modes before drawing anything. I would hire. Level: senior."
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Ilya on Tobias: agree with Wen. System design was crisp, he asked about our failure modes before drawing anything. I would hire. Level: senior."

## step 35 — Texting Marisol where to come on Thursday
Field: messages_marisol#main · wanted: {"paste": "Acme Robotics\n480 Harlan Street, Suite 400\nSan Francisco, CA 94107"}
- **A**: pressed ⌘V; waited 46 ms for the app; total ≈ 0.33 s; landed: "Acme Robotics\n480 Harlan Street, Suite 400\nSan Francisco, CA 94107"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Acme Robotics\n480 Harlan Street, Suite 400\nSan Francisco, CA 94107"

## step 36 — Jonas asked for Marisol's LinkedIn before the loop
Field: slack_dm_jonas#message · wanted: {"paste": "https://www.linkedin.com/in/marisol-reyes-4c82a1"}
- **A**: pressed ⌘Space ⌘4 type:link Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "https://www.linkedin.com/in/marisol-reyes-4c82a1"
- **B**: pressed ⌘V ⌘Z; waited 3 ms for the app; total ≈ 4.75 s; landed: "Acme Robotics\n480 Harlan Street, Suite 400\nSan Francisco, CA 94107"

## step 37 — Pointing Jonas at her scorecard setup
Field: slack_dm_jonas#message · wanted: {"paste": "https://app.greenhouse.io/people/412398007?application_id=519304118"}
- **A**: pressed ⌘V; waited 13 ms for the app; total ≈ 0.29 s; landed: "https://app.greenhouse.io/people/412398007?application_id=519304118"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://app.greenhouse.io/people/412398007?application_id=519304118"

## step 38 — Same title as the calendar hold
Field: gmail_compose#subject · wanted: {"paste": "Marisol Reyes - Onsite loop (Staff Frontend)"}
- **A**: pressed ⌘V; waited 13 ms for the app; total ≈ 0.29 s; landed: "Marisol Reyes - Onsite loop (Staff Frontend)"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Marisol Reyes - Onsite loop (Staff Frontend)"

## step 39 — Booking link again, this time for Nikhil
Field: gmail_reply_nikhil#reply · wanted: {"paste": "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"}
- **A**: pressed ⌘V ⌘Z; waited 2 ms for the app; total ≈ 4.75 s; landed: "Marisol Reyes - Onsite loop (Staff Frontend)"
- **B**: pressed ⌘Space ⌘4 type:cale Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "https://calendly.com/renata-acme/phone-screen-30?back=1&month=2026-10"

## step 40 — Telling Leila the offer is out
Field: slack_dm_leila#message · wanted: {"paste": "https://app.greenhouse.io/offers/88213001"}
- **A**: pressed ⌘V; waited 2 ms for the app; total ≈ 0.28 s; landed: "https://app.greenhouse.io/offers/88213001"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "https://app.greenhouse.io/offers/88213001"

## step 41 — First of two identical prep emails, order does not matter
Field: gmail_compose#to · wanted: {"choose": ["samir.haddad@example.net", "imani.brooks@example.org"]}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "imani.brooks@example.org"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "imani.brooks@example.org"

## step 42 — Second prep email, the other candidate
Field: gmail_compose#to · wanted: {"choose": ["samir.haddad@example.net", "imani.brooks@example.org"]}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "imani.brooks@example.org"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "imani.brooks@example.org"

## step 43 — Parking the reminder in her Thursday list
Field: notes_scratch#main · wanted: {"paste": "Reminder: Marisol's loop starts at 2pm Thursday, front desk needs her name for a badge"}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Reminder: Marisol's loop starts at 2pm Thursday, front desk needs her name for a badge"
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Reminder: Marisol's loop starts at 2pm Thursday, front desk needs her name for a badge"

## step 44 — Address in the onsite confirmation email
Field: gmail_reply_marisol#reply · wanted: {"paste": "Acme Robotics\n480 Harlan Street, Suite 400\nSan Francisco, CA 94107"}
- **A**: pressed ⌘V ⌘Z; waited 18 ms for the app; total ≈ 4.77 s; landed: "Reminder: Marisol's loop starts at 2pm Thursday, front desk needs her name for a badge"
- **B**: pressed ⌘Space ⌘4 type:harl Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "Acme Robotics\n480 Harlan Street, Suite 400\nSan Francisco, CA 94107"

## step 45 — JD link for an agency recruiter
Field: gmail_compose#body · wanted: {"paste": "https://acme.example/careers/senior-backend-engineer?gh_src=7c41d0b2"}
- **A**: pressed ⌘V ⌘Z; waited 0 ms for the app; total ≈ 4.75 s; landed: "Reminder: Marisol's loop starts at 2pm Thursday, front desk needs her name for a badge"
- **B**: pressed ⌘Space ⌘4 type:care Return ⌘V; waited 0 ms for the app; total ≈ 4.19 s; landed: "https://acme.example/careers/senior-backend-engineer?gh_src=7c41d0b2"

## step 46 — Samir's slot goes on tomorrow's list
Field: notes_scratch#main · wanted: {"paste": "Tuesday 10/20 after 3pm PT works for me."}
- **A**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Tuesday 10/20 after 3pm PT works for me."
- **B**: pressed ⌘V; waited 0 ms for the app; total ≈ 0.28 s; landed: "Tuesday 10/20 after 3pm PT works for me."
