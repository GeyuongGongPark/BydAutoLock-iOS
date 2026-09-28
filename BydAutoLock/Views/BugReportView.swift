import SwiftUI

struct BugReportView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var body_ = ""
    @State private var attachLog = true
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var showSuccess = false

    private let logManager = LogManager.shared
    private let storage = StorageManager.shared

    private static let reportURL = URL(string: "https://geyuonggongpark-production.up.railway.app/api/reports")!

    // StorageManager의 vehicleModel("ATTO 3" 등)을 report.html 옵션에 맞게 변환
    private var mappedCar: String {
        switch storage.vehicleModel {
        case "ATTO 3":   return "BYD Atto 3"
        case "SEAL":     return "BYD Seal"
        case "DOLPHIN":  return "BYD Dolphin"
        case "SEALION 7": return "BYD Sealion 7"
        default:         return "기타"
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("제목", text: $title)
                        .autocorrectionDisabled()
                } header: {
                    Text("제목 (필수)")
                }

                Section {
                    HStack {
                        Text("앱")
                        Spacer()
                        Text("BYD AutoLock").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("차종")
                        Spacer()
                        Text(mappedCar).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("플랫폼")
                        Spacer()
                        Text("iOS").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("자동 입력")
                }

                Section {
                    TextEditor(text: $body_)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if body_.isEmpty {
                                Text("증상, 재현 방법, 발생 상황 등을 적어주세요. (선택)")
                                    .foregroundStyle(.tertiary)
                                    .font(.body)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("본문")
                }

                Section {
                    Toggle("로그 파일 첨부 (최근 5000줄)", isOn: $attachLog)
                } header: {
                    Text("첨부")
                } footer: {
                    Text("로그에는 차량 VIN, 계정 정보가 포함되지 않습니다.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("제보하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button { submit() } label: {
                            Text("제출").bold()
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert("제보가 접수됐습니다", isPresented: $showSuccess) {
                Button("확인") { dismiss() }
            } message: {
                Text("소중한 의견 감사합니다.")
            }
        }
    }

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let payload = buildPayload(title: trimmedTitle)
                var req = URLRequest(url: Self.reportURL)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "제출에 실패했습니다. 네트워크 연결을 확인해주세요."
                }
            }
        }
    }

    private func buildPayload(title: String) -> [String: Any] {
        var payload: [String: Any] = [
            "title": title,
            "app": "BYD AutoLock",
            "platform": "iOS",
            "car": mappedCar,
            "body": body_.trimmingCharacters(in: .whitespaces),
        ]

        if attachLog {
            let logText = buildLogText()
            if let data = logText.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                let df = DateFormatter()
                df.dateFormat = "yyyyMMdd_HHmmss"
                let dateStr = df.string(from: Date())
                let modelPart = storage.vehicleModel.isEmpty ? "" : "_\(storage.vehicleModel.replacingOccurrences(of: " ", with: "_"))"
                payload["file_name"] = "byd_log_\(dateStr)\(modelPart).txt"
                payload["file_type"] = "text/plain"
                payload["file_data"] = "data:text/plain;base64,\(base64)"
            }
        }

        return payload
    }

    private func buildLogText() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let header = "BYD AutoLock v\(appVersion) (build \(buildNumber))\n---\n"
        let entries = logManager.fetchLogs(limit: 5000)
        let lines = entries.reversed()
            .map { "[\($0.formattedTime)] [\($0.tag)] \($0.message)" }
            .joined(separator: "\n")
        return header + lines
    }
}
