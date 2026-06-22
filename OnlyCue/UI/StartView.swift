import AppKit
import SwiftUI

/// The welcome window's content (#591): brand + actions on the left, the recent
/// projects list on the right. Dark DS styling matching `FirstLaunchSheet`.
struct StartView: View {

    @State private var recents: [RecentProject] = []

    private enum Metrics {
        static let windowWidth: CGFloat = 720
        static let windowHeight: CGFloat = 460
        static let actionsPaneWidth: CGFloat = 288
        static let heroSize: CGFloat = 96
    }

    var body: some View {
        HStack(spacing: 0) {
            actionsPane
                .frame(width: Metrics.actionsPaneWidth)
                .padding(DS.Space.xl)
            Divider()
            recentsPane
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.lg)
        }
        .frame(width: Metrics.windowWidth, height: Metrics.windowHeight)
        .background(DS.Color.panel)
        .task { recents = RecentProjectsModel.load() }
        .accessibilityIdentifier("startView")
    }

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Image("BrandHero")
                .resizable()
                .interpolation(.high)
                .frame(width: Metrics.heroSize, height: Metrics.heroSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("OnlyCue")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Plan and run lighting cues against your media.")
                    .font(DS.Text.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                actionButton("New Project", systemImage: "plus.square") { newDocument() }
                actionButton("New from Template…", systemImage: "doc.on.doc") { newFromTemplate() }
                actionButton("Open Other…", systemImage: "folder") { openOther() }
            }
            Spacer()
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(DS.Text.body)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Color.textPrimary)
        .accessibilityIdentifier("startAction.\(title)")
    }

    private var recentsPane: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Recent Projects").dsSectionHeader()
            if recents.isEmpty {
                Text("No recent projects")
                    .font(DS.Text.body)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(recents) { project in
                            RecentProjectRow(
                                project: project,
                                onOpen: { open(project) },
                                onRemove: { remove(project) }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func open(_ project: RecentProject) {
        guard project.exists else { return }
        NSDocumentController.shared.openDocument(withContentsOf: project.url, display: true) { _, _, _ in }
        closeWelcomeWindow()
    }

    private func newDocument() {
        NSDocumentController.shared.newDocument(nil)
        closeWelcomeWindow()
    }

    private func newFromTemplate() {
        try? TemplateAction.newDocument()
        closeWelcomeWindow()
    }

    private func openOther() {
        NSDocumentController.shared.openDocument(nil)
        closeWelcomeWindow()
    }

    private func remove(_ project: RecentProject) {
        let controller = NSDocumentController.shared
        let survivors = RecentProjectsModel.removing(project.url, from: controller.recentDocumentURLs)
        controller.clearRecentDocuments(nil)
        // Re-note oldest → newest so the rebuilt list keeps its newest-first order.
        for url in survivors.reversed() { controller.noteNewRecentDocumentURL(url) }
        recents = RecentProjectsModel.load()
    }

    /// The welcome window steps aside once a project opens. Closing the key
    /// window (the welcome window at the moment of action) keeps the launch flow
    /// clean. Verified by manual run.
    private func closeWelcomeWindow() {
        NSApp.keyWindow?.close()
    }
}

/// One recent-project row: name + folder + date, with an inline remove for an
/// entry whose file is missing (greyed).
private struct RecentProjectRow: View {
    let project: RecentProject
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xs / 2) {
                Text(project.name)
                    .font(DS.Text.body)
                    .foregroundStyle(project.exists ? DS.Color.textPrimary : DS.Color.textTertiary)
                Text(project.exists ? project.folder : "\(project.folder) — missing")
                    .font(DS.Text.small)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.sm)
            if let date = project.date {
                Text(date, format: .dateTime.month().day())
                    .font(DS.Text.monoSmall)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            if !project.exists {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.textTertiary)
                .help("Remove from Recents")
                .accessibilityIdentifier("removeRecent")
            }
        }
        .padding(.vertical, DS.Space.sm)
        .padding(.horizontal, DS.Space.sm)
        .contentShape(Rectangle())
        .onTapGesture { if project.exists { onOpen() } }
        .accessibilityIdentifier("recentRow")
    }
}
