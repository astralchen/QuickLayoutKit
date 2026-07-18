# QuickLayoutKit

QuickLayoutKit is a UIKit support package for
[QuickLayout](https://github.com/facebookincubator/QuickLayout). It provides a
small set of UIKit-focused building blocks so view controllers, scroll views,
safe-area spacing, and self-sizing cells can be written with QuickLayout's
declarative layout syntax.

The package contains three modules:

- `QuickLayoutKit` is the public product and re-exports QuickLayout together
  with the public core and UIKit helpers.
- `QuickLayoutKitCore` contains shared QuickLayout extensions.
- `QuickLayoutKitUIKit` contains UIKit integration types.

## Requirements

- iOS 15.0 or later
- Swift 6.2 or later
- QuickLayout from `facebookincubator/QuickLayout`

## Installation

Add this repository to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/astralchen/QuickLayoutKit.git", branch: "main")
]
```

Then add the `QuickLayoutKit` product to your app target:

```swift
.target(
    name: "App",
    dependencies: [
        "QuickLayoutKit"
    ]
)
```

Import QuickLayoutKit where you declare layouts:

```swift
import QuickLayoutKit
```

## Core APIs

### `QuickLayoutHostingController`

`QuickLayoutHostingController` is a `UIViewController` subclass whose root view
is driven by a QuickLayout `body`.

Use subclassing when the screen owns state, targets, delegates, or lifecycle
work:

```swift
import UIKit
import QuickLayoutKit

final class CounterViewController: QuickLayoutHostingController {

    private var count = 0 {
        didSet {
            counterLabel.text = "\(count)"
            setNeedsQuickLayout()
        }
    }

    private let counterLabel = UILabel()
    private let incrementButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        counterLabel.font = .systemFont(ofSize: 48, weight: .bold)
        counterLabel.textAlignment = .center
        counterLabel.text = "\(count)"

        incrementButton.setTitle("Increment", for: .normal)
        incrementButton.addTarget(self, action: #selector(increment), for: .touchUpInside)
    }

    override var body: Layout {
        VStack(alignment: .center, spacing: 24) {
            Spacer()
            counterLabel
            incrementButton
            Spacer()
        }
        .padding(.all, 24)
    }

    @objc private func increment() {
        count += 1
    }
}
```

Use the closure initializer for small hosted layouts:

```swift
let titleLabel = UILabel()
titleLabel.text = "Quick Setup"

let viewController = QuickLayoutHostingController {
    VStack(spacing: 12) {
        titleLabel
    }
    .padding(.all, 24)
}
```

Call `setNeedsQuickLayout()` after mutating state that changes `body`.

### `QuickLayoutView`

`QuickLayoutView` is the reusable `UIView` host used by
`QuickLayoutHostingController`. Use it when a screen already has a UIKit view
controller and only one region needs QuickLayout content.

```swift
let titleLabel = UILabel()
titleLabel.text = "Inline Content"

let hostedView = QuickLayoutView {
    VStack(spacing: 8) {
        titleLabel
    }
    .padding(.all, 16)
}

hostedView.setNeedsQuickLayout()
let measured = hostedView.sizeThatFits(in: CGSize(width: 320, height: .infinity))
```

You can also subclass `QuickLayoutView` and override `body` for reusable UIKit
components.

### Container-relative frames

Use `containerRelativeFrame` to size an element from the nearest
QuickLayoutKit container. `QuickLayoutView`, `QuickLayoutHostingController`,
the list integration views, and `QuickLayoutScrollView` establish container
sizes automatically. Regular hosts exclude safe-area insets; scroll views use
their visible viewport after adjusted content insets.

Make an element fill the container along selected axes:

```swift
heroView
    .resizable()
    .containerRelativeFrame(.horizontal, alignment: .leading)
```

Divide the container into equal sections and let an item span multiple
sections:

```swift
ScrollView(scrollView, .horizontal) {
    ForEach(cardViews) { cardView in
        cardView
            .resizable()
            .containerRelativeFrame(
                .horizontal,
                count: 3,
                span: 2,
                spacing: 12
            )
    }
}
```

Use the closure overload for custom sizing:

```swift
panelView
    .resizable()
    .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
        axis == .horizontal ? length * 0.8 : length / 2
    }
```

When a layout is applied manually without a QuickLayoutKit host,
`containerRelativeFrame` falls back to the size proposed by its immediate
parent.

### Flexible frame ideal size

Use `idealWidth` and `idealHeight` to provide fallback dimensions when a
flexible frame receives an unspecified proposal:

```swift
card
    .resizable()
    .frame(
        minWidth: 160,
        idealWidth: 240,
        maxWidth: 320,
        minHeight: 100,
        idealHeight: 140,
        maxHeight: 200,
        alignment: .topLeading
    )
```

A finite size proposed by the parent takes precedence over the ideal size.
Minimum and maximum values are then applied to the resulting proposal.

### Aspect ratio

Pass a width-to-height ratio directly as a `CGFloat`:

```swift
videoView
    .resizable()
    .aspectRatio(16.0 / 9.0, contentMode: .fit)
```

`scaledToFit()` and `scaledToFill()` preserve the element's ideal aspect ratio
and are aliases for `aspectRatio(nil, contentMode: .fit)` and
`aspectRatio(nil, contentMode: .fill)` respectively.

### Custom layout algorithms

Conform a value type to `LayoutAlgorithm` when stacks, flows, and grids don't
describe the geometry you need. A custom layout first chooses its container
size from a `ProposedSize`, then places each `LayoutSubview` proxy:

```swift
private struct DiagonalLayout: LayoutAlgorithm {

    let step: CGFloat

    func sizeThatFits(
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(
            width: (sizes.map(\.width).max() ?? 0)
                + step * CGFloat(max(0, sizes.count - 1)),
            height: (sizes.map(\.height).max() ?? 0)
                + step * CGFloat(max(0, sizes.count - 1))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(
                    x: bounds.minX + step * CGFloat(index),
                    y: bounds.minY + step * CGFloat(index)
                ),
                proposal: ProposedSize(size)
            )
        }
    }
}

let cards = DiagonalLayout(step: 20) {
    firstCard.zIndex(0)
    secondCard.zIndex(1)
    thirdCard.zIndex(2)
}
```

`ProposedSize.zero`, `.infinity`, and `.unspecified` query minimum, maximum,
and ideal sizing behavior. A layout can cache repeated measurements by defining
a `Cache` type and implementing `makeCache(subviews:)`; QuickLayoutKit passes
the same cache to measurement and placement and calls `updateCache` before a
later layout pass.

Define a `LayoutValueKey` to attach application-specific metadata to direct
children:

```swift
private enum RankKey: LayoutValueKey {
    static let defaultValue = 0
}

card
    .frame(width: 120, height: 80)
    .layoutValue(key: RankKey.self, value: 2)
```

Read the value as `subview[RankKey.self]` inside the algorithm. Keep
`layoutValue` after QuickLayout sizing modifiers so it remains attached to the
direct child proxy.

Use `position(_:)` or `position(x:y:)` to place an element's center at explicit
parent coordinates. Use `zIndex(_:)` for overlapping content; larger values
appear above smaller values, while equal values retain source order.

### Content margins

Use `contentMargins` to add space between a managed scroll view's viewport and
its content without wrapping the content in `padding`:

```swift
ScrollView(scrollView, .horizontal) {
    HStack(spacing: 16) {
        ForEach(cards) { card in
            card
                .resizable()
                .containerRelativeFrame(
                    .horizontal,
                    count: 3,
                    span: 2,
                    spacing: 16
                )
        }
    }
}
.contentMargins(.horizontal, 16)
```

The default `.automatic` placement moves both scrollable content and scroll
indicators. Use `.scrollContent` or `.scrollIndicators` to target one
placement. Leading and trailing margins follow the scroll view's effective
layout direction. A scroll view's `containerRelativeFrame` viewport excludes
its content margins, so relative cards size from the remaining visible area.

### Safe-area layout

QuickLayoutKit hosts propagate container safe-area insets through the layout
tree. Use `safeAreaPadding` to consume those insets and add optional spacing:

```swift
contentView
    .safeAreaPadding(.horizontal, 20)
    .safeAreaPadding(.vertical, 12)
```

The overloads mirror SwiftUI and accept selected edges, one value for all
edges, or directional `EdgeInsets`. Calling `safeAreaPadding()` uses a default
spacing of 16 points.

Use `safeAreaInset` to place content beside a safe-area edge while reserving
its measured size for the main content:

```swift
contentView.safeAreaInset(edge: .bottom, spacing: 8) {
    actionBar
        .resizable()
        .frame(height: 52)
}
```

Vertical edges accept a `HorizontalAlignment`; horizontal edges accept a
`VerticalAlignment`. Use `ignoresSafeArea` to expand selected regions and
edges:

```swift
backgroundView
    .resizable()
    .containerRelativeFrame([.horizontal, .vertical])
    .ignoresSafeArea(.container, edges: .all)
```

`QuickLayoutKeyboardAvoider` publishes a keyboard safe-area region for a
managed `QuickLayoutScrollView`, so `.ignoresSafeArea(.keyboard, edges:
.bottom)` can opt a subtree out of keyboard avoidance.

### Adaptive alternatives

Use `ViewThatFits` to declare layouts in preference order. QuickLayoutKit
selects the first alternative whose ideal size fits the proposed size on the
requested axes, and uses the final alternative as a fallback:

```swift
ViewThatFits(in: .horizontal) {
    HStack(spacing: 12) {
        titleLabel
        actionButton
    }
    VStack(alignment: .leading, spacing: 8) {
        titleLabel
        actionButton
    }
}
```

The default axis set is `[.horizontal, .vertical]`. Unselected UIKit views are
collapsed to zero size when the chosen alternative changes.

### Geometry changes

Use `onGeometryChange` to derive an `Equatable` value from an element's applied
geometry and react only when that value changes:

```swift
contentView
    .resizable()
    .onGeometryChange(for: CGSize.self) { geometry in
        geometry.size
    } action: { size in
        print("Applied size:", size)
    }
```

`GeometryProxy` exposes `size`, `safeAreaInsets`, and `frame(in:)` for the
`.local`, `.global`, and nearest `.scrollView` coordinate spaces. Measurement
with `sizeThatFits` has no callback side effects. An additional overload passes
both the previous and current transformed values; its initial callback receives
the initial value in both parameters.

### `QuickLayoutViewControllerRepresentable`

`QuickLayoutViewControllerRepresentable` embeds a child `UIViewController`
inside a QuickLayout `body`. It only handles UIKit containment and resolves its
parent view controller from the UIKit responder chain when QuickLayout inserts
the host view. Lazy creation is provided by QuickLayout's existing `LazyView`, so
the child controller is not created until the lazy element is first read by
QuickLayout.

```swift
final class ParentViewController: QuickLayoutHostingController {

    private var showsChild = false

    private lazy var lazyChild = LazyView { [unowned self] in
        let child = ChildViewController()
        let host = QuickLayoutViewControllerRepresentable(child)
        host.eventHandler = { event in
            print("representable event:", event.name)
        }
        host.detailedEventHandler = { event in
            print("representable detailed event:", event.kind.name)
        }
        return host
    }

    override var body: Layout {
        VStack(spacing: 16) {
            if showsChild {
                lazyChild.frame(height: 320)
            }
        }
    }

    func replaceLoadedChild() {
        lazyChild.ifLoaded?.setViewController(ChildViewController())
    }

    func resetLazyChild() {
        lazyChild.ifLoaded?.dismantleViewController()
        lazyChild = LazyView { [unowned self] in
            QuickLayoutViewControllerRepresentable(ChildViewController())
        }
    }
}
```

The representable attaches the child in `didMoveToSuperview` when QuickLayout
inserts the host view, and detaches the child when QuickLayout removes the host
view. A loaded `LazyView` keeps its host instance; replace the stored `LazyView`
when the next display should create a fresh child controller. Use
`captureParent(_:)` or `init(_:parent:)` only when the host does not live under a
standard controller-owned UIKit view hierarchy.

Use `detailedEventHandler` when integration logs need containment context such
as the resolved parent, old child, new child, or missing-parent reason. If the
child changes `preferredContentSize`, call `invalidateChildLayout()` on the
representable so QuickLayout can remeasure the hosted controller.

### Layout updating

`QuickLayoutHostingController`, `QuickLayoutView`, and the list integration
views conform to `QuickLayoutUpdating`. Use
`setNeedsQuickLayout()` after state changes, `quickLayoutIfNeeded()` when the
layout must be resolved immediately, and `performLayoutUpdate(...)` when the
layout should animate with UIKit.

### `QuickLayoutScrollView`

`QuickLayoutScrollView` is a `UIScrollView` that measures QuickLayout content
and keeps its `contentSize` in sync during layout.

```swift
final class DynamicScrollViewController: QuickLayoutHostingController {

    private let scrollView = QuickLayoutScrollView()
    private var rows: [UIView] = []

    override var body: Layout {
        ScrollView(scrollView, .vertical) {
            VStack(spacing: 12) {
                ForEach(rows) { row in
                    row.frame(height: 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, view.quickLayoutSafeAreaInsets.bottom)
        }
    }
}
```

The scroll view also supports direct construction:

```swift
let scrollView = QuickLayoutScrollView(.vertical, showsIndicators: false) {
    headerView
    contentView
    footerView
}
```

Like SwiftUI's `ScrollView`, the primary API consists of an axis, indicator
visibility, and builder content. QuickLayoutKit accepts one axis rather than an
axis set because it uses that choice to provide an implicit `VStack` or
`HStack`. Pass `.horizontal` for horizontally arranged content.

For RTL-aware horizontal scrolling, the scroll view resolves leading and
trailing from the current UIKit direction. Use UIKit's native semantic content
attribute when an app-level language switch supplies an explicit direction:

```swift
scrollView.semanticContentAttribute = .forceRightToLeft
scrollView.scrollTo(.leading, animated: false) // physical right in RTL
```

`ScrollView` refreshes the existing UIKit instance with the latest builder
content whenever its containing QuickLayout body is evaluated. Keep mutable
content in the controller, then invalidate the host after changing it:

```swift
rows.append(newRowView)
setNeedsQuickLayout()
quickLayoutIfNeeded()
scrollView.scrollTo(.bottom, animated: true)
```

Other behavior stays in UIKit's existing API: use `isScrollEnabled`,
`keyboardDismissMode`, `alwaysBounceVertical`, `alwaysBounceHorizontal`, or
`UIScrollViewDelegate` instead of parallel QuickLayout-specific wrappers.

### Layout direction

QuickLayout already supports layout direction through `.layoutDirection(...)`.
Use it for QuickLayout-managed leading and trailing layout instead of manually
setting `textAlignment` on every label.

```swift
private lazy var menuContentView = QuickLayoutView { [unowned self] in
    VStack(alignment: .leading, spacing: 12) {
        ForEach(self.menuViews) { view in
            self.menuElement(for: view)
        }
    }
    .padding(.horizontal, 16)
    .layoutDirection(self.currentQuickLayoutDirection)
}

private var currentQuickLayoutDirection: LayoutDirection {
    effectiveUserInterfaceLayoutDirection == .rightToLeft
        ? .rightToLeft
        : .leftToRight
}

private func menuElement(for view: UIView) -> Element {
    if view is UILabel {
        return view.frame(height: 28)
    }

    return view
        .resizable()
        .frame(height: 44)
}
```

Keep text views and labels on `.natural` alignment when the layout position is
owned by QuickLayout. For example, a section header can remain
`textAlignment = .natural` and `semanticContentAttribute = .unspecified`, while
`VStack(alignment: .leading)` and `.layoutDirection(.rightToLeft)` move it to
the physical right side. Use UIKit `semanticContentAttribute` for UIKit-owned
behavior such as scroll view semantics, navigation bars, collection views, and
system controls.

### Keyboard helpers

Use `QuickLayoutKeyboardObserver` when you only need parsed keyboard context,
including the event, begin/end frames, animation duration, and animation
options. Resolve the context against the view that owns the layout before using
the keyboard height; this measures the actual intersection, so floating
keyboards, split keyboards, iPad windows, and hardware-keyboard transitions do
not over-inset the UI.

```swift
final class FormViewController: QuickLayoutHostingController {

    private let scrollView = QuickLayoutScrollView()
    private let keyboardObserver = QuickLayoutKeyboardObserver()
    private lazy var keyboardAvoider = QuickLayoutKeyboardAvoider(
        scrollView: scrollView,
        observer: keyboardObserver
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboardAvoider.extraBottomPadding = 12
        keyboardAvoider.safeAreaStrategy = .subtractExisting
        _ = keyboardAvoider
    }

    func keyboardDidChange(_ context: QuickLayoutKeyboardContext) {
        let resolved = context.resolved(in: scrollView)
        print(context.event, resolved.height, resolved.intersection)
    }
}
```

`QuickLayoutKeyboardAvoider` uses `context.resolved(in: scrollView)` internally.
Its `safeAreaStrategy` defaults to `.ignore`, which avoids double-counting when
your QuickLayout body already pads for safe area. Use `.add` only when the
scroll content does not include safe-area padding, or `.subtractExisting` when
the base inset already contains the bottom safe area.

`QuickLayoutKeyboardContext.height` remains a compatibility fallback for raw
notifications. For precise layout use `context.resolved(in: view).height`; if
you need the system-reported frame, read `context.endFrame.height`.

Custom input controls can participate in active-view tracking by posting:

```swift
NotificationCenter.default.post(
    name: .quickLayoutKeyboardActiveInputDidBeginEditing,
    object: customInputView,
    userInfo: ["activeView": customInputView]
)
```

If the app changes the scroll view's base insets after creating the avoider,
call `captureCurrentInsetsAsBase()` before the next keyboard transition.

### Layout environment helpers

`UIView.quickLayoutSafeAreaInsets` converts UIKit safe-area insets to
`QuickLayout.EdgeInsets` and respects the view's effective layout direction.
UIKit integration also exposes direction-aware layout margins, readable content
insets, and safe-area-plus-margin composition:

```swift
override var body: Layout {
    contentView
        .padding(.horizontal, view.quickLayoutContentInsets.maximumHorizontalInset)
        .padding(.bottom, view.quickLayoutContentInsets.bottom)
}
```

Read environment values after the view has been laid out. In a hosting
controller body, they are commonly used as part of the layout pass. Prefer
direction-aware helpers over direct `safeAreaInsets.left` or
`layoutMargins.right` access when the UI can run in RTL.

`UIView.quickLayoutEnvironment` captures the current layout direction, dynamic
type category, size classes, interface style, display scale, safe area, and
layout margins. `QuickLayoutView` compares that environment during trait, safe
area, margin, and window changes, then calls
`quickLayoutEnvironmentDidChange(_:reason:)`. Override that hook for reusable
views that need to refresh cached UIKit content before QuickLayout runs again.

### Collection view sizing helpers

Use `QuickLayoutCollectionViewCell`, `QuickLayoutTableViewCell`, and
`QuickLayoutCollectionReusableView` when your reusable views are fully described
by QuickLayout.

```swift
final class MessageCell: QuickLayoutCollectionViewCell {

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override var body: Layout {
        VStack(alignment: .leading, spacing: 4) {
            titleLabel
            messageLabel
        }
        .padding(.all, 12)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
```

For custom cell subclasses that cannot inherit from QuickLayoutKit's base
classes, keep using `quickLayoutSizeLimit(proposed:)` and
`quickLayoutFlexibility(for:)` to describe fixed and measured axes.

### Diagnostics

`QuickLayoutDiagnostics` is an opt-in debug helper for layout pass auditing. It
records the layout host name and measured size when enabled.

```swift
QuickLayoutDiagnostics.isEnabled = true
QuickLayoutDiagnostics.reset()

view.setNeedsLayout()
view.layoutIfNeeded()

let snapshot = QuickLayoutDiagnostics.snapshot()
```

## Demo App

The `Demo` project contains examples for:

- Basic hosted screens
- Counters and state-driven relayout
- Vertical and horizontal scrolling
- Safe-area padding
- Dynamic content insertion
- Keyboard-aware scrolling
- Self-sizing collection view cells
- UIKit semantic content direction behavior
- Environment inset helpers
- Debug diagnostics
- Lazy view controller containment with `QuickLayoutViewControllerRepresentable`
- Runtime language switching with String Catalogs and AppLocalization
- QuickLayout-driven LTR/RTL layout direction for menu headers
- UIKit, collection view, navigation, gesture, modal, and SwiftUI localization
  bridge examples

Open `Demo/Demo.xcodeproj` in Xcode and run the `Demo` scheme to explore the
examples.

## Testing

QuickLayoutKit is a UIKit package, so validate it with an iOS Simulator
destination from Xcode or `xcodebuild`:

```sh
Scripts/verify-demo-build.sh
xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Run the demo app from Xcode when validating UIKit layout behavior visually.

## License

QuickLayoutKit is available under the MIT license. See `LICENSE` for details.
