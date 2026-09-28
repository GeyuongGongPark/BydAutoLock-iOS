import Foundation

struct CafeMemberResult: Codable {
    let found: Bool
    let isRegularOrAbove: Bool
    let grade: String
    let checkedAt: Int64
}

struct CafeMemberService {
    static let shared = CafeMemberService()
    private static let apiKey = "byd_210388bcac24d65d3146de0f8dde377480f6f02a1783e609"
    private static let endpoint = "https://byd.cseini.co.kr/cafe/member"

    func check(nick: String) async throws -> CafeMemberResult {
        guard let encoded = nick.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.endpoint)?nick=\(encoded)") else {
            throw CafeError.invalidNick
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-Cafe-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 401:
                throw CafeError.unauthorized
            case 429:
                throw CafeError.rateLimited
            case 200:
                break
            default:
                throw CafeError.serverError(httpResponse.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(CafeMemberResult.self, from: data)
        } catch {
            throw CafeError.invalidResponse
        }
    }
}

enum CafeError: LocalizedError {
    case invalidNick
    case unauthorized
    case rateLimited
    case serverError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidNick:      return "닉네임 형식이 올바르지 않습니다"
        case .unauthorized:     return "인증 키 오류"
        case .rateLimited:      return "요청 한도 초과. 잠시 후 다시 시도하세요"
        case .serverError(let code): return "서버 오류 (\(code))"
        case .invalidResponse:  return "응답 형식 오류"
        }
    }
}
