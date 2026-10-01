# Goals and playful experience — delivery contract

## Owner request and scope
User hima requested continuing It's the Day! with countdowns, quantity goals with deadlines, checklists and explanatory completion entries, online/shared groups, comprehensive icons, and smooth/fun Duolingo-inspired animation. Preserve It's the Day! identity and existing calendar/reminder behavior. Inspiration is interaction quality, not copying Duolingo branding/artwork.

## Preflight
PASS WITH EXCEPTION for isolated feature implementation. Baseline main eb6cf3ea9895a7f897ca7e0fb2a08e339c489a86 passed flutter analyze and 12 Flutter tests. Feature branch feat/goals-playful-experience. No dirty user files were present. No existing workflows or main protection; do not mutate repository settings. Exception owner: delivery orchestrator; retain existing single-main topology for this change, require feature PR, exact-head CI and independent review before integration. Exception expires at PR delivery. Production deployment/store publication is NOT authorized. External auth/provider setup must remain explicit if missing; never fabricate live online verification.

## Acceptance contract
- Countdown-only events still work.
- Quantity goal: positive integer target, explicit unit, deadline, cumulative completed entries with optional title/note/http(s) URL, timestamp. Add/edit/delete entries; quick +1 without requiring fifty pre-created tasks. Undo/confirm destructive actions. No double count from repeat taps or retries. Progress derives from non-deleted entries; progress bar saturates but actual overachievement remains visible.
- Checklist goal: named items with checked state, optional explanation; item completion increments once, unchecking reverses it. Distinguish checklist subtasks from quantity-goal entries.
- Deadline state distinguishes upcoming/today/overdue/completed. Pace estimate only with defined calendar-day rules; no division by zero. Date-only deadline means end of selected day in declared local timezone, not the start of that day.
- Locally persistent goals and entries survive restart; existing events survive migration. Persistence errors must not pretend success or lose pending input.
- Android widget shows selected countdown/goal, days remaining, actual completed/target, recognizable product icon, tap to appropriate app context. Web provides in-app cards; do not claim native home-screen widgets on web.
- Original product icon and cohesive category/action icons, Android launcher/adaptive icon, Android splash, web favicon/PWA icon/name/theme, no remaining default Flutter visible branding. Reproducible icon sources/generator preferred.
- Bright, rounded, tactile design with legible dark mode; subtle press depression, animated progress/check transitions and one-shot success celebration, no idle infinite animations, no unrelated streak punishment. Reduced motion, semantic labels, keyboard navigation, >=48dp touch targets, narrow/large screens and large text covered. Avoid heavy packages for basic animations.
- Online accounts/groups: real server authority and membership authorization, private vs shared access, create/join/leave and revocation, shared-total vs individual targets, actor/time attribution. Native auth tokens in secure storage, web cookie or appropriate documented transport. No embedded provider secrets. Idempotent mutation/retry; offline status and reconciliation explicit. Never count local fake users/groups as online implementation.
- Cloudflare Workers/Hono/D1 backend follows existing intended architecture; Better Auth compatibility verified before claiming it works. Any missing deployment/provider configuration must appear as honest setup-needed UX and delivery gap. Do not add AI services or model calls to product.
- Web builds and preserves goals through reload; calendar/Android-only features explicitly unsupported without crashing (kIsWeb gate required).
- Empty/loading/error/offline/setup-needed/permission-denied/completed/overdue states are implemented, not just happy-path cards.

## Verification and release
Flutter format/analyze/tests; Android debug APK with JDK21; web release build; headless web interaction/screenshots; emulator exact APK primary flow and widget where supported; server integration/security tests with local Worker/D1 and multi-account membership tests. Independent final-diff review. CI runs same meaningful deterministic gates. pubspec is app-version authority: minor version bump for new features, changelog paired; no tag/store release until authorized. Document exact implemented versus tested versus externally configured status. Preserve all existing tests unless assertions truly change with deliberate UI copy; no skipped gates.

## Safety and ownership
Single implementation writer owns repo source. Parent owns final review/git/PR. No visible browser, personal Chrome, other profile changes, production provisioning/deploy, real-user data deletion or secret printing. Additional reviewer is read-only. Secrets are configured out of band only. Do not use model APIs except explicitly authorized Codex coding delegation.
