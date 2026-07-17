import Foundation

struct HealthMetricValue: Codable, Equatable {
    let value: Double
    let unit: String
    let timestamp: String?
    let changeFromPrevious: Double?

    enum CodingKeys: String, CodingKey {
        case value, unit, timestamp
        case changeFromPrevious = "change_from_previous"
    }
}

struct HealthSample: Codable, Equatable, Identifiable {
    let timestamp: Int
    let localTime: String
    let localDate: String
    let value: Double
    let unit: String
    let metric: String

    var id: String { "\(metric)-\(timestamp)" }

    enum CodingKeys: String, CodingKey {
        case timestamp, value, unit, metric
        case localTime = "local_time"
        case localDate = "local_date"
    }
}

struct HealthSleepStage: Codable, Equatable, Identifiable {
    let stage: String
    let seconds: Int
    let percentage: Double

    var id: String { stage }
}

struct HealthSleepSummary: Codable, Equatable {
    let score: HealthMetricValue?
    let totalSleepSeconds: Int?
    let timeInBedSeconds: Int?
    let efficiency: HealthMetricValue?
    let bedtimeStart: String?
    let bedtimeEnd: String?
    let stages: [HealthSleepStage]
    let fullSleepCycles: Int?
    let tossesAndTurns: Int?
    let restorativeSleep: HealthMetricValue?
    let morningAlertnessMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case score, efficiency, stages
        case totalSleepSeconds = "total_sleep_seconds"
        case timeInBedSeconds = "time_in_bed_seconds"
        case bedtimeStart = "bedtime_start"
        case bedtimeEnd = "bedtime_end"
        case fullSleepCycles = "full_sleep_cycles"
        case tossesAndTurns = "tosses_and_turns"
        case restorativeSleep = "restorative_sleep"
        case morningAlertnessMinutes = "morning_alertness_minutes"
    }
}

struct HealthRecoverySummary: Codable, Equatable {
    let score: HealthMetricValue?
    let averageSleepHRV: HealthMetricValue?
    let sleepRestingHR: HealthMetricValue?
    let temperatureDeviation: HealthMetricValue?
    let heartRateDrop: HealthMetricValue?
    let restorativeSleep: HealthMetricValue?

    enum CodingKeys: String, CodingKey {
        case score
        case averageSleepHRV = "average_sleep_hrv"
        case sleepRestingHR = "sleep_resting_hr"
        case temperatureDeviation = "temperature_deviation"
        case heartRateDrop = "heart_rate_drop"
        case restorativeSleep = "restorative_sleep"
    }
}

struct HealthActivitySummary: Codable, Equatable {
    let steps: HealthMetricValue?
    let activeMinutes: HealthMetricValue?
    let movementIndex: HealthMetricValue?

    enum CodingKeys: String, CodingKey {
        case steps
        case activeMinutes = "active_minutes"
        case movementIndex = "movement_index"
    }
}

struct DailyHealthSummary: Codable, Equatable {
    let localDate: String
    let latestHeartRate: HealthMetricValue?
    let averageHRV: HealthMetricValue?
    let skinTemperature: HealthMetricValue?
    let restingHeartRate: HealthMetricValue?
    let spo2: HealthMetricValue?
    let vo2Max: HealthMetricValue?
    let recovery: HealthRecoverySummary
    let activity: HealthActivitySummary
    let sleep: HealthSleepSummary
    let series: [String: [HealthSample]]
    let rejectedSamples: Int

    enum CodingKeys: String, CodingKey {
        case recovery, activity, sleep, series
        case localDate = "local_date"
        case latestHeartRate = "latest_heart_rate"
        case averageHRV = "average_hrv"
        case skinTemperature = "skin_temperature"
        case restingHeartRate = "resting_heart_rate"
        case spo2
        case vo2Max = "vo2_max"
        case rejectedSamples = "rejected_samples"
    }

    var latestGlucose: HealthMetricValue? {
        guard let sample = series["glucose"]?.last else { return nil }
        return HealthMetricValue(value: sample.value, unit: sample.unit, timestamp: sample.localTime, changeFromPrevious: nil)
    }
}

struct HealthSyncMetadata: Codable, Equatable {
    let configured: Bool
    let connected: Bool
    let provider: String
    let sourceAPI: String?
    let timezone: String
    let lastSuccessfulSyncAt: String?
    let latestSourceAt: String?
    let cached: Bool
    let stale: Bool
    let partial: Bool
    let errorCode: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case configured, connected, provider, timezone, cached, stale, partial, message
        case sourceAPI = "source_api"
        case lastSuccessfulSyncAt = "last_successful_sync_at"
        case latestSourceAt = "latest_source_at"
        case errorCode = "error_code"
    }
}

struct HealthDashboardResponse: Codable, Equatable {
    let rangeDays: Int
    let current: DailyHealthSummary?
    let daily: [DailyHealthSummary]
    let sync: HealthSyncMetadata

    enum CodingKeys: String, CodingKey {
        case current, daily, sync
        case rangeDays = "range_days"
    }
}

extension HealthMetricValue {
    func formatted(maximumFractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... maximumFractionDigits)))
    }
}

extension Int {
    var healthDuration: String {
        let hours = self / 3_600
        let minutes = (self % 3_600) / 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }
}
