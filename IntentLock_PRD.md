**PRODUCT REQUIREMENTS DOCUMENT**

**IntentLock**

*Know Why You Picked Up Your Phone*

  ---------------------- ------------------------------------------------
  **Field**              **Details**

  Version                1.0

  Date                   February 27, 2026

  Status                 Draft --- Ready for Development

  Platform               Android (Phase 1), iOS (Phase 2)

  Tech Stack             Replit-Compatible (React Native / Flutter)

  Target Launch          Q3 2026 (MVP)
  ---------------------- ------------------------------------------------

**Table of Contents**

**1. Idea Evaluation**

**1.1 Concept Summary**

IntentLock is a digital wellbeing app that intercepts every phone unlock
with a single question: \"What are you unlocking for?\" The user states
their intent via quick-tap presets or voice-to-text. That intent then
lives as a persistent floating bubble (similar to Facebook Messenger
chat heads) overlaying all other apps, serving as a constant visual
reminder of purpose. The bubble stays until the user manually checks it
off or an optional countdown timer expires.

**1.2 Problem Statement**

The average person unlocks their phone 80--150 times per day. Studies
show that nearly 50% of these unlocks are habitual and purposeless,
leading to an average of 2.5 hours of unintended screen time daily.
Existing solutions (app blockers, screen time limits, grayscale modes)
are punitive and easily bypassed. They restrict behavior rather than
building awareness. There is no mainstream app that combines intent
declaration at unlock with persistent visual accountability (the bubble)
and optional time-bound commitment (the timer).

**1.3 Competitive Landscape**

  ------------ -------------------------- ---------------------------------
  **App**      **What It Does**           **Key Gap IntentLock Fills**

  Intenty      Full-screen nudge on       No persistent bubble reminder;
               unlock asking \"why?\";    intent disappears once dismissed;
               logs answers; breathing    no timer accountability
               exercises                  

  One Sec      Forces a pause/breathing   Only triggers on specific apps,
               exercise before opening    not all unlocks; no intent
               social media apps          logging or bubble

  Forest       Gamified focus timer (grow Opt-in sessions only; doesn't
               a tree); penalizes phone   intercept unlocks; no intent
               use during timer           tracking

  ScreenZen    Adds friction/delay before App-specific, not unlock-level;
               opening distracting apps   no voice input or persistent
                                          overlay

  Minimalist   Replaces launcher with     Full phone replacement; too
  Phone        minimal UI to reduce       extreme for most users; no intent
               distractions               tracking

  Digital      Built-in screen time       Passive reporting; no active
  Wellbeing    dashboard, app timers,     intent capture; no bubble
  (Google)     focus mode                 reminders
  ------------ -------------------------- ---------------------------------

**1.4 Unique Value Proposition**

IntentLock is the only app that combines three mechanics into one
seamless flow:

1.  **Intent Capture at Unlock** --- A non-dismissible screen that
    captures WHY you're using your phone, via tap or voice.

2.  **Persistent Floating Bubble** --- Your declared intent stays
    visible as an overlay across ALL apps until manually completed.

3.  **Optional Timer Accountability** --- Set a deadline for your task.
    The bubble pulses/changes color as time runs out.

**1.5 SWOT Analysis**

  --------------- -------------------------------------------------------
  **Category**    **Details**

  Strengths       Novel mechanic combining intent + bubble + timer;
                  lightweight and privacy-first (all data local); low
                  friction voice input; viral potential (\"I can't
                  believe I unlocked 120 times today\")

  Weaknesses      Relies on Android accessibility/overlay permissions
                  (complex); friction fatigue risk if not tuned well; no
                  iOS bubble equivalent (must use persistent
                  notification)

  Opportunities   Digital detox market growing at 24% CAGR; screen time
                  monitoring market at \$4B; potential B2B (corporate
                  digital wellness programs); integration with wearables

  Threats         Google/Apple could build native intent features;
                  Intenty has first-mover advantage on the nudge concept;
                  users may disable overlays after initial novelty
  --------------- -------------------------------------------------------

**1.6 Verdict**

**Strong opportunity. The core mechanic is validated by Intenty's
traction (featured on TechCrunch, trending on Hacker News and
r/Android). However, Intenty stops at the nudge. IntentLock extends the
concept with persistent accountability (the bubble) and time-bounded
commitment (the timer), which are the two features most requested in
Intenty's user feedback threads. The market is growing rapidly and no
competitor occupies this exact niche.**

**2. Complete Analysis**

**2.1 Target Audience**

  -------------- ------------------ ------------------ -------------------
  **Persona**    **Description**    **Pain Point**     **Key Need**

  The            18--34, heavy      Picks up phone for A visible reminder
  Doomscroller   social media user, one thing, loses   of original intent
                 5+ hrs daily       45 min to          
                 screen time        Instagram/TikTok   

  The            25--45, knowledge  Blurred work-life  Time-boxed phone
  Productivity   worker, uses phone boundary; phone    sessions with
  Seeker         for work +         unlocks derail     accountability
                 personal           focus              

  The Digital    30--50, concerned  Wants to           Simple,
  Wellness       about their own    demonstrate        non-punitive
  Parent         habits and         intentional tech   awareness tool
                 modeling for kids  use                

  The Student    16--24, studying   Unlocks to check   Quick intent
                 but phone is       one notification,  capture +
                 constant           ends up on YouTube persistent nudge
                 distraction                           
  -------------- ------------------ ------------------ -------------------

**2.2 Market Sizing**

**Total Addressable Market (TAM)**

The global wellness apps market is valued at approximately \$12.87
billion in 2025, growing at a 15% CAGR. The digital detox sub-segment is
estimated at \$0.98 billion in 2025, projected to reach \$8.65 billion
by 2035 (24.33% CAGR). Screen time monitoring apps alone represent a \$4
billion market.

**Serviceable Addressable Market (SAM)**

Focusing on English-speaking Android users aged 18--45 who actively seek
screen time reduction tools: approximately 120 million potential users
globally. At a \$2/month average, this represents a \$2.88 billion
annual SAM.

**Serviceable Obtainable Market (SOM)**

Targeting 0.1% penetration in Year 1 (120,000 users), with 10%
conversion to premium (\$24/year): approximately \$288,000 ARR in
Year 1. Target of 1% penetration by Year 3 (1.2 million users) yielding
\$2.88 million ARR.

**2.3 Business Model**

  ----------- --------------------- --------------------------------------
  **Tier**    **Price**             **Features**

  Free        \$0                   Intent capture on unlock (up to 5
                                    presets); bubble reminder; daily
                                    unlock count; 7-day history

  Pro         \$2.99/month or       Unlimited presets; voice-to-text;
              \$24.99/year          custom timers; full history +
                                    analytics; export data; bubble
                                    customization (colors, size, opacity);
                                    smart cooldown scheduling

  Lifetime    \$59.99 one-time      All Pro features forever; early access
                                    to new features; priority support
  ----------- --------------------- --------------------------------------

**2.4 Technical Architecture**

**Recommended Tech Stack (Replit-Compatible)**

  ---------------- ------------------------ ---------------------------------
  **Layer**        **Technology**           **Rationale**

  Framework        React Native (Expo       Cross-platform; Replit has strong
                   managed) or Flutter      React Native support; single
                                            codebase for Android + iOS

  State Management Zustand (RN) or Riverpod Lightweight, minimal boilerplate
                   (Flutter)                

  Local Storage    SQLite via expo-sqlite   All data stays on device; no
                   or sqflite               backend needed for MVP

  Overlay/Bubble   Android:                 Enables floating bubble across
                   SYSTEM_ALERT_WINDOW +    all apps
                   Foreground Service; iOS: 
                   Live Activities +        
                   Persistent Notification  

  Voice Input      Android SpeechRecognizer On-device STT, no network calls
                   API / iOS Speech         needed
                   framework                

  Unlock Detection Android:                 Triggers intent capture screen on
                   BroadcastReceiver for    every unlock
                   ACTION_USER_PRESENT;     
                   iOS: Protected data      
                   availability check       

  Analytics        PostHog (self-hosted) or Privacy-respecting; no user data
  (optional)       Plausible                leaves device by default
  ---------------- ------------------------ ---------------------------------

**Key Android Permissions Required**

-   **SYSTEM_ALERT_WINDOW** --- Draw overlay (the floating bubble) on
    top of other apps

-   **FOREGROUND_SERVICE** --- Keep the bubble alive when the app is
    backgrounded

-   **RECEIVE_BOOT_COMPLETED** --- Auto-start after device reboot

-   **RECORD_AUDIO** --- Voice-to-text input (only when user activates
    mic)

-   **POST_NOTIFICATIONS** --- Timer alerts and foreground service
    notification

**2.5 Key Risks & Mitigations**

  --------------------- -------------- ----------------------------------------
  **Risk**              **Severity**   **Mitigation**

  Friction fatigue:     High           Smart cooldown (no prompt within X
  users disable the app                minutes of last unlock); customizable
  after a few days                     intensity levels; gamification (streaks,
                                       insights)

  Android permission    Medium         Guided onboarding wizard with visual
  complexity                           permission walkthrough; fallback to
                                       notification-based prompt if overlay
                                       denied

  iOS limitations (no   Medium         Use Live Activities (iOS 16.1+) +
  true floating bubble)                Dynamic Island for bubble equivalent;
                                       persistent notification as fallback

  Google Play policy    Medium         Use official Bubble API (Android 11+) as
  changes on overlay                   primary; SYSTEM_ALERT_WINDOW as fallback
  apps                                 for older devices

  User data privacy     Low            100% local storage by default; no
  concerns                             account required; optional encrypted
                                       cloud backup (user-initiated only)
  --------------------- -------------- ----------------------------------------

**3. Product Requirements**

**3.1 User Flows**

**Flow 1: First-Time Setup**

1.  User downloads IntentLock from Google Play Store.

2.  Welcome screen explains the concept in 3 swipe cards: \"Declare\" →
    \"Bubble\" → \"Complete.\"

3.  Guided permission setup: Overlay permission → Notification
    permission → (Optional) Microphone for voice.

4.  User configures 3--5 default intent presets (e.g., \"Check
    messages,\" \"Quick search,\" \"Work task,\" \"Just browsing\").

5.  Setup complete. IntentLock is active. User locks phone to test.

**Flow 2: Standard Unlock (Core Loop)**

1.  User unlocks phone (fingerprint, face, PIN).

2.  IntentLock overlay appears: \"What are you unlocking for?\" with
    preset buttons + voice mic button + custom text field.

3.  User taps a preset OR speaks their intent OR types a custom intent.

4.  (Optional) User sets a timer: \"I want to finish this in X
    minutes.\"

5.  Overlay dismisses. A floating bubble appears showing the intent text
    (truncated).

6.  User proceeds to use their phone. The bubble stays visible across
    all apps.

7.  When done, user taps the bubble → taps \"Done\" checkmark → bubble
    disappears.

8.  Intent is logged with timestamp, duration, and completion status.

**Flow 3: Timer Expiry**

1.  Timer reaches 75% → bubble changes from blue to amber.

2.  Timer reaches 100% → bubble turns red and gently pulses.

3.  A notification appears: \"Time's up! Did you finish \[intent\]?\"

4.  User can tap \"Done,\" \"Need more time (+5 min),\" or \"Dismiss.\"

**3.2 Feature Specification**

**P0 --- Must Have (MVP)**

  --------------- -------------------------- ------------------------------
  **Feature**     **Description**            **Acceptance Criteria**

  Unlock          Detect every phone unlock  Intent screen appears within
  Detection       event and trigger the      500ms of unlock; works with
                  intent capture screen      fingerprint, face, PIN, and
                                             pattern unlock

  Intent Capture  Full-screen overlay with   Minimum 3, maximum 8 preset
  Screen          preset buttons and a       buttons; user can
                  custom text input field    add/edit/remove presets;
                                             custom text field supports up
                                             to 100 characters

  Voice-to-Text   Microphone button that     Activates on-device STT;
  Input           converts speech to text    transcription appears in
                  for intent entry           real-time; auto-submits after
                                             2 seconds of silence

  Floating Bubble Persistent overlay bubble  Draggable to any screen edge;
                  showing current intent     survives app switches; shows
                  text                       truncated intent (max 20
                                             chars); tap to expand full
                                             text + done button

  Manual          User taps bubble to mark   Single tap expands bubble;
  Completion      intent as complete         checkmark button dismisses and
                                             logs completion;
                                             swipe-to-dismiss also works

  Intent History  Chronological log of all   Shows last 7 days (free) or
                  declared intents with      unlimited (pro); displays
                  timestamps                 intent text, time declared,
                                             time completed, and duration

  Cooldown Period Configurable delay before  Default 2 minutes; adjustable
                  showing intent screen      from 0 to 30 minutes; no
                  again after recent unlock  prompt during cooldown

  Basic Analytics Daily/weekly unlock count, Updates in real-time; shows
  Dashboard       most common intents,       today vs. 7-day average;
                  average session duration   visual bar chart for daily
                                             unlocks
  --------------- -------------------------- ------------------------------

**P1 --- Should Have (v1.1)**

  ------------------ ----------------------------------------------------
  **Feature**        **Description**

  Timer              Optional countdown timer attached to an intent;
                     visual color changes at 75% and 100%; notification
                     on expiry; extend/dismiss options

  Smart Cooldown     Auto-disable prompts during configurable time
  Scheduling         windows (e.g., 6--7 AM gym time, 11 PM--12 AM
                     bedtime)

  Bubble             Choose bubble color, size (small/medium/large),
  Customization      opacity, and position memory

  Intent Templates   Time-of-day or location-based preset suggestions
  by Context         (e.g., morning = \"Check email, Weather\" vs.
                     evening = \"Social media, News\")

  Data Export        Export intent history as CSV or JSON for personal
                     analysis
  ------------------ ----------------------------------------------------

**P2 --- Nice to Have (v2.0)**

  ------------------ ----------------------------------------------------
  **Feature**        **Description**

  Gamification       Streaks for consecutive days of intentional use;
                     badges for milestones; weekly reports with insights

  Widget             Home screen widget showing today's unlock count and
                     current active intent

  Share Insights     Generate shareable cards (\"I was intentional 85% of
                     the time this week\") for social media

  iOS Full Support   Live Activities for bubble equivalent; Dynamic
                     Island integration; full feature parity

  Wearable           Show current intent on smartwatch; complete intent
  Integration        from watch

  AI Suggestions     ML model that learns user patterns and suggests
                     likely intents based on time/context
  ------------------ ----------------------------------------------------

**3.3 Screen-by-Screen Specification**

**Screen 1: Intent Capture Overlay**

Appears immediately after phone unlock. Full-screen semi-transparent
overlay (85% opacity dark background).

  --------------- -------------------------------------------------------
  **Element**     **Spec**

  Header Text     \"What are you unlocking for?\" --- 24sp, white,
                  center-aligned

  Preset Buttons  Rounded pill buttons in a 2-column grid; 16sp text;
                  customizable labels; tap = select + auto-submit after
                  300ms

  Custom Input    Text field at bottom with placeholder \"Type your
  Field           intent\...\"; 16sp; max 100 chars; submit on Enter

  Voice Button    Microphone FAB (floating action button) in
                  bottom-right; animates while recording; auto-submits on
                  silence

  Timer Toggle    \"Set timer\" link below presets; expands to show
                  5/10/15/30/60 min quick-select chips + custom input

  Skip Option     Small \"Skip\" text link at top-right (free tier:
                  always visible; Hard Mode pro feature: hidden)
  --------------- -------------------------------------------------------

**Screen 2: Floating Bubble**

Persistent overlay visible across all applications and home screen.

  --------------- -------------------------------------------------------
  **Element**     **Spec**

  Collapsed State 56dp circular bubble; app icon or first letter of
                  intent; draggable; edge-magnetized

  Expanded State  Rounded rectangle (240dp x 120dp); shows full intent
                  text; \"Done\" checkmark button; timer countdown if
                  active; \"More time\" button if timer active

  Timer Visual    Circular progress ring around bubble (collapsed);
                  color: blue → amber (75%) → red (100%); gentle pulse
                  animation at 100%

  Dismiss         Tap checkmark = complete; long-press = dismiss without
                  completing (logged as \"abandoned\"); drag to bottom X
                  = dismiss
  --------------- -------------------------------------------------------

**Screen 3: Dashboard (Main App)**

Accessible by opening the IntentLock app directly.

  --------------- -------------------------------------------------------
  **Element**     **Spec**

  Today Card      Unlock count, intents completed vs. abandoned, average
                  session duration, most common intent

  Weekly Chart    Bar chart showing daily unlocks (7-day view); tap a bar
                  to see that day's intents

  Intent Log      Scrollable list; each entry shows: intent text,
                  timestamp, duration, status
                  (completed/abandoned/timed-out)

  Settings Gear   Top-right icon → opens Settings screen
  --------------- -------------------------------------------------------

**Screen 4: Settings**

  ------------------ ----------------------------------------------------
  **Setting**        **Options**

  Manage Presets     Add/edit/delete/reorder intent presets

  Cooldown Period    Slider: 0--30 minutes

  Bubble Appearance  Size (S/M/L), color picker, opacity slider, position
                     (left/right default edge)

  Timer Defaults     Default timer duration; enable/disable timer
                     suggestions

  Schedule           Set quiet hours where IntentLock does not prompt

  Hard Mode (Pro)    Toggle: removes Skip button from intent screen

  Data & Privacy     View stored data; export; delete all data; app uses
                     no network by default

  About              Version, privacy policy, feedback link, rate app
  ------------------ ----------------------------------------------------

**3.4 Non-Functional Requirements**

  ----------------- -------------------------------------------------------
  **Requirement**   **Target**

  Performance       Intent screen renders in under 500ms after unlock;
                    bubble consumes less than 2% battery per day; app size
                    under 15 MB

  Privacy           Zero data transmitted off-device by default; no
                    analytics SDK in free tier; no account/signup required

  Accessibility     WCAG 2.1 AA compliant; screen reader support; minimum
                    touch target 48dp; high contrast mode

  Reliability       Bubble survives process death and low-memory kills via
                    foreground service; auto-restarts on boot

  Compatibility     Android 10+ (API 29+); covers 90%+ of active Android
                    devices; iOS 16.1+ for Phase 2
  ----------------- -------------------------------------------------------

**4. Development Roadmap**

**4.1 Phase 1: Android MVP (Weeks 1--8)**

  ------------ -------------- ---------------------------------------------
  **Sprint**   **Duration**   **Deliverables**

  Sprint 1     Weeks 1--2     Project scaffold in Replit; unlock detection
                              service; basic intent capture overlay with 3
                              hardcoded presets

  Sprint 2     Weeks 3--4     Floating bubble implementation
                              (SYSTEM_ALERT_WINDOW + Foreground Service);
                              bubble expand/collapse; manual completion

  Sprint 3     Weeks 5--6     Voice-to-text input; custom presets CRUD;
                              SQLite storage for intent history; cooldown
                              logic

  Sprint 4     Weeks 7--8     Dashboard with analytics; settings screen;
                              onboarding flow; Play Store listing; internal
                              testing
  ------------ -------------- ---------------------------------------------

**4.2 Phase 2: Polish & Pro Features (Weeks 9--12)**

  ------------ -------------- ---------------------------------------------
  **Sprint**   **Duration**   **Deliverables**

  Sprint 5     Weeks 9--10    Timer feature (countdown, color changes,
                              notifications); smart cooldown scheduling;
                              bubble customization

  Sprint 6     Weeks 11--12   In-app purchase integration (Pro tier); data
                              export; Hard Mode; Play Store launch
  ------------ -------------- ---------------------------------------------

**4.3 Phase 3: iOS + Growth (Weeks 13--20)**

  ------------ -------------- ---------------------------------------------
  **Sprint**   **Duration**   **Deliverables**

  Sprint 7--8  Weeks 13--16   iOS adaptation: Live Activities + Dynamic
                              Island for bubble; persistent notification
                              fallback; App Store submission

  Sprint 9--10 Weeks 17--20   Gamification (streaks, badges); widget; share
                              insights; AI intent suggestions; v2.0 launch
  ------------ -------------- ---------------------------------------------

**5. Success Metrics**

  --------------------- ---------------- ---------------- ----------------
  **Metric**            **Target (Month  **Target (Month  **Target (Month
                        1)**             6)**             12)**

  Downloads             5,000            50,000           200,000

  DAU / MAU Ratio       30%              35%              40%

  D7 Retention          25%              35%              40%

  D30 Retention         10%              18%              25%

  Pro Conversion Rate   3%               7%               10%

  Avg. Intents          4                6                8
  Completed/Day                                           

  App Store Rating      4.0+             4.3+             4.5+

  Avg. Daily Screen     15 min           25 min           35 min
  Time Reduction                                          
  --------------------- ---------------- ---------------- ----------------

**6. Appendix**

**6.1 Replit Development Notes**

This PRD is designed to be directly actionable in Replit. Recommended
setup:

1.  Create a new Replit project with the React Native (Expo) template.

2.  Install key dependencies: expo-notifications, expo-sqlite,
    react-native-voice, expo-speech.

3.  For the floating bubble, you will need a native Android module
    (BubbleService.kt) since Expo does not support SYSTEM_ALERT_WINDOW
    out of the box. Use expo-dev-client for custom native code.

4.  For unlock detection, create a BroadcastReceiver listening for
    Intent.ACTION_USER_PRESENT.

5.  Test on a physical Android device (emulators do not properly
    simulate unlock events or overlay permissions).

**6.2 Monetization Alternatives Considered**

  ------------- ----------------- ---------------- -----------------------
  **Model**     **Pros**          **Cons**         **Decision**

  Freemium      Low barrier to    Requires large   Selected as primary
  (chosen)      adoption; viral   user base for    model
                growth;           meaningful       
                predictable       revenue          
                recurring revenue                  

  One-time      Simple; users     No recurring     Offered as Lifetime
  purchase      prefer it for     revenue; hard to tier option
                privacy-focused   fund ongoing     
                apps              development      

  Ads           Revenue from free Contradicts the  Rejected
                users             app's digital    
                                  wellness         
                                  mission; breaks  
                                  trust            

  B2B licensing High contract     Requires         Planned for v3.0
                values; corporate enterprise       
                wellness budgets  features (admin  
                                  dashboard,       
                                  reporting)       
  ------------- ----------------- ---------------- -----------------------

**6.3 Key References**

1.  Intenty App (Google Play): Primary competitor reference for
    unlock-based intent capture.

2.  Android Bubble API Documentation:
    developer.android.com/develop/ui/views/notifications/bubbles

3.  TechCrunch coverage of Intenty (Nov 2024): Validates market interest
    and user demand.

4.  Digital Detox Apps Market Report (Roots Analysis, 2025): \$0.98B
    market growing at 24.33% CAGR.

5.  Hacker News discussion threads on Intenty: Key user feedback
    informing P1/P2 feature prioritization.

*End of Document*
