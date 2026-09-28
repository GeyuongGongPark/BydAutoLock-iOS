import SwiftUI

struct CafeAuthView: View {
    let onSuccess: () -> Void

    @State private var nick = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successResult: CafeMemberResult?

    private let storage = StorageManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    // 헤더
                    VStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        Text("BYD 써드파티연구소 인증")
                            .font(.title2.bold())
                        Text("카페 정회원 이상만 사용할 수 있습니다")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 48)

                    // 입력
                    VStack(alignment: .leading, spacing: 8) {
                        Text("카페 닉네임")
                            .font(.subheadline.bold())
                        TextField("지역ll닉네임ll차종", text: $nick)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(isLoading || successResult != nil)
                        Text("예) 서울ll홍길동ll ATTO3  (구분자는 소문자 L 두 개)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // 에러 메시지
                    if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // 성공 시 등급 배지
                    if let result = successResult {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.green)
                            Text("인증 완료")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("등급: \(result.grade)")
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }

                    // 버튼
                    VStack(spacing: 12) {
                        if successResult != nil {
                            Button {
                                onSuccess()
                            } label: {
                                Label("입장하기", systemImage: "arrow.right.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.green)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        } else {
                            Button {
                                Task { await performCheck() }
                            } label: {
                                ZStack {
                                    if isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("인증하기")
                                            .font(.headline)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(nick.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isLoading || nick.trimmingCharacters(in: .whitespaces).isEmpty)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            // 기존 저장된 닉네임 있으면 미리 채움
            if let saved = storage.cafeNick {
                nick = saved
            }
        }
    }

    private func performCheck() async {
        let trimmed = nick.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        successResult = nil

        defer { isLoading = false }

        do {
            let result = try await CafeMemberService.shared.check(nick: trimmed)

            if !result.found {
                errorMessage = "닉네임을 찾을 수 없습니다"
                return
            }
            if !result.isRegularOrAbove {
                errorMessage = "정회원 이상만 사용 가능합니다 (현재: \(result.grade))"
                return
            }

            // 성공 — StorageManager에 저장
            storage.cafeNick = trimmed
            storage.cafeGrade = result.grade
            storage.cafeIsRegular = true
            storage.cafeCheckedAt = Date().timeIntervalSince1970

            successResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
