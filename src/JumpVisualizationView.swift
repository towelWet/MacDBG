import SwiftUI

/// Simple jump arrow visualization overlay
struct JumpVisualizationView: View {
    let jumpTracker: JumpTracker
    let lineHeight: CGFloat
    
    var body: some View {
        Canvas { context, size in
            drawJumpArrows(context: context, size: size)
        }
        .allowsHitTesting(false) // Allow clicks to pass through
        .onAppear {
            print("🎨 JumpVisualizationView appeared with \(jumpTracker.jumpLines.count) jumps")
            print("🎨 Available jump lines: \(jumpTracker.jumpLines.map { "\($0.mnemonic) \(String(format: "0x%llx", $0.fromAddress))" })")
        }
        .onChange(of: jumpTracker.jumpLines) { jumps in
            print("🔄 Jump lines updated: \(jumps.count) jumps detected")
        }
    }
    
    private func drawJumpArrows(context: GraphicsContext, size: CGSize) {
        let jumps = jumpTracker.jumpLines // Include all jumps, even off-screen ones
        
        // Only log when we actually have jumps to draw
        if jumps.count > 0 {
            print("🎨 Drawing \(jumps.count) jump arrows (some may be off-screen)")
            print("   Canvas size: \(size)")
            print("   Line height: \(lineHeight)")
            for (i, jump) in jumps.enumerated() {
                print("   Jump \(i): \(jump.mnemonic) at line \(jump.fromLine) -> line \(jump.toLine ?? -1)")
            }
        }
        
        for (index, jump) in jumps.enumerated() {
            let startY = CGFloat(jump.fromLine) * lineHeight + lineHeight/2
            
            // Handle off-screen targets
            let endY: CGFloat
            let isOffScreen: Bool
            
            if let destLine = jump.toLine {
                // Target is visible in current disassembly
                endY = CGFloat(destLine) * lineHeight + lineHeight/2
                isOffScreen = false
            } else {
                // Target is off-screen - determine direction
                // This is a simplified heuristic: if target address > current address, arrow points down
                if jump.toAddress > jump.fromAddress {
                    endY = size.height + 20 // Point down off bottom
                } else {
                    endY = -20 // Point up off top
                }
                isOffScreen = true
            }
            
            // Always draw if at least one point is in view or nearby
            let margin: CGFloat = 100
            guard (startY >= -margin && startY <= size.height + margin) ||
                  (endY >= -margin && endY <= size.height + margin) else {
                continue
            }
            
            let isHighlighted = jumpTracker.highlightedJump?.id == jump.id
            let color = getJumpColor(for: jump, isHighlighted: isHighlighted, isOffScreen: isOffScreen)
            let lineWidth: CGFloat = isHighlighted ? 4.0 : 2.5 // Thicker lines
            
            // x64dbg style positioning
            let leftMargin: CGFloat = 5
            let arrowColumn = leftMargin + CGFloat(index % 4) * 8 // More columns
            
            var path = Path()
            
            // Fixed-width canvas coordinates
            let rightEdge = size.width - 2 // Right edge of the 40px jump area
            
            if isOffScreen {
                // For off-screen jumps, draw a simpler arrow pointing in the right direction
                path.move(to: CGPoint(x: arrowColumn, y: startY))
                path.addLine(to: CGPoint(x: rightEdge, y: startY))
                
                // Add a visual indicator that this goes off-screen
                let indicatorY = startY + (endY > startY ? 10 : -10)
                path.move(to: CGPoint(x: arrowColumn, y: startY))
                path.addLine(to: CGPoint(x: arrowColumn, y: indicatorY))
                
                // Draw off-screen arrowhead
                drawOffScreenArrowhead(context: context, at: CGPoint(x: rightEdge, y: startY), 
                                     color: color, pointingDown: endY > startY)
            } else {
                // Draw like x64dbg: vertical line in left gutter, then horizontal to instruction
                if abs(startY - endY) > 5 { // Only draw if there's vertical movement
                    // Vertical line in the gutter
                    path.move(to: CGPoint(x: arrowColumn, y: min(startY, endY)))
                    path.addLine(to: CGPoint(x: arrowColumn, y: max(startY, endY)))
                    
                    // Horizontal line to source
                    path.move(to: CGPoint(x: arrowColumn, y: startY))
                    path.addLine(to: CGPoint(x: rightEdge, y: startY))
                    
                    // Horizontal line to destination  
                    path.move(to: CGPoint(x: arrowColumn, y: endY))
                    path.addLine(to: CGPoint(x: rightEdge, y: endY))
                } else {
                    // Short horizontal line for same-line or very close jumps
                    path.move(to: CGPoint(x: leftMargin, y: startY))
                    path.addLine(to: CGPoint(x: rightEdge, y: endY))
                }
                
                // Draw arrowhead at destination
                drawArrowhead(context: context, at: CGPoint(x: rightEdge, y: endY), color: color, size: 6)
            }
            
            // Draw the path with stronger colors
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
            
            // Draw source dot
            let sourceRect = CGRect(x: arrowColumn - 2, y: startY - 2, width: 4, height: 4)
            context.fill(Path(ellipseIn: sourceRect), with: .color(color))
        }
    }
    
    private func drawArrowhead(context: GraphicsContext, at point: CGPoint, color: Color, size: CGFloat = 4) {
        var arrowPath = Path()
        arrowPath.move(to: point)
        arrowPath.addLine(to: CGPoint(x: point.x - size, y: point.y - size/2))
        arrowPath.addLine(to: CGPoint(x: point.x - size, y: point.y + size/2))
        arrowPath.closeSubpath()
        
        context.fill(arrowPath, with: .color(color))
    }
    
    private func drawOffScreenArrowhead(context: GraphicsContext, at point: CGPoint, color: Color, pointingDown: Bool) {
        let size: CGFloat = 6
        var arrowPath = Path()
        
        if pointingDown {
            // Arrow pointing down (target is below)
            arrowPath.move(to: CGPoint(x: point.x, y: point.y + size))
            arrowPath.addLine(to: CGPoint(x: point.x - size/2, y: point.y))
            arrowPath.addLine(to: CGPoint(x: point.x + size/2, y: point.y))
        } else {
            // Arrow pointing up (target is above)
            arrowPath.move(to: CGPoint(x: point.x, y: point.y - size))
            arrowPath.addLine(to: CGPoint(x: point.x - size/2, y: point.y))
            arrowPath.addLine(to: CGPoint(x: point.x + size/2, y: point.y))
        }
        arrowPath.closeSubpath()
        
        context.fill(arrowPath, with: .color(color))
    }
    
    private func getJumpColor(for jump: JumpLine, isHighlighted: Bool, isOffScreen: Bool = false) -> Color {
        if isHighlighted {
            return .orange
        }
        
        // x64dbg style colors - bright and visible
        let opacity: Double = isOffScreen ? 0.6 : 0.8 // Dimmer for off-screen
        
        if jump.isConditional {
            return Color.blue.opacity(opacity)  // Bright blue for conditional jumps
        } else if jump.mnemonic == "call" {
            return Color.red.opacity(opacity)   // Red for calls (like x64dbg)
        } else {
            return Color.green.opacity(opacity) // Green for unconditional jumps
        }
    }
}
