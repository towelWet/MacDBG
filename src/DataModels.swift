import Foundation
import SwiftUI

// MARK: - Debugger State
public enum DebuggerState {
    case idle
    case attaching(pid_t)
    case attached
    case running
    case stepping
    case continuing
    case stopped(reason: String)
    case detaching
    case error(String)
}

public struct ProcessInfo: Identifiable, Equatable {
    public let id = UUID()
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String

    public init(pid: pid_t, ppid: pid_t, name: String) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
    }
}

public enum DisassemblyDirection {
    case forward
    case backward
}

// Range selection like x64dbg - supports continuous ranges
public struct DisassemblySelection {
    public var startAddress: UInt64?
    public var endAddress: UInt64?
    public var anchorAddress: UInt64?  // Where selection started
    
    public init() {}
    
    public var isEmpty: Bool {
        startAddress == nil || endAddress == nil
    }
    
    public var count: Int {
        guard startAddress != nil, endAddress != nil else { return 0 }
        // Count based on address positions in the list
        return 1  // Will be calculated properly in the view
    }
    
    public func contains(_ address: UInt64) -> Bool {
        guard let start = startAddress, let end = endAddress else { return false }
        let minAddr = min(start, end)
        let maxAddr = max(start, end)
        return address >= minAddr && address <= maxAddr
    }
    
    public mutating func setSingleSelection(_ address: UInt64) {
        startAddress = address
        endAddress = address
        anchorAddress = address
    }
    
    public mutating func expandTo(_ address: UInt64) {
        guard let anchor = anchorAddress else {
            setSingleSelection(address)
            return
        }
        
        startAddress = min(anchor, address)
        endAddress = max(anchor, address)
    }
    
    public mutating func clear() {
        startAddress = nil
        endAddress = nil
        anchorAddress = nil
    }
}

// Represents one line of disassembled code
public struct DisassemblyLine: Identifiable, Hashable, Decodable {
    public var id: UInt64 { address }  // Use address as identity for proper SwiftUI updates
    public let address: UInt64
    public let bytes: String
    public let instruction: String
    public let operands: String

    public init(address: UInt64, bytes: String, instruction: String, operands: String) {
        self.address = address
        self.bytes = bytes
        self.instruction = instruction
        self.operands = operands
    }

    public var formattedAddress: String { String(format: "0x%llX", address) }

    enum CodingKeys: String, CodingKey {
        case address, bytes, instruction, operands
    }
}

public struct MemoryLine: Identifiable, Decodable {
    public let id = UUID()
    public let address: String
    public let bytes: String
    public let ascii: String

    public init(address: String, bytes: String, ascii: String) {
        self.address = address
        self.bytes = bytes
        self.ascii = ascii
    }

    enum CodingKeys: String, CodingKey {
        case address, bytes, ascii
    }
}

// Represents a single CPU register
public struct Register: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let value: String
}

// Represents an entry in the console log
public struct ConsoleEntry: Identifiable, Hashable {
    public let id = UUID()
    let timestamp: Date
    let text: String
    let type: EntryType

    enum EntryType {
        case command, info, success, error, warning
    }

    var color: Color {
        switch type {
        case .command: return .cyan
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }
}

// MARK: - LLDB Server Communication Models

/// A generic container for all messages from the Python script.
struct LLDBMessage: Decodable {
    let type: MessageType
    let payload: AnyCodable

    enum MessageType: String, Decodable {
        case log
        case attached
        case detached
        case stopped
        case registers
        case disassembly
        case memory
        case error
        case writeByte
        case string_references
    }
}

/// Payload for the `stopped` event.
public struct LLDBStoppedEvent: Decodable {
    public let reason: String
    public let threadId: UInt64
    public let pc: UInt64
    
    enum CodingKeys: String, CodingKey {
        case reason
        case threadId = "thread_id"
        case pc
    }
}

/// Payload for the `registers` response.
public struct LLDBRegistersResponse: Decodable {
    public let registers: [String: String?]
    
    enum CodingKeys: String, CodingKey {
        case registers
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawRegisters = try container.decode([String: AnyCodable?].self, forKey: .registers)
        
        // Convert to [String: String?] handling null values
        var convertedRegisters: [String: String?] = [:]
        for (key, value) in rawRegisters {
            if let anyValue = value?.value {
                convertedRegisters[key] = String(describing: anyValue)
            } else {
                convertedRegisters[key] = nil
            }
        }
        self.registers = convertedRegisters
    }
}

/// Payload for a generic error.
public struct LLDBErrorEvent: Decodable {
    public let message: String
}

/// Payload for the `disassembly` response.
public struct LLDBDisassemblyResponse: Decodable {
    public let lines: [DisassemblyLine]
}

/// Payload for the `memory` response.
public struct LLDBMemoryResponse: Decodable {
    public let lines: [MemoryLine]
}

/// Response for memory write operations.
struct LLDBWriteByteResponse: Decodable {
    let success: Bool
    let error: String?
    let address: UInt64
    let value: UInt8
}

/// A type-erased wrapper to decode and encode arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else if container.decodeNil() {
            value = ()
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            let anyCodableArray = arrayValue.map { AnyCodable(value: $0) }
            try container.encode(anyCodableArray)
        case let dictValue as [String: Any]:
            let anyCodableDict = dictValue.mapValues { AnyCodable(value: $0) }
            try container.encode(anyCodableDict)
        case _ as Void:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON type"))
        }
    }

    // Helper initializer to wrap a value
    init(value: Any) {
        self.value = value
    }
}

// MARK: - String Analysis (Ghidra-style)

/// String data structure (like Ghidra's string analysis)
public struct StringData: Identifiable, Equatable {
    public let id = UUID()
    public let address: UInt64
    public let content: String
    public let length: Int
    
    public init(address: UInt64, content: String, length: Int) {
        self.address = address
        self.content = content
        self.length = length
    }
}

/// String reference structure (like Ghidra's cross-references)
public struct StringReference: Identifiable, Equatable {
    public let id = UUID()
    public let address: UInt64
    public let instruction: String
    public let module: String
    
    public init(address: UInt64, instruction: String, module: String) {
        self.address = address
        self.instruction = instruction
        self.module = module
    }
}

// MARK: - LLDB Response Models

/// Response structure for string references from LLDB server
public struct LLDBStringReferencesResponse {
    public let payload: StringReferencesPayload
    
    public init(payload: StringReferencesPayload) {
        self.payload = payload
    }
}

/// Payload for string references response
public struct StringReferencesPayload {
    public let stringAddress: UInt64
    public let references: [StringReference]
    public let count: Int
    
    public init(stringAddress: UInt64, references: [StringReference], count: Int) {
        self.stringAddress = stringAddress
        self.references = references
        self.count = count
    }
}

