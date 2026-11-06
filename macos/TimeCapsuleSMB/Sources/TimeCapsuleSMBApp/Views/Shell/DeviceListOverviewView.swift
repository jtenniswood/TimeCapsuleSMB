import AppKit
import SwiftUI

/// The everyday view is a small collection of devices, like AirPort Utility.
/// Configuration and diagnostics are reached deliberately from each device.
struct DeviceListOverviewView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var deviceRegistry: DeviceRegistryStore
    @ObservedObject var deviceDiscovery: DeviceDiscoveryStore
    @ObservedObject var backend: BackendClient
    var dashboardStore: DashboardStore? = nil
    var addManually: (() -> Void)? = nil
    let canAddDevice: Bool
    let addDiscoveredDevice: (DiscoveredDevice) -> Void
    @State private var selectedDeviceID: DeviceProfile.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                otherDevicesMenu
                Spacer()
                if deviceDiscovery.nearbyState == .discovering {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(20)

            if deviceRegistry.profiles.isEmpty {
                welcome
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 8) {
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(.secondary)
                            Text(L10n.string("simple.this_mac"))
                                .foregroundStyle(.secondary)
                        }
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 2, height: 44)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 36)], spacing: 32) {
                            ForEach(deviceRegistry.profiles) { profile in
                                deviceButton(profile)
                            }
                        }
                        .frame(maxWidth: max(280, CGFloat(deviceRegistry.profiles.count) * 280))
                        Text(L10n.string("simple.select_device"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 18)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity)
                }
            }
            discoveryNotice
        }
        .background(LinearGradient(
            colors: [Color(nsColor: .controlBackgroundColor).opacity(0.4), Color(nsColor: .windowBackgroundColor)],
            startPoint: .top, endPoint: .bottom
        ))
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            AirPortDeviceIcon().frame(width: 96, height: 120)
            Text(L10n.string("simple.welcome.title"))
                .font(.title2.weight(.semibold))
            Text(L10n.string("simple.welcome.message"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button(L10n.string("simple.add_device")) { appStore.showAddDevice() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private func deviceButton(_ profile: DeviceProfile) -> some View {
        let summary = appStore.dashboardSummary(for: profile)
        return Button {
            selectedDeviceID = profile.id
        } label: {
            VStack(spacing: 14) {
                AirPortDeviceIcon(isTower: profile.deviceGeneration == "gen5" || profile.model?.contains("8,") == true)
                    .frame(width: 100, height: 120)
                HStack(spacing: 7) {
                    DeviceStatusLight(status: summary.displayStatus)
                    Text(profile.title).font(.headline).multilineTextAlignment(.center)
                }
                Text(summary.displayStatus.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.title + ", " + summary.displayStatus.title)
        .help(L10n.string("simple.select_device"))
        .popover(isPresented: Binding(
            get: { selectedDeviceID == profile.id },
            set: { if !$0 { selectedDeviceID = nil } }
        ), arrowEdge: .trailing) {
            DeviceQuickInfoView(profile: profile, summary: summary, openDisk: {
                dashboardStore?.session(for: profile).performSecondaryAction(.openFinder, profile: profile)
            }, edit: {
                selectedDeviceID = nil
                appStore.select(profile)
            })
            .task { await dashboardStore?.session(for: profile).refreshDeviceStatus(profile: profile) }
        }
    }

    private var otherDevicesMenu: some View {
        Menu {
            NearbyAirPortMenuItems(
                devices: deviceDiscovery.nearbyUnsavedDevices,
                canAddDevice: canAddDevice,
                isRefreshing: backend.isRunning,
                add: addDiscoveredDevice,
                addManually: { if let addManually { addManually() } else { appStore.showAddDevice() } },
                refresh: { deviceDiscovery.refresh() }
            )
        } label: {
            Text(L10n.string("simple.other_devices"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var discoveryNotice: some View {
        if let error = deviceDiscovery.error, deviceDiscovery.nearbyState == .failed {
            ErrorRecoveryView(error: error) { kind in
                guard kind == .openSystemSettings, let url = LocalNetworkRecovery.settingsURL else { return nil }
                return { NSWorkspace.shared.open(url) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        } else if let warning = deviceDiscovery.warning {
            Text(warning).font(.caption).foregroundStyle(.orange).padding(.horizontal, 24)
        }
    }
}

struct NearbyAirPortMenuItems: View {
    let devices: [DiscoveredDevice]
    let canAddDevice: Bool
    let isRefreshing: Bool
    let add: (DiscoveredDevice) -> Void
    let addManually: () -> Void
    let refresh: () -> Void

    var body: some View {
        ForEach(devices) { device in
            Button(device.displayName) { add(device) }
                .disabled(!canAddDevice || device.isUnsupportedModel)
        }
        if devices.isEmpty { Text(L10n.string("overview.discovery.empty")) }
        Divider()
        Button(L10n.string("simple.add_by_address"), action: addManually).disabled(!canAddDevice)
        Button(L10n.string("overview.discovery.refresh"), action: refresh).disabled(isRefreshing)
    }
}

struct AirPortDeviceIcon: View {
    var isTower = true
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * (isTower ? 0.68 : 0.94)
            let height = geometry.size.height * (isTower ? 0.88 : 0.28)
            let capHeight = max(6, geometry.size.height * 0.09)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: width * 0.12)
                    .fill(LinearGradient(colors: [Color(white: 0.86), .white, Color(white: 0.94), Color(white: 0.78)], startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: width * 0.12).strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
                    .padding(.top, capHeight * 0.5)
                AirPortTopFace()
                    .fill(LinearGradient(colors: [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                    .frame(height: capHeight)
                Image(systemName: "apple.logo")
                    .font(.system(size: width * 0.13))
                    .foregroundStyle(Color(white: 0.22))
                    .scaleEffect(y: 0.55)
                    .offset(y: capHeight * 0.03)
                Circle().fill(Color(white: 0.45)).frame(width: max(1, width * 0.018), height: max(1, width * 0.018))
                    .offset(x: width * 0.33, y: height * 0.92)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.22), radius: 4, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct AirPortTopFace: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.12, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.88, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.75), control: CGPoint(x: rect.width * 0.96, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.94, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.height * 0.75), control: CGPoint(x: 0, y: rect.height))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.12, y: 0), control: CGPoint(x: rect.width * 0.04, y: 0))
            path.closeSubpath()
        }
    }
}

struct DeviceStatusLight: View {
    let status: DeviceDisplayStatus
    private var color: Color {
        switch status {
        case .healthy: return .green
        case .warning, .activationNeeded: return .orange
        case .failed, .passwordInvalid, .keychainUnavailable, .unsupported: return .red
        case .installing, .checking, .maintaining: return .accentColor
        default: return .secondary
        }
    }
    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
    }
}

struct DeviceQuickInfoView: View {
    let profile: DeviceProfile
    let summary: DeviceDashboardSummary
    let openDisk: () -> Void
    let edit: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(profile.title).font(.headline).multilineTextAlignment(.center)
            HStack(spacing: 7) {
                DeviceStatusLight(status: summary.displayStatus)
                Text(summary.displayStatus.title).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text(L10n.string("simple.address")).foregroundStyle(.secondary)
                    Text(profile.connectionTarget).textSelection(.enabled)
                }
                if let model = profile.model {
                    GridRow {
                        Text(L10n.string("dashboard.overview.model")).foregroundStyle(.secondary)
                        Text(model)
                    }
                }
            }
            .font(.callout)
            HStack {
                Button(L10n.string("simple.open_disk"), action: openDisk)
                    .disabled(!DashboardActionPolicy.isEnabled(.openFinder, for: summary))
                Spacer()
                Button(L10n.string("simple.edit"), action: edit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
