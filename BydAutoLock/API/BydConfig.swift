import Foundation

struct BydConfig {
    var baseURL: String
    var countryCode: String
    var language: String
    var timeZone: String

    static func fromRegion(_ region: String) -> BydConfig {
        let r = region.uppercased().trimmingCharacters(in: .whitespaces)
        var baseURL: String
        var countryCode = r
        var language = "en"
        var timeZone = "UTC"

        switch r {
        case "KR":
            baseURL = "https://dilinkappoversea-kr-ali.byd.auto"
            language = "ko"; timeZone = "Asia/Seoul"
        case "EU":
            baseURL = "https://dilinkappoversea-eu.byd.auto"
            countryCode = "GB"; language = "en"; timeZone = "Europe/London"
        case "JP":
            baseURL = "https://dilinkappoversea-jp.byd.auto"
            language = "ja"; timeZone = "Asia/Tokyo"
        case "SG":
            baseURL = "https://dilinkappoversea-sg.byd.auto"
            language = "en"; timeZone = "Asia/Singapore"
        case "AU":
            baseURL = "https://dilinkappoversea-au.byd.auto"
            language = "en"; timeZone = "Australia/Sydney"
        case "BR":
            baseURL = "https://dilinkappoversea-br.byd.auto"
            language = "pt"; timeZone = "America/Sao_Paulo"
        case "MX":
            baseURL = "https://dilinkappoversea-mx.byd.auto"
            language = "es"; timeZone = "America/Mexico_City"
        case "NO":
            baseURL = "https://dilinkappoversea-no.byd.auto"
            language = "no"; timeZone = "Europe/Oslo"
        case "UZ":
            baseURL = "https://dilinkappoversea-uz.byd.auto"
            language = "en"; timeZone = "Asia/Tashkent"
        case "KZ":
            baseURL = "https://dilinkappoversea-kz.byd.auto"
            language = "en"; timeZone = "Asia/Almaty"
        case "IN":
            baseURL = "https://dilinkappoversea-in.byd.auto"
            language = "en"; timeZone = "Asia/Kolkata"
        case "ID":
            baseURL = "https://dilinkappoversea-id.byd.auto"
            language = "in"; timeZone = "Asia/Jakarta"
        case "VN":
            baseURL = "https://dilinkappoversea-vn.byd.auto"
            language = "vi"; timeZone = "Asia/Ho_Chi_Minh"
        case "SA":
            baseURL = "https://dilinkappoversea-sa.byd.auto"
            language = "ar"; timeZone = "Asia/Riyadh"
        case "OM":
            baseURL = "https://dilinkappoversea-om.byd.auto"
            language = "ar"; timeZone = "Asia/Muscat"
        default:
            baseURL = "https://dilinkappoversea-\(r.lowercased()).byd.auto"
        }

        return BydConfig(baseURL: baseURL, countryCode: countryCode, language: language, timeZone: timeZone)
    }
}
