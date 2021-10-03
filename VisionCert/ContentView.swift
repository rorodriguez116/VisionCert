//
//  ContentView.swift
//  VisionCert
//
//  Created by Rolando Rodriguez on 11/5/20.
//

import SwiftUI
import Vision
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
    @State var boxLayers = [CALayer]()
    
    var captureSession: AVCaptureSession
    var orientation: AVCaptureVideoOrientation
    var observations: ObservationsGroup
    var visionToAVFTransform: CGAffineTransform
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = captureSession
        view.previewLayer.connection?.videoOrientation = orientation
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        show(boxGroups: observations, view: uiView)
    }
    
    
    // Remove all drawn boxes. Must be called on main queue.
    func removeBoxes() {
        for layer in boxLayers {
            layer.removeFromSuperlayer()
        }
        boxLayers.removeAll()
    }
    
    // Draws groups of colored boxes.
    func show(boxGroups: ObservationsGroup, view: PreviewView) {
        DispatchQueue.main.async {
            removeBoxes()
            
            for group in [boxGroups.text, boxGroups.rectangles] {
                for box in group {
                                                            
                    let rect = view.previewLayer.layerRectConverted(fromMetadataOutputRect: box.boundingBox.applying(self.visionToAVFTransform))                    
                                                                                
                    let layer = CAShapeLayer()
                    layer.borderWidth = 2
                    layer.frame = rect
                    
                  
                    layer.borderColor = UIColor.blue.cgColor
                    layer.backgroundColor = UIColor.red.cgColor
                    layer.opacity = 0.3
                    boxLayers.append(layer)
                    view.previewLayer.insertSublayer(layer, at: 1)
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject var vision = VisionCertService()
    @StateObject var manager = BlockchainManager()

    var captureButton: some View {
        Button(action: {
            vision.capturePhoto()
        }, label: {
            Circle()
                .foregroundColor(.white)
                .frame(width: 80, height: 80, alignment: .center)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        .frame(width: 65, height: 65, alignment: .center)
                )
        })
    }
    
    var body: some View {
        ZStack {
            CameraViewFinder(captureSession: vision.captureSession, orientation: vision.videoOrientation, observations: ObservationsGroup(text: vision.textObservations, rectangles: vision.rectangleObservations), visionToAVFTransform: vision.visionToAVFTransform)
            
            VStack {
                HStack {
                    Button(action: {
                        vision.toggleTorch()
                    }, label: {
                        Image(systemName: vision.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 22, weight: .medium, design: .default))
                            .contentShape(Rectangle())
                            .frame(width: 30, height: 30, alignment: .top)
                    })
                    .accentColor(.white)
                    
                    Spacer()
                    
                    Text(vision.analyzer.currentPage.rawValue.capitalized)
                        .bold()
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                }
                
                Spacer()
                
                captureButton
            }
            .padding(.horizontal, 30)
        }
        .onAppear {
            manager.setup()
            vision.onAppear()
        }
        .sheet(isPresented: $vision.shouldShowResults) {
            ResultsViewer(manager: manager, text: vision.analyzer.found, hash: vision.analyzer.hash)
                .onDisappear {
                    vision.onAppear()
                }
        }
    }
}

struct ResultsViewer: View {
    @Environment(\.presentationMode) var presentationMode
    
    @ObservedObject var manager: BlockchainManager
    
    let text: String
    
    let hash: String
    
    @State var resultColor = Color.white
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    Text(text)
                        .foregroundColor(resultColor)
                        .multilineTextAlignment(.leading)
                        .padding()
                }
                .navigationTitle("Resultados")
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Registrar") {
                            manager.writeValueToSmartContract(with: hash)
                        }
                    }
                    
                    ToolbarItem(placement: .bottomBar) {
                        Button("Validar") {
                            manager.readValueFromSmartContract(hash)
                        }
                    }
                    
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                    
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cerrar") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .onReceive(manager.$validationState, perform: { state in
                    if state != .none {
                        resultColor = state == .valid ? .green : .red
                    }
                })
            }
        }
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
