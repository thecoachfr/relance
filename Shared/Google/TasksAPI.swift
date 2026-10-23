import Foundation

nonisolated enum TasksAPIError: LocalizedError {
    case notSignedIn
    case missingScope
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Pas connecté à Google."
        case .missingScope: "L'accès à Google Tasks n'a pas été autorisé. Reconnecte-toi en cochant l'accès à tes tâches."
        case .http(let code, let message): "Google Tasks a répondu \(code) : \(message)"
        }
    }
}

/// Tâche telle que l'API Google Tasks la décrit.
nonisolated struct RemoteTask: Codable, Sendable {
    var id: String?
    var title: String?
    var notes: String?
    /// RFC 3339. Seule la date compte : Google ignore l'heure.
    var due: String?
    /// « needsAction » ou « completed ».
    var status: String?
    var completed: String?
    var updated: String?
    var deleted: Bool?
    var hidden: Bool?
}

nonisolated struct RemoteTaskList: Codable, Sendable {
    var id: String
    var title: String?
}

nonisolated private struct TaskListPage: Decodable {
    var items: [RemoteTaskList]?
}

nonisolated private struct TaskPage: Decodable {
    var items: [RemoteTask]?
    var nextPageToken: String?
}

/// Client REST de la liste par défaut (« Mes tâches »).
nonisolated struct TasksAPI: Sendable {
    var token: @Sendable () async throws -> String
    var list = "@default"
    private let base = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/")!

    /// Sans `updatedMin` : toutes les tâches à faire. Avec : tout ce qui a changé depuis, y compris cochées et supprimées.
    func fetch(updatedMin: Date?) async throws -> [RemoteTask] {
        var all: [RemoteTask] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "maxResults", value: "100")]
            if let updatedMin {
                query += [
                    URLQueryItem(name: "updatedMin", value: Self.timestamp(updatedMin)),
                    URLQueryItem(name: "showCompleted", value: "true"),
                    URLQueryItem(name: "showHidden", value: "true"),
                    URLQueryItem(name: "showDeleted", value: "true"),
                ]
            } else {
                query.append(URLQueryItem(name: "showCompleted", value: "false"))
            }
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }

            let page: TaskPage = try await send("GET", path: "tasks", query: query)
            all += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    /// `fields` : clés JSON de l'API ; `NSNull()` efface une valeur (ex. retirer la date).
    func insert(_ fields: [String: Any]) async throws -> RemoteTask {
        let data = try await request("POST", path: "tasks", body: JSONSerialization.data(withJSONObject: fields))
        return try JSONDecoder().decode(RemoteTask.self, from: data)
    }

    func patch(id: String, _ fields: [String: Any]) async throws -> RemoteTask {
        let data = try await request("PATCH", path: "tasks/\(id)", body: JSONSerialization.data(withJSONObject: fields))
        return try JSONDecoder().decode(RemoteTask.self, from: data)
    }

    func delete(id: String) async throws {
        _ = try await request("DELETE", path: "tasks/\(id)")
    }

    // MARK: - Listes

    /// Identifiant de la liste `title`, créée si elle n'existe pas.
    func listID(named title: String) async throws -> String {
        let lists = URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
        var all = lists
        all.append(queryItems: [URLQueryItem(name: "maxResults", value: "100")])
        let page = try JSONDecoder().decode(TaskListPage.self, from: await request(url: all, method: "GET"))
        if let found = page.items?.first(where: { $0.title == title }) { return found.id }
        let body = try JSONSerialization.data(withJSONObject: ["title": title])
        return try JSONDecoder().decode(RemoteTaskList.self, from: await request(url: lists, method: "POST", body: body)).id
    }

    // MARK: - Dates

    /// Google renvoie la date à minuit UTC : on la relit en UTC pour retrouver le bon jour.
    static func day(fromDue due: String?, calendar: Calendar = .current) -> Date? {
        guard let due, let date = parse(due) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = utc.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components)
    }

    static func due(fromDay day: Date?, calendar: Calendar = .current) -> String? {
        guard let day else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02dT00:00:00.000Z", c.year!, c.month!, c.day!)
    }

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // MARK: - Transport

    private func send<Response: Decodable>(_ method: String, path: String, query: [URLQueryItem]) async throws -> Response {
        try JSONDecoder().decode(Response.self, from: await request(method, path: path, query: query))
    }

    private func request(_ method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var url = base.appending(path: list).appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        return try await request(url: url, method: method, body: body)
    }

    private func request(url: URL, method: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Un ajout (POST) n'est pas rejouable : renvoyé après une réponse perdue, il créerait un doublon.
        let (data, response) = try await Reseau.envoyer(request, rejouable: method != "POST")
        let status = response?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TasksAPIError.http(status, String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
