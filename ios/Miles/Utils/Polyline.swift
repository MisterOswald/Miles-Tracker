import CoreLocation
import Foundation

/// Google encoded polyline algorithm (precision 5). Matches the TypeScript
/// implementation in web/src/lib/polyline.ts.
enum Polyline {
    static func encode(coordinates: [CLLocationCoordinate2D]) -> String {
        var output = ""
        var prevLat = 0
        var prevLng = 0
        for coord in coordinates {
            let latE5 = Int((coord.latitude * 1e5).rounded())
            let lngE5 = Int((coord.longitude * 1e5).rounded())
            output += encodeValue(latE5 - prevLat)
            output += encodeValue(lngE5 - prevLng)
            prevLat = latE5
            prevLng = lngE5
        }
        return output
    }

    private static func encodeValue(_ value: Int) -> String {
        var v = value < 0 ? ~(value << 1) : value << 1
        var out = ""
        while v >= 0x20 {
            out.append(Character(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63))))
            v >>= 5
        }
        out.append(Character(UnicodeScalar(UInt8(v + 63))))
        return out
    }

    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lng = 0

        func decodeValue() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1f) << shift
                shift += 5
                if byte < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : result >> 1
                }
            }
            return nil
        }

        while index < bytes.count {
            guard let dLat = decodeValue(), let dLng = decodeValue() else { break }
            lat += dLat
            lng += dLng
            coords.append(
                CLLocationCoordinate2D(
                    latitude: Double(lat) / 1e5,
                    longitude: Double(lng) / 1e5
                )
            )
        }
        return coords
    }
}
