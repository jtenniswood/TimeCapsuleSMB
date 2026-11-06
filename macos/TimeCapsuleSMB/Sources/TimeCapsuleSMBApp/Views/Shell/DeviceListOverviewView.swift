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
    @Environment(\.colorScheme) private var colorScheme
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
                            if let image = NSImage(named: NSImage.computerName) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 144, height: 104)
                            } else {
                                Image(systemName: "laptopcomputer").font(.system(size: 72))
                            }
                            Text(L10n.string("simple.this_mac")).font(UtilityStyle.deviceName)
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
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity)
                }
            }
            discoveryNotice
        }
        .background(LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.18, green: 0.20, blue: 0.24), Color(red: 0.42, green: 0.45, blue: 0.49)]
                : [Color(red: 0.94, green: 0.95, blue: 0.96), Color(red: 0.81, green: 0.84, blue: 0.87)],
            startPoint: .top, endPoint: .bottom
        ))
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            AirPortDeviceIcon().frame(width: 96, height: 120)
            Text(L10n.string("simple.welcome.title"))
                .font(UtilityStyle.title)
            Button(L10n.string("simple.add_device")) { appStore.showAddDevice() }
                .keyboardShortcut(.defaultAction)
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
                AirPortDeviceIcon(isTower: profile.usesTowerArtwork)
                    .frame(width: 100, height: 120)
                HStack(spacing: 7) {
                    DeviceStatusLight(status: summary.displayStatus)
                    Text(profile.title).font(UtilityStyle.deviceName).multilineTextAlignment(.center)
                }
                Text(summary.displayStatus.title)
                    .font(UtilityStyle.body)
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
        .menuStyle(.borderedButton)
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
            Text(warning).font(UtilityStyle.secondary).foregroundStyle(.orange).padding(.horizontal, 24)
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
        Group {
            if let image = AirPortArtwork.image(isTower: isTower) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: isTower ? "airport.extreme.tower" : "airport.extreme")
                    .resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Use system-provided hardware artwork when available. It is never copied
/// into our distribution; systems without AirPort Utility use SF Symbols.
@MainActor
private enum AirPortArtwork {
    private static let bundle = Bundle(path: "/System/Applications/Utilities/AirPort Utility.app")
    private static let tower = load("AirPort-8-3D-cropped~mac")
    private static let flat = load("TimeCapsule-3D-cropped~mac")
    static func image(isTower: Bool) -> NSImage? { isTower ? tower : flat }
    private static func load(_ name: String) -> NSImage? {
        bundle?.url(forResource: name, withExtension: "tiff").flatMap { NSImage(contentsOf: $0) }
    }
}

extension DeviceProfile {
    var usesTowerArtwork: Bool { syap == "119" || syap == "120" || payloadFamily == "netbsd6_samba4" }
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.title).font(UtilityStyle.heading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    DeviceStatusLight(status: summary.displayStatus)
                    Text(summary.displayStatus.title).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Text(L10n.string("simple.address")).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(DeviceEndpointPolicy.hostComponent(profile.connectionTarget) ?? profile.displayTarget)
                    .textSelection(.enabled).monospacedDigit()
            }
            HStack(spacing: 8) {
                Button(L10n.string("simple.open_disk"), action: openDisk)
                    .disabled(!DashboardActionPolicy.isEnabled(.openFinder, for: summary))
                Spacer(minLength: 8)
                Button(L10n.string("simple.edit"), action: edit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(UtilityStyle.body).controlSize(.regular)
        .padding(20)
        .frame(width: 300)
    }
}
