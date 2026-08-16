//
//  FormViewModel.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import Foundation

@MainActor
final class FormViewModel {
    enum Field: CaseIterable {
        case name
        case email
        case phone
        case address
        case notes
    }

    struct Values: Equatable {
        var name = ""
        var email = ""
        var phone = ""
        var address = ""
        var notes = ""

        subscript(field: Field) -> String {
            get {
                switch field {
                case .name: name
                case .email: email
                case .phone: phone
                case .address: address
                case .notes: notes
                }
            }
            set {
                switch field {
                case .name: name = newValue
                case .email: email = newValue
                case .phone: phone = newValue
                case .address: address = newValue
                case .notes: notes = newValue
                }
            }
        }
    }

    struct State: Equatable {
        let headerTitle: String
        let headerSubtitle: String
        let namePlaceholder: String
        let emailPlaceholder: String
        let phonePlaceholder: String
        let addressPlaceholder: String
        let notesTitle: String
        let customInputTitle: String
        let submitTitle: String
    }

    struct Submission: Equatable {
        let title: String
        let message: String
        let actionTitle: String
    }

    private let localizer: DemoLocalizer
    private var render: ((State) -> Void)?

    private(set) var state: State
    private(set) var values = Values()
    var onSubmission: ((Submission) -> Void)?

    convenience init() {
        self.init(localizer: .live)
    }

    init(localizer: DemoLocalizer) {
        self.localizer = localizer
        state = Self.makeState(localizer: localizer)
    }

    func bind(_ render: @escaping (State) -> Void) {
        self.render = render
        render(state)
    }

    func refreshLocalizedContent() {
        state = Self.makeState(localizer: localizer)
        render?(state)
    }

    func update(_ value: String, for field: Field) {
        values[field] = value
    }

    func nextField(after field: Field) -> Field? {
        switch field {
        case .name: .email
        case .email: .phone
        case .phone: .address
        case .address: .notes
        case .notes: nil
        }
    }

    func submit() {
        onSubmission?(
            Submission(
                title: localizer.text("form.alert.title"),
                message: localizer.text(
                    "form.summary",
                    values.name,
                    values.email,
                    values.phone,
                    values.address,
                    values.notes
                ),
                actionTitle: localizer.text("common.ok")
            )
        )
    }

    private static func makeState(localizer: DemoLocalizer) -> State {
        State(
            headerTitle: localizer.text("form.header.title"),
            headerSubtitle: localizer.text("form.header.subtitle"),
            namePlaceholder: localizer.text("form.name"),
            emailPlaceholder: localizer.text("form.email"),
            phonePlaceholder: localizer.text("form.phone"),
            addressPlaceholder: localizer.text("form.address"),
            notesTitle: localizer.text("form.notes"),
            customInputTitle: localizer.text("form.customInput"),
            submitTitle: localizer.text("form.submit")
        )
    }
}
