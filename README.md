# Rating Prompt Flow Tester (iOS + Android)

Tests the **exact** logic described in
"แนวทางการแสดงและพัฒนา Rating Prompt จากระบบปฏิบัติการ" — not just a
generic `in_app_review` demo, but the specific condition
(`sessionCount >= 5 && !hasReviewed/!hasRated`) and the specific function
names used in the document (`requestiOSRating()`, `requestAndroidRating()`,
`openAppStorePage()`, `openPlayStorePage()`).

**Not runnable in this sandbox** — no Flutter SDK / network access here.
Copy this to your own machine to actually test on a device/simulator.

## What's different from the earlier simple version

- **Persists state with `shared_preferences`** (same package the document
  lists as a dependency) — `sessionCount`, `hasReviewed` (iOS), `hasRated`
  (Android) all survive an app restart, not just in-memory. This matters
  because the real question is "does it correctly stop asking once
  reviewed" — that can't be tested honestly with in-memory state that
  resets every relaunch.
- **Matches the document's function names 1:1** so what you're testing is
  the same logic, not just "the plugin works in general."
- **Built-in testing notes** (expandable card) with the same Debug /
  TestFlight / Production distinction for iOS, and the Internal Testing
  bypass + delete-review-to-reset procedure for Android — so you don't
  need to have the Word doc open side-by-side while testing.

## Setup

```bash
flutter create review_flow_tester
cd review_flow_tester
# replace the generated pubspec.yaml and lib/main.dart with the ones here
flutter pub get
flutter run
```

Before testing the fallback button on iOS, swap `123456789` in
`main.dart` (`openAppStorePage`) for your real numeric App Store ID.

## How to actually verify "does the native popup work like the document says"

**iOS:**
1. Run in Debug (`flutter run` on a simulator or a cabled device). Tap
   "Simulate session" 5 times — on the 5th, `requestiOSRating()` fires and
   the native Apple dialog should appear **every time** you repeat this
   (reset first). This confirms the *trigger logic* is correct.
2. To confirm the *quota* claim (max 3 times / 365 days) — that can only
   be observed in a real **App Store production build**, since Debug and
   TestFlight both bypass or block it entirely (see the in-app notes).
3. To confirm TestFlight really blocks it: archive, upload to
   TestFlight, install from there, and repeat the same 5-session test —
   the dialog should not appear at all. This is expected per the doc, not
   a failure of your code.

**Android:**
1. Same idea: run debug locally, simulate 5 sessions, watch whether the
   bottom sheet appears. Note that a plain sideloaded debug APK can
   silently no-op even with no error — this is a known limitation, not
   necessarily a bug in your integration.
2. For a real test of the actual dialog: upload to Google Play's
   **Internal Testing track**, install from there with a Google account
   that has **never reviewed this app before**. Internal Testing bypasses
   the time-based quota, so you can repeat the test after using
   "Reset test state" in the app — but if that Google account ever
   actually submits a review, you'll need to manually delete it from the
   Play Store app first (search the app → ⋮ → Delete review) before it
   will show again.

## Files

```
review_flow_tester/
├── pubspec.yaml          in_app_review + shared_preferences
└── lib/main.dart         RatingService + UI + persisted state + testing notes
```

No native Android/iOS project files are included — same as before, those
need to come from `flutter create`, since they're version-specific
scaffolding rather than app logic.
