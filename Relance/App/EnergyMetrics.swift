import Foundation
import MetricKit

/// Audit de batterie (plan P9-E) : rapports quotidiens de MetricKit et réveils de l'app, gardés dans
/// l'App Group et affichés dans Réglages › Diagnostic batterie. Rien n'est envoyé sur le réseau.
nonisolated final class EnergyMetrics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = EnergyMetrics()

    /// Ce qui réveille l'app en arrière-plan.
    enum Wake: String, CaseIterable {
        case push = "Push de la vigie"
        case zone = "Entrée dans une zone"
        case visite = "Arrêt relevé (trajets)"
    }

    /// Résumé d'un rapport MetricKit (en général 24 h).
    struct Report: Codable, Hashable {
        var begin: Date
        var end: Date
        var foregroundSeconds: Double
        var backgroundSeconds: Double
        var backgroundLocationSeconds: Double
        var cpuSeconds: Double
        /// Temps où la position était demandée, toutes précisions confondues.
        var locationSeconds: Double
        var wifiMegabytes: Double
        var cellularMegabytes: Double
    }

    private static let maxReports = 60
    private static let maxWakeDays = 30
    private static let wakesKey = "energyWakes"

    func start() {
        MXMetricManager.shared.add(self)
        // Rapports livrés pendant que l'app n'était pas lancée.
        Self.save(MXMetricManager.shared.pastPayloads)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        Self.save(payloads)
    }

    // MARK: - Rapports

    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("Metrics", isDirectory: true)
    }

    private static func save(_ payloads: [MXMetricPayload]) {
        guard let folder, !payloads.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for payload in payloads {
            let name = "metrics-\(Int(payload.timeStampEnd.timeIntervalSince1970)).json"
            try? payload.jsonRepresentation().write(to: folder.appendingPathComponent(name))
        }
        let files = rawFiles()
        for old in files.dropFirst(maxReports) { try? FileManager.default.removeItem(at: old) }
        storeSummaries(payloads)
    }

    /// Rapports bruts, du plus récent au plus ancien.
    static func rawFiles() -> [URL] {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static var summariesFile: URL? { folder?.appendingPathComponent("resumes.plist") }

    static func reports() -> [Report] {
        guard let file = summariesFile, let data = try? Data(contentsOf: file) else { return [] }
        return (try? PropertyListDecoder().decode([Report].self, from: data)) ?? []
    }

    private static func storeSummaries(_ payloads: [MXMetricPayload]) {
        guard let file = summariesFile else { return }
        var all = reports()
        for payload in payloads {
            let report = Report(payload)
            all.removeAll { $0.end == report.end }
            all.append(report)
        }
        all.sort { $0.end > $1.end }
        if let data = try? PropertyListEncoder().encode(Array(all.prefix(maxReports))) { try? data.write(to: file) }
    }

    // MARK: - Réveils

    static func count(_ wake: Wake, at date: Date = .now) {
        var days = wakes()
        let day = dayKey(date)
        days[day, default: [:]][wake.rawValue, default: 0] += 1
        let kept = days.keys.sorted().suffix(maxWakeDays)
        days = days.filter { kept.contains($0.key) }
        AppGroup.defaults.set(days, forKey: wakesKey)
    }

    /// Réveils par jour (« 2026-10-16 ») puis par cause.
    static func wakes() -> [String: [String: Int]] {
        AppGroup.defaults.dictionary(forKey: wakesKey) as? [String: [String: Int]] ?? [:]
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Export

    /// Un seul fichier JSON : résumés, réveils et rapports bruts, à partager depuis l'écran de diagnostic.
    static func exportFile() -> URL? {
        let raw = rawFiles().compactMap { url -> Any? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let summaries = (try? encoder.encode(reports())).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? []
        let export: [String: Any] = [
            "version": AppVersion.text,
            "exporte": ISO8601DateFormatter().string(from: .now),
            "resumes": summaries,
            "reveils": wakes(),
            "bruts": raw,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiguillage-batterie-\(dayKey(.now)).json")
        return (try? data.write(to: url)) == nil ? nil : url
    }
}

nonisolated private extension EnergyMetrics.Report {
    init(_ payload: MXMetricPayload) {
        func seconds(_ value: Measurement<UnitDuration>?) -> Double { value?.converted(to: .seconds).value ?? 0 }
        func megabytes(_ values: Measurement<UnitInformationStorage>?...) -> Double {
            values.reduce(0) { $0 + ($1?.converted(to: .megabytes).value ?? 0) }
        }
        let time = payload.applicationTimeMetrics
        let location = payload.locationActivityMetrics
        let network = payload.networkTransferMetrics
        self.init(
            begin: payload.timeStampBegin, end: payload.timeStampEnd,
            foregroundSeconds: seconds(time?.cumulativeForegroundTime),
            backgroundSeconds: seconds(time?.cumulativeBackgroundTime),
            backgroundLocationSeconds: seconds(time?.cumulativeBackgroundLocationTime),
            cpuSeconds: seconds(payload.cpuMetrics?.cumulativeCPUTime),
            locationSeconds: [location?.cumulativeBestAccuracyForNavigationTime, location?.cumulativeBestAccuracyTime,
                              location?.cumulativeNearestTenMetersAccuracyTime, location?.cumulativeHundredMetersAccuracyTime,
                              location?.cumulativeKilometerAccuracyTime, location?.cumulativeThreeKilometersAccuracyTime]
                .reduce(0) { $0 + seconds($1) },
            wifiMegabytes: megabytes(network?.cumulativeWifiUpload, network?.cumulativeWifiDownload),
            cellularMegabytes: megabytes(network?.cumulativeCellularUpload, network?.cumulativeCellularDownload))
    }
}
