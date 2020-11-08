//
//  ContentView.swift
//  VisionCert
//
//  Created by Rolando Rodriguez on 11/5/20.
//

import SwiftUI
import AVFoundation

class PreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraViewFinder: UIViewRepresentable {
    let captureSession: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = captureSession
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        
    }
}

struct ContentView: View {
    @StateObject var vision = VisionCertService()
    
    var body: some View {
        CameraViewFinder(captureSession: vision.captureSession)
            .onAppear {
                vision.onAppear()
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
