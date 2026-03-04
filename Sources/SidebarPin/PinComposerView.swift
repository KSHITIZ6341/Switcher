import SwiftUI

struct PinComposerView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    var body: some View {
        ZStack {
            SidebarBackground()

            VStack(alignment: .leading, spacing: 12) {
                header

                if model.composerSource == .installedApp {
                    installedAppSection
                } else {
                    runningWindowSection
                }

                placementSection

                footer
            }
            .padding(18)
        }
        .frame(width: model.composerSource == .installedApp ? 760 : 700, height: model.composerSource == .installedApp ? 740 : 560)
        .onAppear {
            if model.composerSource == .installedApp {
                searchText = ""
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.composerSelectedBundleID)
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 12) {
                Group {
                    if let icon = model.icon(forBundleID: model.composerSelectedBundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.composerSource == .installedApp ? "Pin Installed App" : "Pin Running Window")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(model.selectedComposerAppDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                StatusChip(text: model.composerSelectedEdge.title + " Edge", color: .blue)
            }
        }
    }

    private var installedAppSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Installed Apps", systemImage: "square.grid.3x3.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(filteredInstalledApps.count) apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Search apps", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)

                if filteredInstalledApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("No apps match your search")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 106, maximum: 128), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(filteredInstalledApps) { app in
                                AppGridCell(
                                    app: app,
                                    icon: model.icon(for: app),
                                    isSelected: app.bundleId == model.composerSelectedBundleID
                                ) {
                                    model.updateBundleSelection(bundleID: app.bundleId)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 330, maxHeight: 390)
                }
            }
        }
    }

    private var runningWindowSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Running Windows", systemImage: "macwindow.on.rectangle")
                    .font(.headline)

                if model.runningWindows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.stack.badge.xmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("No running windows found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.runningWindows) { window in
                                RunningWindowRow(
                                    window: window,
                                    isSelected: String(window.windowID) == model.composerSelectedWindowID
                                ) {
                                    model.updateRunningWindowSelection(windowIDString: String(window.windowID))
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 180, maxHeight: 240)
                }
            }
        }
    }

    private var placementSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Placement", systemImage: "rectangle.inset.filled.and.person.filled")
                    .font(.headline)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Display", selection: $model.composerSelectedDisplayID) {
                            ForEach(model.displays) { display in
                                Text(display.name).tag(display.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Edge", selection: $model.composerSelectedEdge) {
                            ForEach(SidebarEdge.allCases) { edge in
                                Text(edge.title).tag(edge)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sidebar Size")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Width is fixed at 25% of the selected display. Height is the full screen height.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add up to 3 apps on one side. They stack vertically and split the height evenly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()

            Button("Cancel") {
                model.isComposerPresented = false
            }
            .buttonStyle(SoftButtonStyle())
            .frame(width: 120)

            Button {
                Task {
                    await model.confirmPin()
                }
            } label: {
                Label("Pin to Sidebar", systemImage: "pin.fill")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(PrimaryPillButtonStyle())
            .frame(width: 170)
            .disabled(!canSubmit)
        }
        .padding(.top, 2)
    }

    private var canSubmit: Bool {
        switch model.composerSource {
        case .installedApp:
            return !model.composerSelectedBundleID.isEmpty
        case .runningWindow:
            return !model.composerSelectedBundleID.isEmpty && !model.composerSelectedWindowID.isEmpty
        }
    }

    private var filteredInstalledApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return model.installedApps
        }

        return model.installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(query)
                || app.bundleId.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct RunningWindowRow: View {
    let window: RunningWindow
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "macwindow")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(window.appName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(window.title.isEmpty ? "Untitled window" : window.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.17)
                            : Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.98 : 0.88)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.75),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovering && !isSelected ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct AppGridCell: View {
    let app: InstalledApp
    let icon: NSImage
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 52, height: 52)

                Text(app.name)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
            .frame(height: 112)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.2)
                            : Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1.0 : 0.9)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.7),
                        lineWidth: isSelected ? 1.7 : 1
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 7 : 3, y: 2)
            .scaleEffect(isSelected ? 1.03 : (isHovering ? 1.015 : 1))
        }
        .buttonStyle(.plain)
        .help(app.bundleId)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}
