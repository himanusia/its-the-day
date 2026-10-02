# Dark inputs, icon safe zones and compact-widget checkpoint

Parent issue #15 under #6. Final functional source: `710ff3c4cddb7eed715b6872b3e818a7a4589b4a`.

## Changes

- Dark input fill now uses the dark surface container; readable text, hint, cursor and selection. Light-mode white fill remains unchanged. All six form-bearing presentation files were audited for local fill overrides.
- Original clock/spark marks paint in a safely inset centered square; Android adaptive/legacy/splash marks fit the mask safe zone. No brand redesign.
- Android widget supports one-cell metadata and compact rendering on initial options and resizing. Compact goal view prioritizes numeric completed/target; full description retains status/unit for accessibility. Larger widget retains progress and cadence.
- Shared app cadence uses nonnegative remaining work and inclusive local calendar days: daily ceil target or one unit every whole-number interval. Completed, empty, overdue and today are explicit. Online quantity uses authoritative server totals. Native widget recalculates from numeric snapshot fields and current local calendar date.

## Real parent gates

| Gate | Result |
|---|---|
| Flutter analyze | Clean |
| Full default suite | 78 passed, 4 explicit local/remote opt-in skips, 0 failed; JSON test event aggregation |
| Icon safe-zone script | PASS; static only |
| HTTPS ARM64 debug APK | Built and installed `-r` on emulator-5554 without clearing existing data |
| Independent review | PASS `a7355a2`; narrow re-review PASS exact final `710ff3c` |
| Actual dark Account screenshot | Dark fields and legible labels inspected; optional Google remains setup-needed |
| Actual in-app mark | Final dark home screenshot inspected: complete ring/spark, no framework fallback |
| Actual Android launcher | App drawer screenshot inspected: original ring/spark fully inside circular mask; unrelated apps' icons unchanged |
| Actual widget resize/creation | Existing widget resized from large to 1×1 and back using launcher handles; a new widget was then added from the launcher picker (advertised 1×1), rendered as one cell with actual saved goal/title/countdown/3/50 immediately; inspected alongside the larger widget |
| Actual compact progress | After runtime-discovered truncation fix, screenshot shows full `3/50` and `D-91` without clipped digits |
| Actual update/deep link | Dedicated QA goal incremented from 2/50 to 3/50; launcher widget readback updated; widget tap opened the same goal with three entries |
| Actual larger widget | Readable title/countdown, 3/50 progress and current cadence after expansion; inspected screenshot |

Runtime QA found and fixed a defect missed by static review: `UPCOMING · 3/50 ...` ellipsized the numeric progress in 1×1. Final compact rendering removes visible status/unit, preserves the full accessibility description, and was rebuilt/reinstalled/rechecked. The first integrated APK build also exposed an incorrect resize callback signature; corrected to `(Context, AppWidgetManager, Int, Bundle)` before the successful build.

The isolated dark InputDecorator regression initially read only the undecorated property; it was corrected to assert effective `applyDefaults` theme resolution. These earlier failures were not counted as passes.

## Artifact

- Application version remains `1.1.0+2`; release tag identifies this bounded UI checkpoint separately.
- API build define: `GROUPS_API_URL=https://its-the-day.himanusia.com`.
- APK SHA-256: `7ee74166c1e06decab896db7fd862af5d04ad58a3438e8ab9366c2f8621e8a9f`.
- Debug-signed early-access artifact, not an app-store release.

## Bounds

Physical Samsung is absent; no physical APK replacement claimed. Runtime launcher mask checked was circular; other masks have static safe-zone evidence, not a complete physical launcher matrix. Initial one-cell creation and subsequent resizing were exercised through the actual launcher picker and resize handles. Dark runtime screenshot covers Account; remaining forms share the audited theme and regressions, not a full manual screenshot matrix. No reboot/date-rollover/physical notifications or smooth-motion claims. Existing `flutter_timezone` Kotlin-plugin deprecation warning remains nonblocking. This checkpoint does not complete alarms, durable outbox/realtime, OAuth provider setup, or the broader product.
