//
//  CertAnalyzerView.swift
//  VisionCertMac
//
//  Created by Rolando Rodriguez on 11/5/20.
//

import SwiftUI
import Vision

#if os(macOS)
import AppKit
extension NSImage {
    public var cgImage: CGImage? {
        guard let imageData = self.tiffRepresentation else { return nil }
        guard let sourceData = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(sourceData, 0, nil)
    }
}
#else
import UIKit
#endif

typealias ObservationsGroup = (text: [VNRecognizedTextObservation], rectangles: [VNRectangleObservation])

struct CertAnalyzerView {
    var boxes: ObservationsGroup
            
    init(boxes: ObservationsGroup) {
        self.boxes = boxes
    }
    
    // Draws groups of colored boxes.
    func show(boxGroups: ObservationsGroup, view: Any) {
        #if os(macOS)
        guard let view = view as? NSView else { return }
        #else
        guard let view = view as? UIView else { return }
        #endif
        
        DispatchQueue.main.async {
            view.subviews.forEach { $0.removeFromSuperview() }
        
            for group in [boxGroups.text, boxGroups.rectangles] {
                for box in group {
                    let size = view.frame.size
                    
//                    MARK: Working transform for macOS
                                        
//                    let transform = CGAffineTransform.identity
//                        .translatedBy(x: 0, y: size.height)
//                        .scaledBy(x: 1, y: -1)
//                        .scaledBy(x: size.width, y: -size.height)
                    
                    let rect = VNImageRectForNormalizedRect(box.boundingBox, Int(size.width), Int(size.height))

                                        
//                    MARK: Rect working on macOS
//                    let rect = CGRect(x: convertedBottomLeft.x, y: convertedBottomRight.y - size.height, width: convertedBottomRight.x - convertedBottomLeft.x, height: convertedTopRight.y - convertedBottomRight.y)
                    
                                        
                    let layer = CAShapeLayer()
                    layer.borderWidth = 2
                    layer.frame = rect
                    
                    #if os(macOS)

                    let holder = NSView(frame: rect)
                    layer.borderColor = NSColor.blue.cgColor
                    holder.layer = layer
                    holder.wantsLayer = true
                    holder.layer?.backgroundColor = NSColor.red.cgColor
                    holder.layer?.opacity = 0.3

                    #else
                    let holder = UIView(frame: rect)
                    layer.borderColor = UIColor.blue.cgColor
                    layer.backgroundColor = UIColor.red.cgColor
                    layer.opacity = 0.3
                    holder.layer.addSublayer(layer)
                    #endif
                    
                    
                    view.addSubview(holder)
                }
            }
        }
    }    
}

#if os(macOS)
extension CertAnalyzerView: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSView {
        let holder = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let layer = CALayer()
        holder.layer = layer
        holder.wantsLayer = true
        holder.layer?.backgroundColor = NSColor.clear.cgColor
        show(boxGroups: boxes, view: holder)

        return holder
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        show(boxGroups: boxes, view: nsView)
    }
}

#else

extension CertAnalyzerView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.backgroundColor = UIColor.clear
        show(boxGroups: boxes, view: holder)
        return holder
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        show(boxGroups: boxes, view: uiView)
    }
}

#endif

struct CertAnalyzerView_Previews: PreviewProvider {
    static var previews: some View {
        CertAnalyzerView(boxes: ObservationsGroup([], []))
    }
}
