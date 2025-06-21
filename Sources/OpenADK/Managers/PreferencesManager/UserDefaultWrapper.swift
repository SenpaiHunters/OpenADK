//
//  UserDefaultWrapper.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Combine
import Observation
import SwiftUI

// MARK: - UserDefault

/// This is used instead of @AppStorage as that clashes with @Observable and I want all of the vars in
/// The PreferenceManager to be accessible without needing to list all vars in each view we have to change variables
@propertyWrapper
public struct UserDefault<Value> {
    public let key: String
    public let defaultValue: Value
    public var container: UserDefaults = .standard
    private let publisher = PassthroughSubject<Value, Never>()

    public var wrappedValue: Value {
        get {
            container.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            // Check whether we're dealing with an optional and remove the object if the new value is nil.
            if let optional = newValue as? AnyOptional, optional.isNil {
                container.removeObject(forKey: key)
            } else {
                container.set(newValue, forKey: key)
            }
            publisher.send(newValue)
        }
    }

    public var projectedValue: AnyPublisher<Value, Never> {
        publisher.eraseToAnyPublisher()
    }
}

// MARK: - AnyOptional

/// Allows to match for optionals with generics that are defined as non-optional.
public protocol AnyOptional {
    /// Returns `true` if `nil`, otherwise `false`.
    var isNil: Bool { get }
}

// MARK: - Optional + AnyOptional

extension Optional: AnyOptional {
    public var isNil: Bool { self == nil }
}
