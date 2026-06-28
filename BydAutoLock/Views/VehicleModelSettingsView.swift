import SwiftUI

struct VehicleModelSettingsView: View {

    @Environment(\.dismiss) private var dismiss
    private let storage = StorageManager.shared

    @State private var vehicleModel: String

    init() {
        _vehicleModel = State(initialValue: StorageManager.shared.vehicleModel)
    }

    var body: some View {
        Form {
            Section {
                Picker("차종", selection: $vehicleModel) {
                    Text("선택 안 함").tag("")
                    ForEach(StorageManager.vehicleModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("차종 선택")
            } footer: {
                Text("선택한 차종은 로그 파일명에 포함됩니다.")
            }
        }
        .navigationTitle("차량 정보")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("저장") {
                    storage.vehicleModel = vehicleModel
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear { vehicleModel = storage.vehicleModel }
    }
}
