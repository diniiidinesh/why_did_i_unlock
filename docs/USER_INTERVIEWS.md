# User interviews

> A running list of questions to ask testers/friends in 1:1s, so a question that
> motivated a real product decision doesn't get lost in chat/memory. Append new
> questions under a topic heading (new heading if it doesn't fit an existing one)
> rather than rewriting past ones — this is a growing log, not a fixed script.
> Mark a question `[ASKED]` with a short summary of answers once you've actually
> put it to people; leave it unmarked while still queued.
>
> Not a replacement for `docs/BACKLOG.md`'s `[decision]` tag — that's for tracking
> that a decision is open. This is for the actual interview questions used to
> inform it.

## Presets / capture screen

- **Preset count — does having more options help or slow you down?** Added
  2026-08-11, prompted by a request to raise `maxEnabledPresets` from 8 to 10.
  Kept at 8 for now specifically to ask this first, rather than guess — see
  `docs/DATA_MODEL.md` §7: the documented rationale for the current cap of 8
  (5–6 recommended) is that decision cost, not screen space, is the binding
  constraint — "the capture screen must be answerable in about two seconds,
  one-handed, at unlock... a prompt that is slow to answer gets answered
  dishonestly or not at all." That's a hypothesis, not a measured fact; this
  question is how we'd actually find out.
  - "When you unlock and see the preset options, does having that many feel
    helpful, or does it feel like too many things to pick from in the moment?"
  - Follow-up if they want more: "Which extra ones would you actually use
    regularly, versus ones you'd tap once and never again?"
  - Follow-up if they want fewer: "Which of the current ones do you never
    use?"
  - **[PARTIALLY ASKED 2026-08-15]** — one unprompted data point from written
    closed-test feedback (not a 1:1, so the follow-ups above went unasked).
    **Chukka:** *"8 Options feels like a limitation… It'll be helpful if more
    options are present."* Same tester also reported *"phone usage hasn't gone
    down"* and *"even if I write a note, I'm not fulfilling it"* — so read the
    request in context: it may be a proxy for "the app isn't working for me"
    rather than a literal capacity problem, which is exactly what the follow-up
    questions above are designed to separate. **Still worth a real 1:1 before
    changing the cap.** No other tester mentioned the limit.
