//
//  SpatiumTests.swift
//  SpatiumTests
//
//  Created by Dongha Ryu on 6/26/26.
//

import Testing
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import Spatium

@MainActor
struct SpatiumTests {

    @Test func spatiumProjectRoundTripsThroughJSON() throws {
        var project = SpatiumProject(id: "1", name: "우리집 인테리어")
        project.rooms = [
            RoomRecord(id: "10", roomType: "거실", itemCount: 8, photoCount: 4, uploadedAt: Date(), fileName: "room-scan.usdz", area: 19.6)
        ]

        let data = try JSONEncoder.spatiumAPI.encode(project)
        let decoded = try JSONDecoder.spatiumAPI.decode(SpatiumProject.self, from: data)

        #expect(decoded.id == "1")
        #expect(decoded.name == "우리집 인테리어")
        #expect(decoded.rooms.count == 1)
        #expect(decoded.rooms.first?.roomType == "거실")
        #expect(decoded.rooms.first?.area == 19.6)
    }

    @Test func resolvedNameFallsBackWhenBlank() {
        let project = SpatiumProject(id: "1", name: "   ")
        #expect(project.resolvedName == "이름 없는 프로젝트")
    }

    @Test func displayRoomCountUsesServerListCountBeforeRoomsLoad() {
        let project = SpatiumProject(id: "1", name: "우리집 인테리어", roomCount: 3)
        #expect(project.displayRoomCount == 3)
    }

    // MARK: - API 명세 계약: 요청 바디의 JSON 키가 문서와 정확히 일치해야 함

    @Test func loginRequestMatchesSpecKeys() throws {
        let request = LoginRequest(email: "a@b.com", password: "pw", keepLogin: true)
        let object = try encodeToDictionary(request)

        #expect(object["email"] as? String == "a@b.com")
        #expect(object["password"] as? String == "pw")
        #expect(object["keepLogin"] as? Bool == true)
    }

    @Test func signUpRequestMatchesSpecKeys() throws {
        let request = SignUpRequest(
            email: "a@b.com", nickname: "동하", password: "pw",
            birthDate: "2000-01-01", gender: .male,
            termsAgreed: true, privacyAgreed: true
        )
        let object = try encodeToDictionary(request)

        #expect(object["nickname"] as? String == "동하")
        #expect(object["birthDate"] as? String == "2000-01-01")
        #expect(object["gender"] as? Int == 0)
        #expect(object["termsAgreed"] as? Bool == true)
        #expect(object["privacyAgreed"] as? Bool == true)
    }

    /// 보안 개편 후 소셜 요청은 provider + idToken만 보낸다.
    /// (email/providerUserId는 서버가 idToken 검증으로 직접 얻는다)
    @Test func socialLoginRequestSendsOnlyProviderAndIdToken() throws {
        let apple = SocialLoginRequest(provider: .apple, idToken: "apple.jwt.token")
        let appleObject = try encodeToDictionary(apple)
        #expect(appleObject["provider"] as? String == "APPLE")
        #expect(appleObject["idToken"] as? String == "apple.jwt.token")
        #expect(appleObject["email"] == nil)
        #expect(appleObject["providerUserId"] == nil)

        let google = SocialLoginRequest(provider: .google, idToken: "google.jwt.token")
        let googleObject = try encodeToDictionary(google)
        #expect(googleObject["provider"] as? String == "GOOGLE")
        #expect(googleObject["idToken"] as? String == "google.jwt.token")
    }

    @Test func socialSignUpRequestMatchesSpecKeys() throws {
        let request = SocialSignUpRequest(
            provider: .google, idToken: "google.jwt.token",
            nickname: "김스파티", birthDate: "1998-06-07", gender: .male,
            termsAgreed: true, privacyAgreed: true
        )
        let object = try encodeToDictionary(request)

        #expect(object["provider"] as? String == "GOOGLE")
        #expect(object["idToken"] as? String == "google.jwt.token")
        #expect(object["email"] == nil)
        #expect(object["nickname"] as? String == "김스파티")
        #expect(object["birthDate"] as? String == "1998-06-07")
        #expect(object["gender"] as? Int == 0)
        #expect(object["termsAgreed"] as? Bool == true)
        #expect(object["privacyAgreed"] as? Bool == true)
    }

    /// "창문"이 door 키워드 "문"에 부분 매칭돼 문 모델로 렌더되던 회귀 방지.
    @Test func windowCategoryBeatsDoorSubstringMatch() {
        #expect(FurnitureCatalog.category(matching: "창문 창문")?.id == "window")
        #expect(FurnitureCatalog.category(matching: "문 1")?.id == "door")
        #expect(FurnitureCatalog.defaultModelName(matching: "창문") == "window")
    }

    @Test func jwtClaimsExtractEmailAndSubject() throws {
        // {"sub":"12345","email":"a@b.com"} — base64url payload를 가진 가짜 JWT
        let payload = #"{"sub":"12345","email":"a@b.com"}"#
        let base64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(base64).signature"

        #expect(JWTClaims.email(from: token) == "a@b.com")
        #expect(JWTClaims.subject(from: token) == "12345")
    }

    @Test func envelopeDecodesSpecShape() throws {
        let json = """
        {"statusCode": 201, "message": "룸이 생성되었습니다.", "data": {"roomId": 1}}
        """.data(using: .utf8)!

        struct RoomData: Decodable { var roomId: Int }
        let envelope = try JSONDecoder.spatiumAPI.decode(SpatiumAPIEnvelope<RoomData>.self, from: json)

        #expect(envelope.statusCode == 201)
        #expect(envelope.message == "룸이 생성되었습니다.")
        #expect(envelope.data?.roomId == 1)
    }

    @Test func viewModeRawValuesMatchSpec() {
        #expect(RoomViewMode.threeD.rawValue == "3D")
        #expect(RoomViewMode.skyView.rawValue == "SKYVIEW")
    }

    private func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder.spatiumAPI.encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
struct ImgTo3DUploadImageTests {
    /// 8×8 단색 이미지 — 인코딩 테스트용 최소 입력.
    private func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBrown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    @Test func heicPhotoConvertsToPNGForBackend() throws {
        let image = solidImage()
        let heicData = NSMutableData()
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithData(heicData, UTType.heic.identifier as CFString, 1, nil) else {
            return // 이 환경이 HEIC 인코딩을 지원하지 않으면 검증 불가
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return }

        let normalized = try #require(ImgTo3DUploadImage.normalize(image: image, rawData: heicData as Data))
        #expect(normalized.convertedFromIncompatibleFormat)
        #expect(normalized.fileExtension == "png")
        #expect(normalized.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func jpegPhotoPassesThroughUnchanged() throws {
        let image = solidImage()
        let jpeg = try #require(image.jpegData(compressionQuality: 0.9))
        let normalized = try #require(ImgTo3DUploadImage.normalize(image: image, rawData: jpeg))
        #expect(!normalized.convertedFromIncompatibleFormat)
        #expect(normalized.fileExtension == "jpg")
        #expect(normalized.data == jpeg)
    }

    @Test func cameraCaptureWithoutRawDataEncodesToPNG() throws {
        let normalized = try #require(ImgTo3DUploadImage.normalize(image: solidImage(), rawData: nil))
        #expect(!normalized.convertedFromIncompatibleFormat)
        #expect(normalized.fileExtension == "png")
        #expect(normalized.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
