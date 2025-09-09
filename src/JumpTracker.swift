import Foundation
import SwiftUI

// MARK: - Simple Jump Line Data

public struct JumpLine: Identifiable, Hashable {
    public let id = UUID()
    public let fromAddress: UInt64
    public let toAddress: UInt64
    public let fromLine: Int
    public let toLine: Int? // nil when target is off-screen
    public let isConditional: Bool
    public let mnemonic: String
}

// MARK: - Simple Jump Tracker

public class JumpTracker: ObservableObject {
    @Published public var jumpLines: [JumpLine] = []
    @Published public var highlightedJump: JumpLine?
    
    /// Find jumps in the given disassembly lines
    public func analyzeJumps(for instructions: [DisassemblyLine]) {
        jumpLines.removeAll()
        
        guard !instructions.isEmpty else { 
            print("🔍 No instructions to analyze")
            return 
        }
        
        print("🔍 Analyzing \(instructions.count) instructions for jumps...")
        
        // Create address to line index mapping
        let addressToIndex = Dictionary(uniqueKeysWithValues: 
            instructions.enumerated().map { ($1.address, $0) }
        )
        
        var jumpCount = 0
        var potentialJumps = 0
        
        // Analyze each instruction for jumps
        for (index, instruction) in instructions.enumerated() {
            let mnemonic = instruction.instruction.lowercased()
            
            // Check if this is a jump instruction
            if isJumpInstruction(mnemonic) {
                potentialJumps += 1
                
                // Parse target address from operands
                if let targetAddress = parseJumpTarget(instruction.operands) {
                    // Create jump line regardless of whether target is visible
                    let targetLineIndex = addressToIndex[targetAddress] // nil if target not in view
                    let jumpLine = JumpLine(
                        fromAddress: instruction.address,
                        toAddress: targetAddress,
                        fromLine: index,
                        toLine: targetLineIndex, // Can be nil for off-screen targets
                        isConditional: isConditionalJump(mnemonic),
                        mnemonic: mnemonic
                    )
                    jumpLines.append(jumpLine)
                    jumpCount += 1
                    
                    if targetLineIndex != nil {
                        print("✅ Jump: \(mnemonic) \(String(format: "0x%llx", instruction.address)) → \(String(format: "0x%llx", targetAddress)) (visible)")
                    } else {
                        print("➡️ Jump: \(mnemonic) \(String(format: "0x%llx", instruction.address)) → \(String(format: "0x%llx", targetAddress)) (off-screen)")
                    }
                }
            }
        }
        
        print("🔍 Analysis complete: \(jumpCount)/\(potentialJumps) jumps added from \(instructions.count) instructions")
    }
    
    /// Get jump target for a specific address (for double-click navigation)
    public func getJumpTarget(for address: UInt64) -> UInt64? {
        return jumpLines.first(where: { $0.fromAddress == address })?.toAddress
    }
    
    /// Highlight a specific jump
    public func highlightJump(from address: UInt64) {
        highlightedJump = jumpLines.first(where: { $0.fromAddress == address })
    }
    
    /// Clear jump highlighting
    public func clearHighlight() {
        highlightedJump = nil
    }
    
    // MARK: - Private Methods
    
    private func isJumpInstruction(_ mnemonic: String) -> Bool {
        let jumpInstructions = [
            "jmp", "call",
            "je", "jne", "jz", "jnz", "jg", "jl", "jge", "jle",
            "ja", "jb", "jae", "jbe", "js", "jns", "jo", "jno",
            "jc", "jnc", "jp", "jnp"
        ]
        return jumpInstructions.contains(mnemonic)
    }
    
    private func isConditionalJump(_ mnemonic: String) -> Bool {
        return mnemonic != "jmp" && mnemonic != "call"
    }
    
    private func parseJumpTarget(_ operands: String) -> UInt64? {
        let trimmed = operands.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern 1: Direct hex address (0x1234567890abcdef)
        if trimmed.hasPrefix("0x") {
            let hexPart = String(trimmed.dropFirst(2))
            if let address = UInt64(hexPart, radix: 16) {
                return address
            }
        }
        
        // Pattern 2: Plain hex without 0x prefix (for addresses >= 0x1000)
        // Remove any trailing suffixes like 'h' or other decorators
        let cleanHex = trimmed.replacingOccurrences(of: "h", with: "")
                              .replacingOccurrences(of: "H", with: "")
        
        if let address = UInt64(cleanHex, radix: 16), address >= 0x1000 {
            return address
        }
        
        // Pattern 3: Handle bracketed addresses [0x...]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            return parseJumpTarget(inner)
        }
        
        // Pattern 4: Handle relative offsets (+/-) - would need current instruction address
        // This is complex and might not be needed for basic jump detection
        
        return nil
    }
}
