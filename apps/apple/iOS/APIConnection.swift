import Foundation
import Observation
import REPickShared

@Observable @MainActor
final class APIConnection {
    private(set) var isLoading = false
    private(set) var status = String(localized: "서버 주소를 입력하면 연결을 확인할 수 있어요.")

    func check(baseURL: String) async {
        guard !isLoading else { return }
        guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else {
            status = String(localized: "올바른 HTTPS 서버 주소를 입력해 주세요.")
            return
        }
        var allowed = base.scheme == "https"
        #if DEBUG
        allowed = allowed || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(base.host ?? ""))
        #endif
        guard allowed else {
            status = String(localized: "올바른 HTTPS 서버 주소를 입력해 주세요.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: base.appending(path: "api/v1/status"))
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                status = String(localized: "서버가 준비되지 않았어요. 잠시 후 다시 시도해 주세요.")
                return
            }
            let result = try JSONDecoder().decode(APIStatus.self, from: data)
            guard result.status == "ok", result.service == "RE:PICK", result.date != nil else {
                status = String(localized: "서버 응답 형식이 맞지 않아요.")
                return
            }
            status = String(localized: "RE:PICK 서버와 연결됐어요.")
        } catch is CancellationError {
            status = String(localized: "연결 확인을 취소했어요.")
        } catch {
            status = String(localized: "서버에 연결하지 못했어요. 주소와 네트워크를 확인해 주세요.")
        }
    }
}

