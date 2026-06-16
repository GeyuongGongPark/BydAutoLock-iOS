import SwiftUI
import CoreBluetooth

struct BluetoothSettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = BLEScanner()
    private let storage = StorageManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let saved = storage.deviceName {
                    currentDeviceSection(saved)
                }

                List {
                    Section {
                        if scanner.isScanning {
                            HStack {
                                ProgressView()
                                Text("검색 중...").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("발견된 기기")
                    }

                    ForEach(scanner.discovered) { device in
                        Button {
                            storage.deviceMac  = device.id
                            storage.deviceName = device.name
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).foregroundStyle(.primary)
                                    Text(device.id).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if storage.deviceMac == device.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("블루투스 기기 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(scanner.isScanning ? "중지" : "검색") {
                        if scanner.isScanning { scanner.stop() }
                        else                  { scanner.start() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear  { scanner.start() }
            .onDisappear { scanner.stop() }
        }
    }

    private func currentDeviceSection(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("현재 선택된 기기")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "bluetooth").foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(name).fontWeight(.medium)
                    Text(storage.deviceMac ?? "").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

// MARK: - BLE Scanner

struct DiscoveredDevice: Identifiable {
    let id: String    // peripheral.identifier.uuidString (iOS에서 MAC 대체)
    let name: String
    let rssi: Int
}

@MainActor
final class BLEScanner: NSObject, ObservableObject {
    @Published var discovered = [DiscoveredDevice]()
    @Published var isScanning = false

    private var central: CBCentralManager?
    private var seenIDs = Set<String>()

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func stop() {
        central?.stopScan()
        isScanning = false
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
                self.isScanning = true
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard RSSI.intValue != 127 else { return }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "(이름 없음)"
        let id   = peripheral.identifier.uuidString

        Task { @MainActor in
            if !self.seenIDs.contains(id) {
                self.seenIDs.insert(id)
                self.discovered.append(DiscoveredDevice(id: id, name: name, rssi: RSSI.intValue))
                self.discovered.sort { $0.rssi > $1.rssi }
            } else if let idx = self.discovered.firstIndex(where: { $0.id == id }) {
                self.discovered[idx] = DiscoveredDevice(id: id, name: name, rssi: RSSI.intValue)
            }
        }
    }
}
