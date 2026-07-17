import Foundation

enum PreviewFixtures {
    static let rooms: [Room] = [
        room("living", "Living Room", "sofa", [
            device("lv_bulb", "Bulb", .light, "living", "Living Room", false),
            device("lv_fan", "Fan", .fan, "living", "Living Room", true),
            device("lv_socket", "Socket", .switch, "living", "Living Room", false),
            device("lv_tube", "Tubelight", .light, "living", "Living Room", true),
        ]),
        room("kitchen", "Kitchen", "fork.knife", [
            device("kt_bulb_l", "Left Bulb", .light, "kitchen", "Kitchen", false),
            device("kt_bulb_r", "Right Bulb", .light, "kitchen", "Kitchen", false),
        ]),
        room("gaming", "Gaming Room", "gamecontroller", [
            device("gm_tube1", "Tubelight 1", .light, "gaming", "Gaming Room", true),
            device("gm_socket", "Socket", .switch, "gaming", "Gaming Room", false),
            device("gm_fan", "Fan", .fan, "gaming", "Gaming Room", false),
            device("gm_bulb", "Bulb", .light, "gaming", "Gaming Room", false),
            device("gm_tube2", "Tubelight 2", .light, "gaming", "Gaming Room", false),
        ]),
        room("bedroom", "Bedroom", "bed.double", [
            device("bd_tube1", "Tubelight 1", .light, "bedroom", "Bedroom", true),
            device("bd_aircon", "Aircon Socket", .switch, "bedroom", "Bedroom", false),
            device("bd_bulb", "Bulb", .light, "bedroom", "Bedroom", false),
            device("bd_fan", "Fan", .fan, "bedroom", "Bedroom", false),
            device("bd_socket", "Socket", .switch, "bedroom", "Bedroom", false),
            device("bd_tube2", "Tubelight 2", .light, "bedroom", "Bedroom", false),
        ]),
        room("bathroom", "Bathroom", "drop", [
            device("bt_geyser", "Geyser", .switch, "bathroom", "Bathroom", false),
        ]),
        room("dining", "Dining Room", "fork.knife.circle", [
            device("dn_tube", "Tubelight", .light, "dining", "Dining Room", false),
            device("dn_bulb", "Bulb", .light, "dining", "Dining Room", false),
        ]),
    ]

    static let health = HealthDashboardResponse(
        rangeDays: 1,
        current: DailyHealthSummary(
            localDate: "2026-07-17",
            latestHeartRate: metric(62, "bpm"),
            averageHRV: metric(58, "ms"),
            skinTemperature: metric(36.6, "°C"),
            restingHeartRate: metric(55, "bpm"),
            spo2: metric(98, "%"),
            vo2Max: metric(44, "mL/kg/min"),
            recovery: HealthRecoverySummary(
                score: metric(82, "score"),
                averageSleepHRV: metric(58, "ms"),
                sleepRestingHR: metric(55, "bpm"),
                temperatureDeviation: metric(0.1, "°C"),
                heartRateDrop: metric(16, "bpm"),
                restorativeSleep: metric(74, "%")
            ),
            activity: HealthActivitySummary(
                steps: metric(8_432, "steps"),
                activeMinutes: metric(46, "min"),
                movementIndex: metric(72, "score")
            ),
            sleep: HealthSleepSummary(
                score: metric(86, "score"),
                totalSleepSeconds: 25_920,
                timeInBedSeconds: 28_800,
                efficiency: metric(90, "%"),
                bedtimeStart: nil,
                bedtimeEnd: nil,
                stages: [
                    HealthSleepStage(stage: "rem", seconds: 5_640, percentage: 20),
                    HealthSleepStage(stage: "deep", seconds: 4_320, percentage: 16),
                    HealthSleepStage(stage: "light", seconds: 15_960, percentage: 56),
                    HealthSleepStage(stage: "awake", seconds: 2_880, percentage: 8),
                ],
                fullSleepCycles: 4,
                tossesAndTurns: 12,
                restorativeSleep: metric(74, "%"),
                morningAlertnessMinutes: 22
            ),
            series: [
                "glucose": samples(metric: "glucose", unit: "mg/dL", values: [88, 91, 89, 94, 96, 93, 97, 94]),
                "motion": samples(metric: "motion", unit: "intensity", values: [18, 22, 28, 25, 45, 38, 52, 48, 62, 55]),
            ],
            rejectedSamples: 0
        ),
        daily: [],
        sync: HealthSyncMetadata(
            configured: true,
            connected: true,
            provider: "ultrahuman",
            sourceAPI: "personal",
            timezone: "Asia/Kolkata",
            lastSuccessfulSyncAt: "2026-07-17T07:12:00+05:30",
            latestSourceAt: "2026-07-17T07:10:00+05:30",
            cached: false,
            stale: false,
            partial: false,
            errorCode: nil,
            message: nil
        )
    )

    private static func room(_ id: String, _ name: String, _ icon: String, _ devices: [Device]) -> Room {
        Room(id: id, name: name, icon: icon, devices: devices)
    }

    private static func device(
        _ id: String,
        _ name: String,
        _ type: DeviceType,
        _ roomID: String,
        _ roomName: String,
        _ isOn: Bool
    ) -> Device {
        Device(
            id: id,
            name: name,
            type: type,
            entityID: "\(type.rawValue).\(id)",
            roomID: roomID,
            roomName: roomName,
            capabilities: [.toggle],
            state: DeviceState(
                state: isOn ? "on" : "off",
                isOn: isOn,
                brightness: nil,
                percentage: nil,
                colorTempKelvin: nil,
                rgbColor: nil
            )
        )
    }

    private static func metric(_ value: Double, _ unit: String) -> HealthMetricValue {
        HealthMetricValue(value: value, unit: unit, timestamp: nil, changeFromPrevious: nil)
    }

    private static func samples(metric: String, unit: String, values: [Double]) -> [HealthSample] {
        values.enumerated().map { index, value in
            HealthSample(
                timestamp: 1_752_736_000 + index * 3_600,
                localTime: "2026-07-17T\(String(format: "%02d", index + 8)):00:00+05:30",
                localDate: "2026-07-17",
                value: value,
                unit: unit,
                metric: metric
            )
        }
    }
}
