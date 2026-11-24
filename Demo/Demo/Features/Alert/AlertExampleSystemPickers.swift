import Contacts
import MapKit
import QuickLayoutKit
import UIKit

@MainActor
enum AlertExampleContacts {
    static func make(select: @escaping (String) -> Void) -> AlertExampleList {
        let list = AlertExampleList { select($0.result) }
        list.setRows([], message: Localization.text("demo.alertExamples.contacts.loading"))
        list.loadOnAppearance = { [weak list] in
            guard let list else { return }
            if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
                Task { @MainActor [weak list] in
                    let allowed = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
                    guard let list else { return }
                    if allowed {
                        load(into: list)
                    } else {
                        list.setRows([], message: Localization.text("demo.alertExamples.contacts.denied"))
                    }
                }
            } else {
                load(into: list)
            }
        }
        return list
    }

    private static func load(into list: AlertExampleList) {
        Task { @MainActor [weak list] in
            let unnamed = Localization.text("demo.alertExamples.contacts.unnamed")
            let rows = await Task.detached(priority: .userInitiated) { readContacts(unnamed: unnamed) }.value
            if let rows {
                list?.setRows(rows, message: rows.isEmpty ? Localization.text("demo.alertExamples.contacts.empty") : nil)
            } else {
                list?.setRows([], message: Localization.text("demo.alertExamples.contacts.denied"))
            }
        }
    }

    nonisolated private static func readContacts(unnamed: String) -> [AlertExampleList.Row]? {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as NSString,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as NSString,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var rows: [AlertExampleList.Row] = []
        do {
            try CNContactStore().enumerateContacts(with: request) { contact, _ in
                let number = contact.phoneNumbers.first?.value.stringValue
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? number ?? unnamed
                rows.append(.init(id: contact.identifier, title: name, detail: name == number ? nil : number))
            }
            return rows
        } catch {
            return nil
        }
    }
}

@MainActor
final class AlertExampleLocation: QuickLayoutHostingController, UISearchBarDelegate, @preconcurrency CLLocationManagerDelegate {
    private let map = MKMapView()
    private let search = UISearchBar()
    private let status = LocalizedLabel()
    private let resultsButton = UIButton(type: .system)
    private let locate = UIButton(type: .system)
    private let pick = UIButton(type: .system)
    private let locationManager = CLLocationManager()
    private var pendingSearch: MKLocalSearch?
    private var annotation: MKPointAnnotation?
    private var selectionName: String?
    private var awaitsLocationAuthorization = false
    private let select: (String) -> Void

    init(select: @escaping (String) -> Void) {
        self.select = select
        super.init(nibName: nil, bundle: nil)
        preferredContentSize.height = 290
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        search.placeholder = Localization.text("demo.alertExamples.map.search")
        search.searchBarStyle = .minimal
        search.delegate = self
        search.accessibilityIdentifier = "alerts.map.search"
        map.accessibilityIdentifier = "alerts.map"
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 37.3349, longitude: -122.0090),
                                        latitudinalMeters: 18_000, longitudinalMeters: 18_000), animated: false)
        map.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectPoint(_:))))
        locationManager.delegate = self

        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        status.text = Localization.text("demo.alertExamples.map.instruction")
        resultsButton.setTitle(Localization.text("demo.alertExamples.map.searchResults"), for: .normal)
        resultsButton.showsMenuAsPrimaryAction = true
        resultsButton.isHidden = true
        locate.setImage(UIImage(systemName: "location"), for: .normal)
        locate.accessibilityLabel = Localization.text("demo.alertExamples.map.currentLocation")
        locate.addAction(UIAction { [weak self] _ in self?.requestLocation() }, for: .touchUpInside)
        pick.setTitle(Localization.text("demo.alertExamples.map.confirm"), for: .normal)
        pick.accessibilityIdentifier = "alerts.map.choose"
        pick.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let coordinate = annotation?.coordinate ?? map.centerCoordinate
            select(selectionName ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
        }, for: .touchUpInside)
    }

    override var body: Layout {
        VStack(spacing: 4) {
            search.resizable().frame(height: 44)
            if !resultsButton.isHidden { resultsButton.resizable(axis: .horizontal) }
            map.resizable()
            status.resizable(axis: .horizontal)
            HStack(spacing: 0) {
                locate.resizable(axis: .horizontal)
                pick.resizable(axis: .horizontal)
            }
        }
    }

    @objc private func selectPoint(_ gesture: UITapGestureRecognizer) {
        setSelection(map.convert(gesture.location(in: map), toCoordinateFrom: map), name: nil)
    }

    private func setSelection(_ coordinate: CLLocationCoordinate2D, name: String?) {
        if let annotation { map.removeAnnotation(annotation) }
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title = name ?? Localization.text("demo.alertExamples.map.selectedLocation")
        map.addAnnotation(pin)
        annotation = pin
        selectionName = name
        status.text = pin.title
        setNeedsQuickLayout()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        guard let query = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return }
        pendingSearch?.cancel()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = map.region
        let operation = MKLocalSearch(request: request)
        pendingSearch = operation
        status.text = Localization.text("demo.alertExamples.map.searching")
        setNeedsQuickLayout()
        Task { @MainActor [weak self] in
            let response = try? await operation.start()
            guard let self, pendingSearch === operation else { return }
            pendingSearch = nil
            let places = response?.mapItems ?? []
            resultsButton.isHidden = places.isEmpty
            status.text = response == nil ? Localization.text("demo.alertExamples.map.searchUnavailable") : Localization.text("demo.alertExamples.map.found", places.count)
            setNeedsQuickLayout()
            resultsButton.menu = UIMenu(children: places.map { place in
                UIAction(title: place.name ?? Localization.text("demo.alertExamples.map.location")) { [weak self] _ in
                    guard let self else { return }
                    let coordinate = place.placemark.coordinate
                    setSelection(coordinate, name: place.name)
                    map.setCenter(coordinate, animated: true)
                }
            })
        }
    }

    private func requestLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            awaitsLocationAuthorization = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locationManager.requestLocation()
        default:
            status.text = Localization.text("demo.alertExamples.map.denied")
            setNeedsQuickLayout()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard awaitsLocationAuthorization, manager.authorizationStatus != .notDetermined else { return }
        awaitsLocationAuthorization = false
        requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        setSelection(location.coordinate, name: Localization.text("demo.alertExamples.map.currentLocation"))
        map.setCenter(location.coordinate, animated: true)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        status.text = Localization.text("demo.alertExamples.map.currentUnavailable")
        setNeedsQuickLayout()
    }
}

@MainActor
final class AlertExampleAttachments: QuickLayoutHostingController {
    private static let pageSpacing: CGFloat = 8
    private static let preferredWidth: CGFloat = 270
    private let horizontalInset: CGFloat
    private let makePage: (Int) -> UIViewController
    private let tabs = UISegmentedControl(items: [
        Localization.text("demo.alertExamples.attachments.photos"),
        Localization.text("demo.alertExamples.attachments.contacts"),
        Localization.text("demo.alertExamples.map.location"),
    ])
    private var pages: [Int: UIViewController] = [:]
    private var current: UIViewController?
    private var visible = false

    init(legacyActionSheetWidth: CGFloat? = nil, makePage: @escaping (Int) -> UIViewController) {
        horizontalInset = legacyActionSheetWidth == nil ? 0 : 16
        self.makePage = makePage
        super.init(nibName: nil, bundle: nil)
        // UIKit 在显示弹窗前会读取嵌入控制器的首选尺寸。
        let firstPage = makePage(0)
        pages[0] = firstPage
        updateHeight(for: firstPage)
        preferredContentSize.width = legacyActionSheetWidth ?? Self.preferredWidth
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        tabs.accessibilityIdentifier = "alerts.attachments.tabs"
        tabs.selectedSegmentIndex = 0
        tabs.addAction(UIAction { [weak self] _ in self?.showSelectedPage() }, for: .valueChanged)
        showSelectedPage()
    }

    override var body: Layout {
        VStack(spacing: Self.pageSpacing) {
            tabs.resizable(axis: .horizontal)
            if let current { current.view.resizable() }
        }
        .padding(.horizontal, horizontalInset)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        if let current, container === current { updateHeight(for: current) }
    }

    private func updateHeight(for controller: UIViewController) {
        let height = max(100, controller.preferredContentSize.height) + tabs.intrinsicContentSize.height + Self.pageSpacing
        if preferredContentSize.height != height { preferredContentSize.height = height }
    }

    private func showSelectedPage() {
        let index = tabs.selectedSegmentIndex
        let next = pages[index] ?? makePage(index)
        guard current !== next else { return }
        pages[index] = next
        if let current {
            current.willMove(toParent: nil)
            if visible { current.beginAppearanceTransition(false, animated: false) }
            current.view.removeFromSuperview()
            if visible { current.endAppearanceTransition() }
            current.removeFromParent()
        }
        current = next
        addChild(next)
        if visible { next.beginAppearanceTransition(true, animated: false) }
        next.loadViewIfNeeded()
        setNeedsQuickLayout()
        quickLayoutIfNeeded()
        next.didMove(toParent: self)
        if visible { next.endAppearanceTransition() }
        updateHeight(for: next)
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("位置选择器") {
    AlertExamplesViewController.preview(.location)
}
#endif
