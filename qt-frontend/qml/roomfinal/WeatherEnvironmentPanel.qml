import QtQuick

GlassPanel {
    id: root

    property var environment: ({})
    property string weatherLatitude: "12.9716"
    property string weatherLongitude: "77.5946"
    property string weatherLocationName: "Bengaluru, India"
    property string temperature: ""
    property string humidity: ""
    property string aqi: ""
    property string condition: ""
    property string lastWeatherKey: ""

    width: 184
    height: 132
    radius: theme.radiusXl - 2
    padding: theme.space6

    Component.onCompleted: loadConfiguredWeather()
    onWeatherLatitudeChanged: loadConfiguredWeather()
    onWeatherLongitudeChanged: loadConfiguredWeather()

    function hasHaData() {
        return !!(environment.temperature || environment.humidity || environment.aqi || environment.condition)
    }

    function loadConfiguredWeather() {
        var key = weatherLatitude + "," + weatherLongitude
        if (lastWeatherKey === key)
            return
        lastWeatherKey = key
        loadWeather(weatherLatitude, weatherLongitude)
    }

    function loadWeather(lat, lon) {
        var weather = new XMLHttpRequest()
        weather.onreadystatechange = function() {
            if (weather.readyState !== XMLHttpRequest.DONE)
                return
            try {
                var data = JSON.parse(weather.responseText || "{}")
                var current = data.current || {}
                temperature = current.temperature_2m !== undefined ? Math.round(current.temperature_2m) + "°C" : ""
                humidity = current.relative_humidity_2m !== undefined ? Math.round(current.relative_humidity_2m) + "%" : ""
                condition = conditionFromCode(current.weather_code, current.is_day)
            } catch (e) {}
        }
        weather.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&current=temperature_2m,relative_humidity_2m,weather_code,is_day")
        weather.send()

        var air = new XMLHttpRequest()
        air.onreadystatechange = function() {
            if (air.readyState !== XMLHttpRequest.DONE)
                return
            try {
                var data = JSON.parse(air.responseText || "{}")
                var current = data.current || {}
                aqi = current.us_aqi !== undefined ? "AQI " + Math.round(current.us_aqi) : ""
            } catch (e) {}
        }
        air.open("GET", "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon) + "&current=us_aqi")
        air.send()
    }

    function conditionFromCode(code, isDay) {
        if (code === undefined || code === null)
            return ""
        if (code >= 95)
            return "Storm"
        if (code >= 51)
            return "Rain"
        if (code >= 1 && code <= 48)
            return "Clouds"
        return isDay === 0 ? "Night" : "Clear"
    }

    function weatherIcon() {
        var value = String(condition).toLowerCase()
        if (value.indexOf("storm") !== -1 || value.indexOf("thunder") !== -1)
            return "cloud-lightning"
        if (value.indexOf("rain") !== -1 || value.indexOf("drizzle") !== -1)
            return "cloud-rain"
        if (value.indexOf("cloud") !== -1 || value.indexOf("overcast") !== -1)
            return "cloud"
        if (value.indexOf("night") !== -1 || value.indexOf("moon") !== -1)
            return "moon"
        return "sun"
    }

    Row {
        x: 0
        y: 0
        spacing: theme.space4
        SvgIcon {
            width: 18
            height: 18
            name: root.weatherIcon()
            iconColor: theme.iconColor
            darkMode: theme.darkMode
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: condition || "Weather"
            color: theme.textPrimary
            font.family: theme.family()
            font.pixelSize: theme.bodyMd
            font.bold: true
            width: 120
            elide: Text.ElideRight
        }
    }

    Row {
        x: 0
        y: 34
        width: parent.width
        spacing: theme.space3
        clip: true
        Repeater {
            model: [
                { icon: "thermometer", label: "Temp", value: root.temperature || "--", color: theme.accentCyan },
                { icon: "droplets", label: "Hum", value: root.humidity || "--", color: theme.accentBlue },
                { icon: "wind", label: "AQI", value: root.aqi || "--", color: theme.accentGreen }
            ]
            Column {
                width: (parent.width - parent.spacing * 2) / 3
                SvgIcon {
                    width: 16
                    height: 16
                    name: modelData.icon
                    iconColor: theme.iconColor
                    darkMode: theme.darkMode
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    width: parent.width
                    text: modelData.value
                    color: modelData.color
                    font.family: theme.family()
                    font.pixelSize: theme.bodyMd
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: modelData.label
                    color: theme.textMuted
                    font.family: theme.family()
                    font.pixelSize: theme.caption
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Text {
        x: 0
        y: 106
        width: parent.width
        text: root.weatherLocationName
        color: theme.textMuted
        font.family: theme.family()
        font.pixelSize: theme.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
}
