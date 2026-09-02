import Foundation

/// Shared JSON Schema DSL for tool manifests.
///
/// Every tool used to hand-write `FamiliarJSONSchema.init`, which is how array
/// parameters shipped without an element type and how numeric bounds ended up
/// living only in prose inside `description`. These factories are the single
/// place a parameter shape is expressed.
///
/// When a factory declares `defaultValue`, the Swift side must apply the same
/// constant, otherwise the schema and the executed behaviour drift apart. Use
/// the `FamiliarToolDefaults` constants for anything referenced in both places.
nonisolated extension FamiliarJSONSchema {
    static func object(
        _ properties: [String: FamiliarJSONSchema],
        required: [String] = []
    ) -> FamiliarJSONSchema {
        .init(type: .object, properties: properties, required: required)
    }

    static func string(
        _ description: String,
        enumValues: [String]? = nil,
        defaultValue: String? = nil
    ) -> FamiliarJSONSchema {
        .init(
            type: .string,
            description: description,
            enumValues: enumValues,
            defaultValue: defaultValue.map(FamiliarJSONSchemaValue.string)
        )
    }

    static func boolean(
        _ description: String,
        defaultValue: Bool? = nil
    ) -> FamiliarJSONSchema {
        .init(
            type: .boolean,
            description: description,
            defaultValue: defaultValue.map(FamiliarJSONSchemaValue.boolean)
        )
    }

    static func integer(
        _ description: String,
        minimum: Int? = nil,
        maximum: Int? = nil,
        defaultValue: Int? = nil
    ) -> FamiliarJSONSchema {
        .init(
            type: .integer,
            description: description,
            minimum: minimum.map(Double.init),
            maximum: maximum.map(Double.init),
            defaultValue: defaultValue.map(FamiliarJSONSchemaValue.integer)
        )
    }

    static func number(
        _ description: String,
        minimum: Double? = nil,
        maximum: Double? = nil,
        defaultValue: Double? = nil
    ) -> FamiliarJSONSchema {
        .init(
            type: .number,
            description: description,
            minimum: minimum,
            maximum: maximum,
            defaultValue: defaultValue.map(FamiliarJSONSchemaValue.number)
        )
    }

    /// A typed array. `items` is required because an array without an element
    /// type gives the model nothing to generate against.
    static func array(
        _ description: String,
        items: FamiliarJSONSchema,
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) -> FamiliarJSONSchema {
        .init(
            type: .array,
            description: description,
            items: items,
            minItems: minItems,
            maxItems: maxItems
        )
    }

    static func stringArray(
        _ description: String,
        itemDescription: String,
        enumValues: [String]? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) -> FamiliarJSONSchema {
        .array(
            description,
            items: .string(itemDescription, enumValues: enumValues),
            minItems: minItems,
            maxItems: maxItems
        )
    }

    static func objectArray(
        _ description: String,
        properties: [String: FamiliarJSONSchema],
        required: [String] = [],
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) -> FamiliarJSONSchema {
        .array(
            description,
            items: .object(properties, required: required),
            minItems: minItems,
            maxItems: maxItems
        )
    }
}

/// Bounds and defaults referenced by both a manifest schema and the Swift code
/// that executes the tool. Declaring them once keeps the model's contract and
/// the runtime behaviour from drifting.
nonisolated enum FamiliarToolDefaults {
    enum EventQuery {
        static let minimumLimit = 1
        static let maximumLimit = 200
        static let limit = 20
    }

    enum ReminderPriority {
        static let minimum = 0
        static let maximum = 9
    }

    enum MapSearch {
        static let minimumLimit = 1
        static let maximumLimit = 10
        static let limit = 5
    }

    enum WeatherForecast {
        static let minimumDays = 1
        static let maximumDays = 10
        static let days = 3
    }

    enum WeatherHistory {
        /// WeatherKit historical coverage begins on 2021-08-01T00:00:00Z.
        static let earliestDate = Date(timeIntervalSince1970: 1_627_776_000)
        /// WeatherKit returns at most 10 days per daily range request.
        static let maximumDays = 10
        static let earliestDateDescription = "2021-08-01"
    }

    enum Alarm {
        static let maximumLabelCharacters = 120
    }

    enum HealthActivity {
        static let minimumDays = 1
        static let maximumDays = 31
        static let days = 7
    }

    enum MusicSearch {
        static let minimumLimit = 1
        static let maximumLimit = 10
        static let limit = 5
    }

    enum BluetoothScan {
        static let minimumServiceUUIDs = 1
        static let maximumServiceUUIDs = 8
        static let minimumDuration: Double = 2
        static let maximumDuration: Double = 10
        static let duration: Double = 5
    }

    enum PhotoMetadata {
        static let minimumLimit = 1
        static let maximumLimit = 50
        static let limit = 10
        static let imagesOnly = true
    }

    enum NaturalLanguage {
        static let maximumCharacters = 40_000
        static let maximumEntities = 60
    }

    enum Notification {
        static let maximumTitleCharacters = 120
        static let maximumBodyCharacters = 1_000
    }
}
