import Foundation

// Simple x64 instruction assembler for common instructions
class InstructionAssembler {
    
    // Mapping of common instruction mnemonics to their opcodes
    private static let instructionMap: [String: String] = [
        // Conditional jumps (1-byte relative jumps)
        "je": "74",     // Jump if Equal
        "jz": "74",     // Jump if Zero (same as JE)
        "jne": "75",    // Jump if Not Equal  
        "jnz": "75",    // Jump if Not Zero (same as JNE)
        "ja": "77",     // Jump if Above
        "jnbe": "77",   // Jump if Not Below or Equal (same as JA)
        "jae": "73",    // Jump if Above or Equal
        "jnb": "73",    // Jump if Not Below (same as JAE)
        "jnc": "73",    // Jump if Not Carry (same as JAE)
        "jb": "72",     // Jump if Below
        "jnae": "72",   // Jump if Not Above or Equal (same as JB)
        "jc": "72",     // Jump if Carry (same as JB)
        "jbe": "76",    // Jump if Below or Equal
        "jna": "76",    // Jump if Not Above (same as JBE)
        "jg": "7f",     // Jump if Greater
        "jnle": "7f",   // Jump if Not Less or Equal (same as JG)
        "jge": "7d",    // Jump if Greater or Equal
        "jnl": "7d",    // Jump if Not Less (same as JGE)
        "jl": "7c",     // Jump if Less
        "jnge": "7c",   // Jump if Not Greater or Equal (same as JL)
        "jle": "7e",    // Jump if Less or Equal
        "jng": "7e",    // Jump if Not Greater (same as JLE)
        "jo": "70",     // Jump if Overflow
        "jno": "71",    // Jump if Not Overflow
        "js": "78",     // Jump if Sign
        "jns": "79",    // Jump if Not Sign
        "jp": "7a",     // Jump if Parity
        "jpe": "7a",    // Jump if Parity Even (same as JP)
        "jnp": "7b",    // Jump if Not Parity
        "jpo": "7b",    // Jump if Parity Odd (same as JNP)
        
        // Common single-byte instructions
        "nop": "90",    // No Operation
        "ret": "c3",    // Return
        "retf": "cb",   // Return Far
        "int3": "cc",   // Interrupt 3 (Breakpoint)
        "int": "cd",    // Interrupt (needs immediate byte)
        "hlt": "f4",    // Halt
        "clc": "f8",    // Clear Carry Flag
        "stc": "f9",    // Set Carry Flag
        "cli": "fa",    // Clear Interrupt Flag
        "sti": "fb",    // Set Interrupt Flag
        "cld": "fc",    // Clear Direction Flag
        "std": "fd",    // Set Direction Flag
        "cmc": "f5",    // Complement Carry Flag
        "sahf": "9e",   // Store AH into Flags
        "lahf": "9f",   // Load Status Flags into AH
        "pushf": "9c",  // Push Flags
        "popf": "9d",   // Pop Flags
        "cbw": "66 98", // Convert Byte to Word
        "cwde": "98",   // Convert Word to Doubleword Extended
        "cdq": "99",    // Convert Doubleword to Qword
        "xlat": "d7",   // Table Look-up Translation
        "daa": "27",    // Decimal Adjust AL after Addition
        "das": "2f",    // Decimal Adjust AL after Subtraction
        "aaa": "37",    // ASCII Adjust after Addition
        "aas": "3f",    // ASCII Adjust after Subtraction
        
        // Additional useful instructions for patching
        "pushad": "60", // Push All General Registers (32-bit)
        "popad": "61",  // Pop All General Registers (32-bit)
        "pusha": "66 60", // Push All General Registers (16-bit)
        "popa": "66 61",  // Pop All General Registers (16-bit)
        "leave": "c9",  // Set SP to BP, then pop BP
        "enter": "c8",  // Make Stack Frame (needs immediate values)
        "iret": "cf",   // Interrupt Return
        "wait": "9b",   // Wait
        "fwait": "9b",  // Floating Wait (same as wait)
        
        // Segment override prefixes (useful for patching)
        "cs": "2e",     // CS segment override prefix
        "ds": "3e",     // DS segment override prefix  
        "es": "26",     // ES segment override prefix
        "fs": "64",     // FS segment override prefix
        "gs": "65",     // GS segment override prefix
        "ss": "36",     // SS segment override prefix
        
        // Unconditional jumps (short)
        "jmp": "eb",    // Short jump (needs relative offset)
        
        // Call instructions
        "call": "e8",   // Near call (needs relative offset)
        
        // Push/Pop (single register)
        "push rax": "50", "push eax": "50", "push ax": "66 50",
        "push rcx": "51", "push ecx": "51", "push cx": "66 51",
        "push rdx": "52", "push edx": "52", "push dx": "66 52",
        "push rbx": "53", "push ebx": "53", "push bx": "66 53",
        "push rsp": "54", "push esp": "54", "push sp": "66 54",
        "push rbp": "55", "push ebp": "55", "push bp": "66 55",
        "push rsi": "56", "push esi": "56", "push si": "66 56",
        "push rdi": "57", "push edi": "57", "push di": "66 57",
        
        "pop rax": "58", "pop eax": "58", "pop ax": "66 58",
        "pop rcx": "59", "pop ecx": "59", "pop cx": "66 59",
        "pop rdx": "5a", "pop edx": "5a", "pop dx": "66 5a",
        "pop rbx": "5b", "pop ebx": "5b", "pop bx": "66 5b",
        "pop rsp": "5c", "pop esp": "5c", "pop sp": "66 5c",
        "pop rbp": "5d", "pop ebp": "5d", "pop bp": "66 5d",
        "pop rsi": "5e", "pop esi": "5e", "pop si": "66 5e",
        "pop rdi": "5f", "pop edi": "5f", "pop di": "66 5f",
        
        // Single register inc/dec
        "inc rax": "48 ff c0", "inc eax": "ff c0", "inc ax": "66 ff c0",
        "inc rcx": "48 ff c1", "inc ecx": "ff c1", "inc cx": "66 ff c1",
        "inc rdx": "48 ff c2", "inc edx": "ff c2", "inc dx": "66 ff c2",
        "inc rbx": "48 ff c3", "inc ebx": "ff c3", "inc bx": "66 ff c3",
        "inc rsp": "48 ff c4", "inc esp": "ff c4", "inc sp": "66 ff c4",
        "inc rbp": "48 ff c5", "inc ebp": "ff c5", "inc bp": "66 ff c5",
        "inc rsi": "48 ff c6", "inc esi": "ff c6", "inc si": "66 ff c6",
        "inc rdi": "48 ff c7", "inc edi": "ff c7", "inc di": "66 ff c7",
        
        "dec rax": "48 ff c8", "dec eax": "ff c8", "dec ax": "66 ff c8",
        "dec rcx": "48 ff c9", "dec ecx": "ff c9", "dec cx": "66 ff c9",
        "dec rdx": "48 ff ca", "dec edx": "ff ca", "dec dx": "66 ff ca",
        "dec rbx": "48 ff cb", "dec ebx": "ff cb", "dec bx": "66 ff cb",
        "dec rsp": "48 ff cc", "dec esp": "ff cc", "dec sp": "66 ff cc",
        "dec rbp": "48 ff cd", "dec ebp": "ff cd", "dec bp": "66 ff cd",
        "dec rsi": "48 ff ce", "dec esi": "ff ce", "dec si": "66 ff ce",
        "dec rdi": "48 ff cf", "dec edi": "ff cf", "dec di": "66 ff cf"
    ]
    
    /// Attempts to assemble a single instruction from mnemonic to bytes
    /// Returns the assembled bytes as a hex string, or nil if not found
    static func assembleInstruction(_ instruction: String) -> String? {
        let cleanInstruction = instruction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First try exact match
        if let bytes = instructionMap[cleanInstruction] {
            return bytes
        }
        
        // Try to handle just the mnemonic part for simple conditional jump changes
        let parts = cleanInstruction.split(separator: " ", maxSplits: 1)
        if parts.count >= 1 {
            let mnemonic = String(parts[0])
            
            // For simple mnemonic-only instructions (like "jne" instead of "jne 0x1234")
            if let bytes = instructionMap[mnemonic] {
                if parts.count == 1 {
                    // Just the mnemonic - return with placeholder offset for relative jumps
                    if mnemonic.hasPrefix("j") && mnemonic != "jmp" {
                        return bytes + " 00" // Use 0x00 offset for same address (no jump)
                    }
                    return bytes
                } else {
                    // Has operands - handle relative jumps
                    let _ = String(parts[1]) // Operand - not used yet for relative calculations
                    if let baseOpcode = instructionMap[mnemonic] {
                        // For now, just return the base opcode - relative jump calculation
                        // would need current address and target address
                        return baseOpcode + " 00" // Default to no offset
                    }
                }
            }
        }
        
        // Try to handle relative jumps with explicit addresses
        if cleanInstruction.hasPrefix("j") && cleanInstruction.contains(" ") {
            let parts = cleanInstruction.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let mnemonic = String(parts[0])
                let _ = String(parts[1]) // Target address - not used yet
                
                if let baseOpcode = instructionMap[mnemonic] {
                    // For now, just return the base opcode - relative jump calculation
                    // would need current address and target address
                    return baseOpcode + " 00" // Use 0x00 offset for same address
                }
            }
        }
        
        return nil
    }
    
    /// Gets a list of supported instruction mnemonics
    static func getSupportedInstructions() -> [String] {
        return Array(instructionMap.keys).sorted()
    }
    
    /// Checks if an instruction is supported
    static func isSupported(_ instruction: String) -> Bool {
        let cleanInstruction = instruction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return instructionMap[cleanInstruction] != nil
    }
    
    /// Attempts to disassemble common single-byte opcodes back to mnemonics
    static func disassembleOpcode(_ bytes: String) -> String? {
        let cleanBytes = bytes.lowercased().replacingOccurrences(of: " ", with: "")
        
        // Reverse lookup in the instruction map
        for (mnemonic, opcode) in instructionMap {
            let cleanOpcode = opcode.lowercased().replacingOccurrences(of: " ", with: "")
            if cleanOpcode == cleanBytes {
                return mnemonic.uppercased()
            }
        }
        
        return nil
    }
    
    /// Calculates relative jump offset for conditional jumps
    static func calculateRelativeJump(from currentAddress: UInt64, to targetAddress: UInt64, instructionLength: Int = 2) -> Int8? {
        let offset = Int64(targetAddress) - Int64(currentAddress) - Int64(instructionLength)
        
        // Check if offset fits in signed 8-bit range (-128 to 127)
        if offset >= -128 && offset <= 127 {
            return Int8(offset)
        }
        
        return nil // Would need to use 32-bit relative jump
    }
    
    /// Assembles a conditional jump with target address
    static func assembleJumpInstruction(_ mnemonic: String, from currentAddress: UInt64, to targetAddress: UInt64) -> String? {
        guard let baseOpcode = instructionMap[mnemonic.lowercased()] else {
            return nil
        }
        
        guard let relativeOffset = calculateRelativeJump(from: currentAddress, to: targetAddress) else {
            return nil // Jump too far for short jump
        }
        
        let offsetHex = String(format: "%02x", UInt8(bitPattern: relativeOffset))
        return "\(baseOpcode) \(offsetHex)"
    }
}

// Extension to help with parsing instruction formats
extension String {
    func parseInstruction() -> (mnemonic: String, operands: String?) {
        let parts = self.split(separator: " ", maxSplits: 1)
        let mnemonic = String(parts[0]).lowercased()
        let operands = parts.count > 1 ? String(parts[1]) : nil
        return (mnemonic, operands)
    }
}

// Helper for getting alternative jump instructions
extension InstructionAssembler {
    /// Gets alternative jump instructions for the current instruction
    static func getAlternativeJumps(for currentInstruction: String) -> [String] {
        let current = currentInstruction.lowercased()
        
        // Define alternative jump groups
        let jumpAlternatives: [String: [String]] = [
            "je": ["jne", "jz", "jnz"],
            "jz": ["jnz", "je", "jne"],
            "jne": ["je", "jnz", "jz"],
            "jnz": ["jz", "jne", "je"],
            "ja": ["jb", "jae", "jbe"],
            "jb": ["ja", "jbe", "jae"],
            "jae": ["jb", "ja", "jbe"],
            "jbe": ["ja", "jb", "jae"],
            "jg": ["jl", "jge", "jle"],
            "jl": ["jg", "jle", "jge"],
            "jge": ["jl", "jg", "jle"],
            "jle": ["jg", "jl", "jge"],
            "jo": ["jno"],
            "jno": ["jo"],
            "js": ["jns"],
            "jns": ["js"],
            "jc": ["jnc"],
            "jnc": ["jc"],
            "jp": ["jnp"],
            "jnp": ["jp"]
        ]
        
        return jumpAlternatives[current] ?? []
    }
    
    /// Get common instruction alternatives for any instruction
    static func getCommonAlternatives(for instruction: String) -> [String] {
        let inst = instruction.lowercased()
        
        if inst.hasPrefix("j") {
            return getAlternativeJumps(for: inst)
        }
        
        // Other common alternatives
        switch inst {
        case "ret":
            return ["nop", "int3", "hlt"]
        case "nop":
            return ["ret", "int3"]
        case "int3":
            return ["nop", "ret"]
        case "call":
            return ["jmp", "nop"]
        default:
            return []
        }
    }
}
