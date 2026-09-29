import SwiftUI

struct AuthSettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var username  = ""
    @State private var password  = ""
    @State private var pin       = ""
    @State private var region    = "KR"
    @State private var isLoading = false
    @State private var alertMsg  = ""
    @State private var showAlert = false
    @State private var showDemoConfirm = false

    private let storage = StorageManager.shared

    private let regions = ["KR", "EU", "JP", "SG", "AU", "BR", "MX", "NO", "UZ", "KZ", "IN", "ID", "VN", "SA", "OM"]

    var body: some View {
        NavigationView {
            Form {
                Section("BYD 계정") {
                    TextField("이메일 / 아이디", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("비밀번호", text: $password)
                        .textContentType(.password)
                }

                Section("차량 PIN") {
                    SecureField("PIN (원격 제어 비밀번호)", text: $pin)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                }

                Section("지역") {
                    Picker("지역 서버", selection: $region) {
                        ForEach(regions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("로그인 및 저장")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.accentColor)
                    .foregroundStyle(.white)
                    .disabled(isLoading || username.isEmpty || password.isEmpty)
                }

                if storage.hasCredentials {
                    Section {
                        Button(role: .destructive) {
                            storage.clearAuth()
                            storage.isDemoMode = false
                            AutoLockService.shared.stop()
                        } label: {
                            Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                if !storage.hasCredentials || storage.isDemoMode {
                    Section {
                        if storage.isDemoMode {
                            Button(role: .destructive) {
                                storage.isDemoMode = false
                                AutoLockService.shared.stop()
                            } label: {
                                Label("데모 모드 종료", systemImage: "xmark.circle")
                            }
                        } else {
                            Button {
                                showDemoConfirm = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("데모 모드로 체험", systemImage: "play.rectangle")
                                        .font(.headline)
                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.orange.opacity(0.85))
                            .foregroundStyle(.white)
                        }
                    } footer: {
                        if !storage.isDemoMode {
                            Text("BYD 계정 없이 앱의 주요 기능을 체험할 수 있습니다. 실제 차량에 연결되지 않습니다.")
                        }
                    }
                }
            }
            .navigationTitle("계정 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .alert("알림", isPresented: $showAlert) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(alertMsg)
            }
            .alert("데모 모드로 체험", isPresented: $showDemoConfirm) {
                Button("취소", role: .cancel) {}
                Button("체험 시작") {
                    AutoLockService.shared.stop()
                    storage.isDemoMode = true
                    dismiss()
                }
            } message: {
                Text("실제 차량에 연결되지 않는 체험 모드입니다. 자동 잠금/해제가 동작하지 않습니다.")
            }
            .onAppear(perform: loadSaved)
        }
    }

    private func loadSaved() {
        username = storage.username ?? ""
        password = storage.password ?? ""
        pin      = storage.pin      ?? ""
        region   = storage.region
    }

    private func login() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let config  = BydConfig.fromRegion(region)
            let service = try BydVehicleService(config: config)
            let uid     = try await service.login(username: username, password: password)

            let vins: [String]
            do {
                vins = try await service.fetchVehicleList()
            } catch {
                throw BydError.serverError("로그인은 성공했지만 차량 목록 조회에 실패했습니다: \(error.localizedDescription)", "vehicle-list")
            }
            // actor-isolated 프로퍼티를 MainActor.run 밖에서 미리 추출
            let signToken  = await service.signToken
            let encryToken = await service.encryToken

            await MainActor.run {
                storage.username       = username
                storage.password       = password
                storage.pin            = pin
                storage.region         = region
                storage.userId         = uid
                storage.signToken      = signToken
                storage.encryToken     = encryToken
                storage.vins           = vins.joined(separator: ",")
                storage.selectedVin    = vins.first
                storage.hasCredentials = true
                alertMsg = "로그인 성공! VIN: \(vins.first ?? "없음")"
                showAlert = true
            }
        } catch {
            await MainActor.run {
                alertMsg  = "로그인 실패: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
