import Foundation

public struct FoodPhotoAnalysisRequest: Codable, Equatable, Sendable {
    public let image: Image

    public init(image: Image) throws {
        self.image = image
        try validate()
    }

    public func validate() throws { try image.validate() }

    public struct Image: Codable, Equatable, Sendable {
        public static let maximumBytes = 2_097_152
        public let mimeType: String
        public let base64: String

        public init(mimeType: String, base64: String) throws {
            self.mimeType = mimeType
            self.base64 = base64
            try validate()
        }

        public func validate() throws {
            guard ["image/jpeg", "image/png"].contains(mimeType),
                  base64.utf8.count <= ((Self.maximumBytes + 2) / 3) * 4,
                  let bytes = Data(base64Encoded: base64), !bytes.isEmpty,
                  bytes.count <= Self.maximumBytes, bytes.base64EncodedString() == base64 else {
                throw FoodPhotoAnalysisError.invalidImage
            }
            let signature: [UInt8] = mimeType == "image/jpeg"
                ? [0xff, 0xd8, 0xff] : [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
            // Image preparation and the server validate decoded pixels and dimensions.
            guard bytes.starts(with: signature) else { throw FoodPhotoAnalysisError.invalidImage }
        }
    }
}

public struct FoodEstimate: Codable, Equatable, Sendable {
    public let name: String
    public let portion: String
    public let calories: Int
    public let nutrients: MealNutrients
    public let notes: String

    public init(name: String, portion: String, calories: Int, nutrients: MealNutrients, notes: String) throws {
        self.name = name
        self.portion = portion
        self.calories = calories
        self.nutrients = nutrients
        self.notes = notes
        try validate()
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              !portion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, portion.count <= 120,
              (1...5_000).contains(calories), notes.count <= 300 else {
            throw FoodPhotoAnalysisError.invalidEstimate
        }
        try nutrients.validate()
    }
}

public struct FoodPhotoAnalysis: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case recognized, unrecognized
    }

    public let id: UUID
    public let createdAt: Date
    public let model: String
    public let status: Status
    public let food: FoodEstimate?
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, model, status, food, message
    }

    public init(id: UUID, createdAt: Date, model: String, status: Status,
                food: FoodEstimate?, message: String) throws {
        self.id = id
        self.createdAt = createdAt
        self.model = model
        self.status = status
        self.food = food
        self.message = message
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        model = try values.decode(String.self, forKey: .model)
        status = try values.decode(Status.self, forKey: .status)
        food = try values.decode(FoodEstimate?.self, forKey: .food)
        message = try values.decode(String.self, forKey: .message)
    }

    public func validate() throws {
        guard createdAt.timeIntervalSince1970.isFinite,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.count <= 160,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, message.count <= 300,
              message.range(of: "[가-힣]", options: .regularExpression) != nil,
              (status == .recognized) == (food != nil) else { throw FoodPhotoAnalysisError.invalidResponse }
        try food?.validate()
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(model, forKey: .model)
        try values.encode(status, forKey: .status)
        try values.encode(food, forKey: .food)
        try values.encode(message, forKey: .message)
    }
}

public struct FoodPhotoAnalysisResponse: Codable, Equatable, Sendable {
    public let data: FoodPhotoAnalysis

    public init(data: FoodPhotoAnalysis) { self.data = data }

    public func validate() throws { try data.validate() }
}

public enum FoodPhotoAnalysisError: Error, LocalizedError, Equatable, Sendable {
    case invalidImage, invalidEstimate, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidImage: String(localized: "사진을 확인하고 다시 선택해 주세요.")
        case .invalidEstimate: String(localized: "음식 이름과 영양 정보를 확인해 주세요.")
        case .invalidResponse: String(localized: "음식 분석 결과를 확인할 수 없어요. 다시 시도해 주세요.")
        }
    }
}
