//
//  CertAnalyzer.swift
//  VisionCertMac
//
//  Created by Rolando Rodriguez on 11/5/20.
//

import Foundation
import SwiftUI
import AVFoundation
import Vision
import CryptoKit

class CertAnalyzer: ObservableObject {
    @Published var textObservations = [VNRecognizedTextObservation]()
    
    @Published var rectangleObservations = [VNRectangleObservation]()
    
    @Published var found = ""
    
    @Published var hash = ""
    
    @Published var accurateResult = ""
    
    @Published var fastResults = Set<String>()

    
    var accurateRequest: VNRecognizeTextRequest!
    
    var fastRequest: VNRecognizeTextRequest!
    
    var rectangleRequest: VNDetectRectanglesRequest!
    // Temporal string tracker
    private let featureTracker = StringTracker()
    
    
    func cleanAndProcess(string: String) -> String? {
        let normalized = string.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        guard let data = normalized.data(using: .utf32, allowLossyConversion: true) else {
            return nil
        }
        
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    init() {
        accurateRequest = VNRecognizeTextRequest(completionHandler: recognizeAccurateTextHandler)
        accurateRequest.usesCPUOnly = false
        accurateRequest.recognitionLevel = .accurate
        accurateRequest.recognitionLanguages = ["ES"]
        accurateRequest.usesLanguageCorrection = false
        
        fastRequest = VNRecognizeTextRequest(completionHandler: recognizeAccurateTextHandler)
        fastRequest.usesCPUOnly = false
        fastRequest.recognitionLevel = .accurate
        fastRequest.recognitionLanguages = ["ES"]
        fastRequest.usesLanguageCorrection = false
        
        rectangleRequest = VNDetectRectanglesRequest(completionHandler: recognizedRectangleHandler)
        rectangleRequest.usesCPUOnly = false
        rectangleRequest.maximumObservations = 1
        rectangleRequest.minimumAspectRatio = 0.5
        rectangleRequest.maximumAspectRatio = 1.0
        rectangleRequest.minimumSize = 0.25
        rectangleRequest.quadratureTolerance = 45.0
        rectangleRequest.minimumConfidence = 0.85
        
        
    }
    
    var isScanning = false
    
    public func analyzePhoto() {
        if let cgImage = NSImage(named: "back")?.cgImage, let request = self.accurateRequest {
            print("Proccessing photo")
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try requestHandler.perform([request])
            } catch {
                print(error)
            }
            
        } else {
            print("No photo data to process, capture failed")
        }
        
    }
    
    // MARK: - Text recognition
    
    // Vision recognition handler.
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        var features = [String]()
        var greenBoxes = [CGRect]() // Shows words that might be serials
        
        guard let results = request.results as? [VNRecognizedTextObservation] else {
            return
        }
        
        let maximumCandidates = 1
        
        for visionResult in results {
            guard let candidate = visionResult.topCandidates(maximumCandidates).first else { continue }
            
            features.append(candidate.string)
            
            greenBoxes.append(visionResult.boundingBox)
            
        }
        
        // Log any found numbers.
        featureTracker.logFrame(strings: features)
        
        // Check if we have any temporally stable numbers.
        if let certainText = featureTracker.getStableString() {
            print("I'm confident of this observation: ", certainText)
            fastResults.insert(certainText)
            featureTracker.reset(string: certainText)
        }
        
        textObservations = results
        
    }
    
    func recognizedRectangleHandler(request: VNRequest, error: Error?) {
        var orangeBoxes = [CGRect]()
        
        guard let results = request.results as? [VNRectangleObservation] else {
            return
        }
        
        for vresult in results {
            orangeBoxes.append(vresult.boundingBox)
            print("Recognized rectangle rec: ", vresult.boundingBox)
            
        }
        
        rectangleObservations = results
    }
    
    func recognizeAccurateTextHandler(request: VNRequest, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            var orangeBoxes = [CGRect]()
            
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            for vresult in results {
                orangeBoxes.append(vresult.boundingBox)
                print("Recognized rectangle rec: ", vresult.boundingBox)
                
            }
            
            var fullText = ""
            let maximumCandidates = 1
            for observation in results {
                guard let candidate = observation.topCandidates(maximumCandidates).first else { continue }
                fullText += candidate.string
                fullText += "\n"
            }
            
            //
            guard let HASH = self?.cleanAndProcess(string: fullText) else { return }
            //
            
            fullText += "\n"
            fullText += "\n"
            fullText += "HASH: \(HASH)"
            self?.found = fullText
            print(fullText)
            
            self?.hash = HASH
            
            self?.textObservations = results
            
        }
    }
}
