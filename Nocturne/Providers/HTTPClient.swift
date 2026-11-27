import Foundation

/// Единый HTTP-клиент для внешних API: таймауты, JSON-декодирование, ошибки.
struct HTTPClient {
    static let shared = HTTPClient()

    let session: URLSession

    init(session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    enum HTTPError: LocalizedError {
        case badStatus(Int, String?)
        case emptyBody

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let detail):
                return "HTTP \(code)" + (detail.map { ": \($0)" } ?? "")
            case .emptyBody:
                return "Пустой ответ сервера."
            }
        }
    }

    func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.badStatus(-1, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.prefix(300)
            throw HTTPError.badStatus(http.statusCode, detail.map(String.init))
        }
        return data
    }

    func getJSON<T: Decodable>(_ url: URL, as type: T.Type, headers: [String: String] = [:]) async throws -> T {
        let data = try await data(from: url, headers: headers)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.unavailable("Не удалось разобрать ответ \(url.host ?? ""): \(error.localizedDescription)")
        }
    }

    func post<T: Decodable>(_ url: URL, body: Data,
                            headers: [String: String] = [:], as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let detail = String(data: data, encoding: .utf8)?.prefix(300)
            throw HTTPError.badStatus(status, detail.map(String.init))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
