//
//  Utilities.swift
//  FileMonitoringSystem
//
//  Created by Iraniya Naynesh on 27/12/20.
//

import Foundation
import EndpointSecurity

//getting username from uid
public func getUsername(id: uid_t) -> String {
    guard let passwd = getpwuid(id)?.pointee.pw_name else { return "" }
    return String(cString: passwd)
}

// Converts a es_string_token_t to swift string
func getString(tok: es_string_token_t) -> String {
    if tok.length > 0 {
        return String(cString: tok.data)
    }

    return ""
}

extension String {
    init<T>(tupleOfCChars: T, length: Int = Int.max) {
        self = withUnsafePointer(to: tupleOfCChars) {
            let lengthOfTuple = MemoryLayout<T>.size / MemoryLayout<CChar>.size
            return $0.withMemoryRebound(to: UInt8.self, capacity: lengthOfTuple) {
                String(bytes: UnsafeBufferPointer(start: $0, count: Swift.min(length, lengthOfTuple)), encoding: .utf8)!
            }
        }
    }
}
