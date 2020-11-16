/*
Authors: Rolando Rodriguez & Diego Carcovich

Abstract:
Vision view controller.
			Recognizes text using a Vision VNRecognizeTextRequest request handler in pixel buffers from an AVCaptureOutput.
			Displays bounding boxes around recognized text results in real time.
*/

import Foundation
import UIKit
import AVFoundation
import Vision
import CryptoKit
import Combine

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
}

class VisionCertService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let analyzer = CertAnalyzer()
    // MARK: - UI objects
    var maskLayer = CAShapeLayer()
    // Device orientation. Updated whenever the orientation changes to a
    // different supported orientation.
    var currentOrientation = UIDeviceOrientation.portrait
    
    // MARK: - Capture related objects
    @Published var captureSession = AVCaptureSession()
    
    @Published var textObservations = [VNRecognizedTextObservation]()
    
    @Published var rectangleObservations = [VNRectangleObservation]()
    
    @Published var videoOrientation = AVCaptureVideoOrientation.portrait
    
    @Published var isTorchOn = false
    
    @Published var shouldShowResults = false
    
    let captureSessionQueue = DispatchQueue(label: "com.rry.visioncert.CaptureSessionQueue")
    
    var captureDevice: AVCaptureDevice?
    
    let captureOutput = AVCapturePhotoOutput()

    var videoDataOutput = AVCaptureVideoDataOutput()
    
    let videoDataOutputQueue = DispatchQueue(label: "com.rry.visioncert.VideoDataOutputQueue")
    
    // MARK: - Region of interest (ROI) and text orientation
    // Region of video data output buffer that recognition should be run on.
    // Gets recalculated once the bounds of the preview layer are known.
    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    // Orientation of text to search for in the region of interest.
    var textOrientation = CGImagePropertyOrientation.up
    
    // MARK: - Coordinate transforms
    var bufferAspectRatio: Double!
    // Transform from UI orientation to buffer orientation.
    var uiRotationTransform = CGAffineTransform.identity
    // Transform bottom-left coordinates to top-left.
    var bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    
    // Vision -> AVF coordinate transform.
    @Published var visionToAVFTransform = CGAffineTransform.identity
    
    private var subscriptions = Set<AnyCancellable>()
    
    override init() {
        super.init()
        // Starting the capture session is a blocking call. Perform setup using
        // a dedicated serial dispatch queue to prevent blocking the main thread.
        
        analyzer.$textObservations
            .receive(on: RunLoop.main)
            .sink { [weak self] (observation) in
            self?.textObservations = observation
        }
        .store(in: &self.subscriptions)
            
        analyzer.$shouldShowResults
            .receive(on: RunLoop.main)
            .sink { [weak self] (val) in
                self?.shouldShowResults = val 
            }
            .store(in: &self.subscriptions)
        
        
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification).sink { [weak self] (_) in
            self?.updateOrientation()
        }
        .store(in: &self.subscriptions)
        
        captureSessionQueue.async {
            self.setupCamera()
            
            // Calculate region of interest now that the camera is setup.
            DispatchQueue.main.async {
                // Figure out initial ROI.
                self.setupOrientationAndTransform()
            }
        }
    }
    
    func updateOrientation() {

        // Only change the current orientation if the new one is landscape or
        // portrait. You can't really do anything about flat or unknown.
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            currentOrientation = deviceOrientation
        }

        // Handle device orientation in the preview layer.
        if let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
            videoOrientation = newVideoOrientation
        }

        setupOrientationAndTransform()
    }


    func setupOrientationAndTransform() {
        // Compensate for orientation (buffers always come in the same orientation).
        switch currentOrientation {
        case .landscapeLeft:
            textOrientation = CGImagePropertyOrientation.up
            uiRotationTransform = CGAffineTransform.identity
        case .landscapeRight:
            textOrientation = CGImagePropertyOrientation.down
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 1).rotated(by: CGFloat.pi)
        case .portraitUpsideDown:
            textOrientation = CGImagePropertyOrientation.left
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 0).rotated(by: CGFloat.pi / 2)
        default: // We default everything else to .portraitUp
            textOrientation = CGImagePropertyOrientation.right
            uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
        }
        
        // Full Vision ROI to AVF transform.
        visionToAVFTransform =
            bottomToTopTransform
            .concatenating(uiRotationTransform)
    }
    
    func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) else {
            print("Could not create capture device.")
            return
        }
        self.captureDevice = captureDevice
    
        // NOTE:
        // Requesting 4k buffers allows recognition of smaller text but will
        // consume more power. Use the smallest buffer size necessary to keep
        // down battery usage.
        if captureDevice.supportsSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
            bufferAspectRatio = 3840.0 / 2160.0
        } else {
            captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080
            bufferAspectRatio = 1920.0 / 1080.0
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Could not create device input.")
            return
        }
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
        }
        
        // Configure video data output.
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            captureSession.addOutput(captureOutput)

            // NOTE:
            // There is a trade-off to be made here. Enabling stabilization will
            // give temporally more stable results and should help the recognizer
            // converge. But if it's enabled the VideoDataOutput buffers don't
            // match what's displayed on screen, which makes drawing bounding
            // boxes very hard. Disable it in this app to allow drawing detected
            // bounding boxes on screen.
            videoDataOutput.connection(with: AVMediaType.video)?.preferredVideoStabilizationMode = .off
        } else {
            print("Could not add VDO output")
            return
        }
        
        // Set zoom and autofocus to help focus on very small text.
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.videoZoomFactor = 1
            captureDevice.autoFocusRangeRestriction = .none
            captureDevice.unlockForConfiguration()
        } catch {
            print("Could not set zoom level due to error: \(error)")
            return
        }
        
        captureSession.startRunning()
        
      
    }

    var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    let captureQueue = DispatchQueue(label: "captureQueue")
    
    func toggleTorch() {
        do {
            try captureDevice?.lockForConfiguration()
            captureDevice?.torchMode = isTorchOn ? .off : .on
            isTorchOn.toggle()
            captureDevice?.unlockForConfiguration()
        } catch {
            print("Could not set torch on due to error: \(error)")
            return
        }
    }
        
    func onAppear() {
        
        captureSessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    /// - Tag: CapturePhoto
    @objc
    public func capturePhoto() {
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. This to ensures that UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        
//        MARK: TODO: Handle orientation for iOS camera capture.
//        let videoPreviewLayerOrientation = self.previewView.videoPreviewLayer.connection?.videoOrientation
      
        captureQueue.async {
            if let photoOutputConnection = self.captureOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = .portrait
            }
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture HEIF photos when supported. Enable according to user settings and high-resolution photos.
            if  self.captureOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
//            photoSettings.isHighResolutionPhotoEnabled = true
            
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            
            photoSettings.photoQualityPrioritization = .speed
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that AVCam took a photo.
                DispatchQueue.main.async {
                    //                        self.willCapturePhoto.toggle()
                    //                        self.willCapturePhoto.toggle()
                }
            }, completionHandler: { [weak self] (photoCaptureProcessor) in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                if let data = photoCaptureProcessor.photoData, let cgImage = UIImage(data: data)?.cgImage, let request = self?.analyzer.accurateRequest, let session = self?.captureSession, let orientation = self?.textOrientation {
                    print("Proccessing photo")
                    
                    self?.captureSessionQueue.async {
                        session.stopRunning()
                    }
                                        
                    let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                    do {
                        try requestHandler.perform([request])
                    } catch {
                        print(error)
                    }
                    
                } else {
                    print("No photo data to process, capture failed")
                }
                
                self?.captureSessionQueue.async {
                    self?.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }

                
            }, photoProcessingHandler: { animate in
                
            })
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.captureOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
	
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: textOrientation, options: [:])
			do {
                try requestHandler.perform([analyzer.fastRequest])
			} catch {
				print(error)
			}
		}
	}
}
