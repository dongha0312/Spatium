import Foundation

/// 소셜 로그인에서 받은 ID 토큰(JWT)의 페이로드에서 이메일/사용자ID를 꺼내기 위한
/// 최소한의 디코더. 서명 검증은 서버 책임이므로 여기서는 클레임만 읽습니다.
enum JWTClaims {
    static func decodePayload(from token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func email(from token: String) -> String? {
        decodePayload(from: token)?["email"] as? String
    }

    static func subject(from token: String) -> String? {
        decodePayload(from: token)?["sub"] as? String
    }
}
