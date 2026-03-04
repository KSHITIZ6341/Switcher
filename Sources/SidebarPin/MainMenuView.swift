import SwiftUI

struct MainMenuView: View {
    @ObservedObject var model: AppModel
    var isCompact: Bool = false

    var body: some View {
        ZStack {
            SidebarBackground()

            ScrollView {
                VStack(spacing: 12) {
                    headerCard

                    if !model.permissionGranted {
                        permissionCard
                    }

                    actionCard
                    controlCard

                    if let status = model.statusMessage {
                        messageCard(text: status, color: .blue, icon: "info.circle.fill")
                    }

                    if let error = model.errorMessage {
                        messageCard(text: error, color: .red, icon: "exclamationmark.triangle.fill")
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
        }
        .frame(
            minWidth: isCompact ? 390 : 500,
            minHeight: isCompact ? 500 : 620
        )
        .animation(.easeInOut(duration: 0.2), value: model.pinStatus)
        .animation(.easeInOut(duration: 0.2), value: model.permissionGranted)
        .task {
            model.start()
        }
        .sheet(isPresented: $model.isComposerPresented) {
            PinComposerView(model: model)
        }
        .contextMenu {
            Button(model.autoHoverEnabled ? "Disable Automatic Edge Hover" : "Enable Automatic Edge Hover") {
                model.setAutoHoverEnabled(!model.autoHoverEnabled)
            }
        }
    }

    private var headerCard: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sidebar Pin")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(model.pinnedTargetDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if model.pinStatus.isPinned {
                    StatusChip(text: "Pinned \(model.pinStatus.pinnedCount)/3", color: .green)
                } else {
                    StatusChip(text: "Idle", color: .orange)
                }
            }
        }
    }

    private var permissionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Accessibility Required", systemImage: "hand.raised.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text("Grant Accessibility permission so Sidebar Pin can move and resize other app windows.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    model.requestAccessibilityPermission()
                } label: {
                    Label("Grant Permission", systemImage: "lock.open.display")
                }
                .buttonStyle(PrimaryPillButtonStyle())
            }
        }
    }

    private var actionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pinning")
                    .font(.headline)

                HStack(spacing: 10) {
                    Button {
                        model.openComposer(for: .installedApp)
                    } label: {
                        Label("Pin App", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .disabled(!model.permissionGranted)

                    Button {
                        model.openComposer(for: .runningWindow)
                    } label: {
                        Label("Running Window", systemImage: "macwindow.on.rectangle")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(!model.permissionGranted)
                }

                HStack(spacing: 10) {
                    Button {
                        model.bringPinnedWindowForward()
                    } label: {
                        Label("Bring Forward", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(!model.pinStatus.isPinned)

                    Button {
                        Task {
                            await model.repin()
                        }
                    } label: {
                        Label("Repin", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(!model.canRepin)

                    Button {
                        model.unpin()
                    } label: {
                        Label("Unpin One", systemImage: "pin.slash")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(!model.pinStatus.isPinned)
                }
            }
        }
    }

    private var controlCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preferences")
                    .font(.headline)

                Toggle(
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin(enabled: $0) }
                    )
                ) {
                    Label("Launch at Login", systemImage: "power")
                }
                .toggleStyle(.switch)

                Toggle(
                    isOn: Binding(
                        get: { model.autoHoverEnabled },
                        set: { model.setAutoHoverEnabled($0) }
                    )
                ) {
                    Label("Automatic Edge Hover", systemImage: "cursorarrow.motionlines")
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Blue Button Apps", systemImage: "circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.blue)

                    if model.installedApps.isEmpty {
                        Text("No installed apps found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(model.installedApps) { app in
                                    HStack(spacing: 8) {
                                        Image(nsImage: model.icon(for: app))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 16, height: 16)

                                        Text(app.name)
                                            .font(.caption)
                                            .lineLimit(1)

                                        Spacer(minLength: 6)

                                        Toggle(
                                            "",
                                            isOn: Binding(
                                                get: { model.isBlueButtonEnabled(for: app.bundleId) },
                                                set: { model.setBlueButtonEnabled($0, for: app.bundleId) }
                                            )
                                        )
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .controlSize(.small)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 170)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        model.refreshCatalogAndDisplays()
                        model.refreshPermissionState()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(SoftButtonStyle())

                    Button(role: .destructive) {
                        model.quit()
                    } label: {
                        Label("Quit", systemImage: "xmark.circle")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    private func messageCard(text: String, color: Color, icon: String) -> some View {
        GlassCard {
            Label {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
        }
    }
}
