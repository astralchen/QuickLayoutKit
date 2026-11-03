# Native tab direction isolation

This diagnostic app links UIKit/QuartzCore and the Objective-C runtime only. It does not use AppLocalization, QuickLayoutKit, package dependencies, language preferences, or appearance proxies.

It retains one UITabBarController, its native tab bar, and its children through LTR -> RTL -> LTR -> RTL -> LTR. A UINavigationController inside the selected tab is the comparison control. Container traits and public semantic attributes follow each direction.

Build with Xcode, or:

```sh
xcodebuild -project Experiments/TabDirectionIsolation/TabDirectionIsolation.xcodeproj \
  -scheme TabDirectionIsolation -sdk iphonesimulator \
  -derivedDataPath /tmp/TabDirectionIsolation build
```

Install and launch `com.quicklayoutkit.TabDirectionIsolation` on an iPad simulator. The app writes `tmp/tab-direction-layers.json` in its data container after approximately three seconds. Pass `--refresh` to additionally exercise public property, constraint, and layout refresh APIs; that run writes `tmp/tab-direction-refresh.json`.

Snapshots contain public view/layer transforms, direction traits, local-to-parent/window coordinate conversion, object identities, and read-only diagnostic getters for internal horizontal-axis flipping. The internal getters are not supported public APIs and are confined to this diagnostic app. The default, public-recovery, and owned-control runs call no private setter. The explicit `--cache` experiment below can call a private setter. This target must not be linked into the shipping app or package.

On the tested iPad simulator (iOS 27.2), `_UIFloatingTabBarCollectionView` retains its horizontal-axis flip after returning to LTR, while its cells clear their compensating flips. Public transforms remain identity. Explicit public refresh did not correct this. Native navigation-bar labels remained correctly oriented. See `Docs/TabDirectionInvestigation-2026-11-02.md` for the evidence and integration results.

## Setter trace

On an arm64 simulator, launch with `--debug-pause`. The app stops after its first layout, before the direction round trip. Attach LLDB to the PID printed by `simctl launch`, then run (from the repository root):

```text
expr -l objc++ -- @import UIKit
command script import Experiments/TabDirectionIsolation/Tools/trace_flips.py
trace-flips /tmp/tab-flip-events.jsonl
continue
```

The debugger logs native calls to the collection view's axis setter, its direction-trait callback, and the compositional layout's RTL-cache setter. Breakpoints automatically continue and only read object state. The app itself performs every language-direction transition. After the run, interrupt and detach the debugger normally.

The captured `Evidence/autonomous-setter-events.jsonl` shows that each RTL-to-LTR transition first clears the axis flip in `UICollectionView._layoutDirectionTraitDidChange`, then sets it back to true in `UICollectionViewCompositionalLayout._fullResolve`. The layout's `layoutRTL` cache remains true. This is a clear-then-overwrite sequence, not a missing trait callback.

## Public recovery matrix

Run one candidate with `--recovery=idiom` (or `compact-idiom`, `sidebar`, `hide`, `items`, `appearance`, `batch`, `minimize`, `content-size`). Each candidate keeps the same root controller, restores its final native presentation, and repeats the round trip twice. A later badge/layout update checks for recurrence.

To execute all candidates on a booted simulator:

```sh
python3 Experiments/TabDirectionIsolation/Tools/run_recoveries.py \
  --simulator YOUR_IPAD_UDID \
  --app /tmp/TabDirectionIsolation/Build/Products/Debug-iphonesimulator/TabDirectionIsolation.app \
  --output /tmp/tab-recovery-results
```

The nine tested candidates did not reset or replace the native layout on iPad / iOS 27.2. See `Evidence/public-recovery-results.json`. The sidebar experiment also leaves a separate, correctly oriented sidebar label in the hierarchy; that label must not be mistaken for a repaired floating tab label.

`--owned-control` adds a separate app-owned compositional collection view to the selected page. It invalidates that layout on direction changes and compares invalidation, configuration changes, reattaching the same layout, and installing a new layout. Each action is followed by another invalidation to distinguish temporary recovery from cache reset. This control never accesses or replaces the native tab bar's collection view.

The owned-control result is in `Evidence/owned-collection-results.json`: reattaching the old layout clears the axis flip temporarily but preserves `layoutRTL=true`, so the next invalidation reproduces the mirror. A new app-owned layout resets the cache and survives invalidation. Neither operation changes the system tab bar's layout. Those public-API experiments did not establish a stable native floating-tab recovery.

## Native UITab API refresh (2026-11-03)

The `tabs-*` candidates initialize with `UITabBarController.tabs` from the start. They use the original UITab instances and their existing page providers, and restore selection via `selectedTab`. They do not use UITabBarController.viewControllers after setting tabs. The later badge update also uses UITab.badgeValue.

```sh
python3 Experiments/TabDirectionIsolation/Tools/run_recoveries.py \
  --simulator YOUR_IPAD_UDID \
  --app /tmp/TabDirectionIsolation/Build/Products/Debug-iphonesimulator/TabDirectionIsolation.app \
  --output /tmp/tab-modern-api-results \
  --cases tabs-assign tabs-set tabs-animated tabs-empty tabs-reorder tabs-remove-unselected tabs-reselect
```

Cases cover direct tabs reassignment, setTabs with/without animation, empty/restore, reorder/restore, remove unselected tabs/restore, and select another tab/reselect. `modernTabState` records UITab object identities, selectedTab identity, its resolved controller, and the selected navigation root page. The final native layout identity and label coordinates distinguish content refresh from layout-cache recovery.

## Opt-in private cache experiment (2026-11-03)

This is a diagnostic proof, not a supported production fix. `--cache=before` calls the observed private `setLayoutRTL:` on the existing native layout before updating direction; `--cache=after` does so after direction assignments but before explicit layout. `--cache=late` waits until the layout has settled. `--cache=none` is the baseline and never calls a setter. The setter is guarded by the exact native layout class and Objective-C method ABI. There is no swizzle, axis setter, transform correction, replacement layout, or controller replacement.

Each run uses nine alternating direction stages. It changes the first title between Chinese and Arabic, updates its badge, invalidates the native layout, temporarily reduces UIWindow bounds width by 80 points, and restores the width. This is synthetic bounds stress, not a system multitasking gesture test. An existing UITextView becomes first responder once at startup; each stage appends text without refocusing it. Snapshots retain its identity, text, selected range, and first-responder state. This input probe is not the Demo chat regression.

```sh
python3 Experiments/TabDirectionIsolation/Tools/run_cache_probes.py \
  --simulator YOUR_IPAD_UDID \
  --app /tmp/TabDirectionIsolation/Build/Products/Debug-iphonesimulator/TabDirectionIsolation.app \
  --output /tmp/tab-cache-results
```

`--initial-rtl` starts the controller in RTL; `--modern-tabs` initializes with UITab. The runner covers both start directions and both tab APIs. Complete view/layer snapshots are stored in the output directory; compact records are in `Evidence/cache-results.json`.

For the user-provided Medium article's additional suggestion, `--modern-tabs --clear-legacy-items --cache=none` sets each provider's existing controller.tabBarItem to nil before returning the controller. Run the same tool with `--article-only` to compare modern UITab initialization with and without that change. This comparison invokes no private setter.

## Unspecified semantic attributes (2026-11-03)

`--semantics=inherited` sets the selected direction only on UIWindow.semanticContentAttribute, while the tab/navigation controller views, bars, and page use `.unspecified`. `--semantics=traits` also leaves the window unspecified. Both continue to update the tab/navigation controller layoutDirection trait overrides according to the selected direction. The default `explicit` behavior is unchanged.

Run `Tools/run_cache_probes.py` with the same simulator/app/output arguments and `--semantics-only` to compare these two strategies using native UITab and `--cache=none`. Each run includes four direction round trips, content/layout/bounds stress, and the input probe. Neither strategy calls a private setter. Inspect effective direction as well as trait direction: absence of mirrored text alone would not establish correct RTL behavior.

## Upstream traits, timing, and presentation matrix (2026-11-03)

`Tools/run_public_matrix.py` builds no app itself; provide the built standalone app and a booted iPad simulator:

```sh
python3 Experiments/TabDirectionIsolation/Tools/run_public_matrix.py \
  --simulator YOUR_IPAD_UDID \
  --app /tmp/TabDirectionIsolation/Build/Products/Debug-iphonesimulator/TabDirectionIsolation.app \
  --output /tmp/tab-public-matrix-results
```

The 17 cases use native UITab, unspecified view semantics, and `--cache=none` (no private setter calls):

- Direction source: controller, window, or scene. Window/scene cases remove the child controllers' direction overrides, so direction is inherited from one upstream source.
- Title timing: after settling (baseline), before direction changes, immediately after an explicit direction layout, asynchronously queued to the main dispatch queue, or synchronously after direction assignments without an explicit intervening layout. The queue case does not guarantee a rendered frame or a full run-loop cycle. The synchronous case does not suppress UIKit's own synchronous layouts.
- Presentation: enter hidden, sidebar, or compact state before changing direction, lay out in that state, then restore the normal native bar. These are diagnostic transitions, not an accepted product flow. Additional snapshots capture entered/directed states as well as the restored bar.

Each case includes four direction round trips and later badge, native-layout invalidation, and synthetic bounds stress. The script reports failures as evidence (`candidatePassed=false`), not as a successful repair. Full snapshots and compact results remain in the requested output directory. Inputs are checked at sampled stages, including temporary presentation states; no claim of continuous focus between samples or IME composition coverage is made.

`--fresh-tabs-only` runs two lower-priority model replacement candidates. They clear selectedTab and tabs before direction changes, wait for UIKit to release old models, and inspect the public UIViewController.tab association. If any association remains, the experiment records `replacementBlocked=true` and stops without forcibly clearing it or assigning a controller to a second model. Otherwise it creates new UITab models with the same or new identifiers while keeping the original page controllers. These candidates intentionally change model identities; controller/page identities, final selection, native geometry, and input continuity remain acceptance criteria.
