import Foundation
import REPickShared

struct ReportEndpoint: Sendable {
    let baseURL: URL
    let identity: String

    init(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ReportClientError.setupRequired }
        guard let canonical = try? ReportOrigin.canonical(value), let url = URL(string: canonical) else {
            throw ReportClientError.invalidAddress
        }
        baseURL = url
        identity = canonical
    }

    func url(_ path: String) -> URL { baseURL.appending(path: path) }

    func permitsRedirect(to url: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return baseURL.scheme?.lowercased() == url.scheme?.lowercased()
            && baseURL.host?.lowercased() == url.host?.lowercased() && port(baseURL) == port(url)
            && url.user == nil && url.password == nil
    }
}

private final class ReportRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let endpoint: ReportEndpoint
    init(endpoint: ReportEndpoint) { self.endpoint = endpoint }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(endpoint.permitsRedirect(to:)) == true ? request : nil)
    }
}

actor HealthReportClient {
    nonisolated let endpoint: ReportEndpoint
    private let credentials = ReportCredentials()
    private let session: URLSession
    private var enrollment: Task<ReportCredential, Error>?

    init(baseURL: String) throws {
        endpoint = try ReportEndpoint(baseURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 70
        configuration.timeoutIntervalForResource = 75
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: ReportRedirectDelegate(endpoint: endpoint), delegateQueue: nil)
    }

    func existingCredential() throws -> ReportCredential? { try credentials.read(origin: endpoint.identity) }

    func analyzeFoodPhoto(_ request: FoodPhotoAnalysisRequest) async throws -> FoodPhotoAnalysis {
        try Task.checkCancellation()
        try request.validate()
        let body = try HealthReportCoding.encoder().encode(request)
        guard body.count <= 2_900_000 else { throw FoodPhotoClientError.requestTooLarge }
        do {
            let result: FoodPhotoAnalysisResponse = try await send(path: "api/v1/food-analyses", method: "POST",
                                                                  body: body, authenticated: true)
            try result.validate()
            return result.data
        } catch let error as ReportClientError {
            throw FoodPhotoClientError.connection(error)
        } catch is ReportCredentialError {
            throw FoodPhotoClientError.credentials
        } catch is DecodingError {
            throw FoodPhotoClientError.credentials
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw FoodPhotoClientError.network
        }
    }

    func create(_ request: HealthReportRequest, idempotencyKey: UUID) async throws -> HealthReportResource {
        guard request.hasRecords else { throw ReportClientError.noRecords }
        let body = try HealthReportCoding.encoder().encode(request)
        guard body.count <= 262_144 else { throw HealthReportError.requestTooLarge }
        let result: HealthReportResponse = try await send(path: "api/v1/health-reports", method: "POST", body: body,
                                                        idempotencyKey: idempotencyKey, authenticated: true)
        try result.data.validate()
        guard result.data.period == request.period, result.data.timeZone == request.timeZone else {
            throw ReportClientError.invalidResponse
        }
        return result.data
    }

    func fetch(id: UUID) async throws -> HealthReportResource {
        let result: HealthReportResponse = try await send(path: "api/v1/health-reports/\(id.uuidString)", authenticated: true)
        try result.data.validate()
        guard result.data.id == id else { throw ReportClientError.invalidResponse }
        return result.data
    }

    func list(period: HealthReportPeriod? = nil, cursor: String? = nil) async throws -> HealthReportListResponse {
        var query = [URLQueryItem(name: "limit", value: "20")]
        if let period { query.append(URLQueryItem(name: "period", value: period.rawValue)) }
        if let cursor {
            guard cursor.count <= 1_024 else { throw ReportClientError.invalidResponse }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let result: HealthReportListResponse = try await send(path: "api/v1/health-reports", query: query, authenticated: true)
        guard result.data.count <= 20, result.meta.nextCursor.map({ $0.count <= 1_024 }) ?? true else {
            throw ReportClientError.invalidResponse
        }
        try result.validate()
        return result
    }

    private func credential() async throws -> ReportCredential {
        if let existing = try credentials.read(origin: endpoint.identity) { return existing }
        let task: Task<ReportCredential, Error>
        if let enrollment { task = enrollment }
        else {
            task = Task { try await self.enroll() }
            enrollment = task
        }
        defer { enrollment = nil }
        let issued = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        // Another window may have registered while this request was in flight.
        if let existing = try credentials.read(origin: endpoint.identity) { return existing }
        do { try credentials.save(issued, origin: endpoint.identity) }
        catch {
            if let existing = try credentials.read(origin: endpoint.identity) { return existing }
            throw error
        }
        return issued
    }

    private func enroll() async throws -> ReportCredential {
        struct Envelope: Decodable, Sendable { let data: ReportCredential }
        let response: Envelope = try await send(path: "api/v1/report-installations", method: "POST",
                                               body: Data("{}".utf8), authenticated: false)
        try response.data.validate()
        return response.data
    }

    private func send<Response: Decodable & Sendable>(path: String, method: String = "GET", body: Data? = nil,
                                                     query: [URLQueryItem] = [], idempotencyKey: UUID? = nil,
                                                     authenticated: Bool) async throws -> Response {
        try Task.checkCancellation()
        guard var components = URLComponents(url: endpoint.url(path), resolvingAgainstBaseURL: false) else {
            throw ReportClientError.invalidAddress
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw ReportClientError.invalidAddress }
        var request = URLRequest(url: url)
        request.timeoutInterval = path == "api/v1/report-installations" ? 12 : method == "POST" ? 70 : 15
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let idempotencyKey { request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        if authenticated {
            let credential = try await credential()
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        }
        try Task.checkCancellation()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                  response.url.map(endpoint.permitsRedirect(to:)) == true else { throw ReportClientError.invalidResponse }
            if let length = response.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), length > 524_288 {
                throw ReportClientError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 524_288 else { throw ReportClientError.invalidResponse }
                data.append(byte)
            }
            guard (200...299).contains(response.statusCode) else {
                throw ReportClientError.status(response.statusCode)
            }
            guard response.mimeType?.lowercased() == "application/json" else { throw ReportClientError.invalidResponse }
            return try HealthReportCoding.decoder().decode(Response.self, from: data)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ReportClientError.timedOut
        } catch is DecodingError {
            throw ReportClientError.invalidResponse
        }
    }
}

enum FoodPhotoClientError: Error, LocalizedError, Sendable {
    case requestTooLarge, credentials, network, connection(ReportClientError)

    var errorDescription: String? {
        switch self {
        case .requestTooLarge: String(localized: "사진 파일이 너무 커요. 다른 사진을 선택해 주세요.")
        case .credentials: String(localized: "이 기기의 음식 분석 연결 정보를 읽거나 저장하지 못했어요. 기존 정보는 유지됩니다.")
        case .network: String(localized: "음식 분석 서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.")
        case .connection(.setupRequired): String(localized: "음식 분석 서버에 아직 연결되지 않았어요.")
        case .connection(.invalidAddress): String(localized: "음식 분석 서버 주소를 확인해 주세요.")
        case .connection(.invalidResponse): String(localized: "음식 분석 결과를 읽지 못했어요. 다시 시도해 주세요.")
        case .connection(.timedOut), .connection(.status(504)):
            String(localized: "음식 사진 분석이 늦어지고 있어요. 잠시 후 다시 시도해 주세요.")
        case .connection(.status(401)), .connection(.status(403)):
            String(localized: "음식 분석 연결 정보를 확인할 수 없어요. 기존 연결 정보는 유지했습니다.")
        case .connection(.status(400)), .connection(.status(413)), .connection(.status(422)):
            String(localized: "음식 사진을 처리할 수 없어요. 다른 사진을 선택하거나 다시 촬영해 주세요.")
        case .connection(.status(429)): String(localized: "음식 분석 요청이 많아요. 잠시 후 다시 시도해 주세요.")
        case .connection(.status(503)): String(localized: "음식 사진 분석 서비스를 아직 사용할 수 없어요. 잠시 후 다시 시도해 주세요.")
        case .connection: String(localized: "음식 사진을 분석하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }
}

enum ReportClientError: Error, LocalizedError, Sendable {
    case setupRequired, invalidAddress, invalidResponse, noRecords, timedOut, processing, failed, status(Int)

    var errorDescription: String? {
        switch self {
        case .setupRequired: String(localized: "리포트 서버에 아직 연결되지 않았어요.")
        case .invalidAddress: String(localized: "리포트 서버 주소를 확인해 주세요.")
        case .invalidResponse: String(localized: "리포트 응답을 읽지 못했어요. 다시 시도해 주세요.")
        case .noRecords: String(localized: "선택한 기간에 보관된 기록이 없어요.")
        case .timedOut: String(localized: "응답이 늦어지고 있어요. 잠시 후 지난 리포트를 확인하거나 다시 시도해 주세요.")
        case .processing: String(localized: "리포트를 아직 작성 중이에요. 잠시 후 지난 리포트를 새로고침해 주세요.")
        case .failed: String(localized: "리포트를 완성하지 못했어요. 기록은 유지됩니다. 다시 시도해 주세요.")
        case .status(401), .status(403): String(localized: "리포트 연결 정보를 확인할 수 없어요. 기존 연결 정보는 유지했습니다.")
        case .status(404): String(localized: "리포트를 찾을 수 없어요.")
        case .status(409): String(localized: "리포트 요청이 변경됐어요. 화면을 다시 열고 시도해 주세요.")
        case .status(422), .status(400), .status(413): String(localized: "선택한 기간과 기록을 확인해 주세요.")
        case .status(429): String(localized: "리포트 요청이 많아요. 잠시 후 다시 시도해 주세요.")
        case .status: String(localized: "리포트 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }
}
