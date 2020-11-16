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


struct Certificate {
    struct PageData {
        var fileUrl: URL!
        
        var text: String
        
        var boxes: [VNRecognizedTextObservation]
    }

    var frontPage: PageData
    
    var backPage: PageData

    let date: Date

    var hash: String

    var fullText: String
    
}

enum CertificateSide {
    case front
    case back
    case both
}

class CertAnalyzer: ObservableObject {
    @Published var textObservations = [VNRecognizedTextObservation]()
    
    @Published var rectangleObservations = [VNRectangleObservation]()
    
    @Published var found = ""
    
    @Published var hash = ""
    
    @Published var accurateResult = ""
    
    @Published var fastResults = Set<String>()
    
    @Published var shouldShowResults = false
    
    @Published var results = [String]()
    
//    New stuff
    #if os(macOS)
    @Published var frontImage: NSImage?
    
    @Published var backImage: NSImage?
    #endif
    
    @Published var certificates = [Certificate]()
    
    @Published var isLoading = false
    
    @Published var selectedCertificate: Certificate?
    
    var accurateRequest: VNRecognizeTextRequest!
    
    var fastRequest: VNRecognizeTextRequest!
    
    var rectangleRequest: VNDetectRectanglesRequest!
    // Temporal string tracker
    private let featureTracker = StringTracker()
        
    var currentIndex = 0
    
    var currentPage = CertificateSide.front
    
    var currentProccessingIndex = 0
    
    
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
        accurateRequest.usesLanguageCorrection = true
        
        fastRequest = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        fastRequest.usesCPUOnly = false
        fastRequest.recognitionLevel = .fast
        
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
    
    #if os(macOS)
    func selectFiles(for side: CertificateSide) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.begin { [weak self] (result) in
            if result == .OK {
                if openPanel.urls.count > 0 {
                    if side == .front {
                        self?.certificates = openPanel.urls.map({ (url) -> Certificate in
                            Certificate(frontPage: Certificate.PageData(fileUrl: url, text: "", boxes: []), backPage: Certificate.PageData(fileUrl: nil, text: "", boxes: []), date: Date(), hash: "", fullText: "")
                        })
                    } else {
                        for i in 0 ..< openPanel.urls.count {
                            let backPage = Certificate.PageData(fileUrl: openPanel.urls[i], text: "", boxes: [])
                            self?.certificates[i].backPage = backPage
                        }
                    }
                    
                    self?.load(to: side)
                }
            }
        }
    }
    
    private func load(to side: CertificateSide) {
        switch side {
        case .front:
            guard let url =  certificates[currentIndex].frontPage.fileUrl, let image = NSImage(contentsOf: url) else { return }
            frontImage = image
        case .back:
            guard let url =  certificates[currentIndex].backPage.fileUrl, let image = NSImage(contentsOf: url) else { return }
            backImage = image
        case .both:
            guard let frontUrl =  certificates[currentIndex].frontPage.fileUrl, let frontImage = NSImage(contentsOf: frontUrl), let backUrl =  certificates[currentIndex].backPage.fileUrl, let backImage = NSImage(contentsOf: backUrl)  else { return }
            self.backImage = backImage
            self.frontImage = frontImage
        }
       
        selectedCertificate = certificates[currentIndex]
    }
    
    public func showNext() {
        if currentIndex + 1 < certificates.count {
            currentIndex += 1
            load(to: .both)
        }
    }
    
    public func showPrev() {
        if currentIndex > 0 {
            currentIndex -= 1
            load(to: .both)
        }
    }
    
    public func process() {
        self.isLoading = true
                
        currentProccessingIndex = 0
        
        var counter = 0
        
        let requestHandlers = certificates.compactMap { (certificate) -> (VNImageRequestHandler, VNImageRequestHandler)? in
            if let temp = NSImage(contentsOf: certificate.frontPage.fileUrl)?.cgImage, let temp2 = NSImage(contentsOf: certificate.backPage.fileUrl)?.cgImage {
                return (VNImageRequestHandler(cgImage: temp, orientation: .up, options: [:]), VNImageRequestHandler(cgImage: temp2, orientation: .up, options: [:]))
            } else {
                return nil
            }
        }
        
        requestHandlers.forEach { (handler) in
            let request1: VNRecognizeTextRequest = {
                let accurateRequest = VNRecognizeTextRequest(completionHandler: recognizeAccurateTextHandler)
                accurateRequest.usesCPUOnly = false
                accurateRequest.recognitionLevel = .accurate
                accurateRequest.recognitionLanguages = ["ES"]
                accurateRequest.usesLanguageCorrection = false
                return accurateRequest
            }()
            
            let request2: VNRecognizeTextRequest = {
                let accurateRequest = VNRecognizeTextRequest(completionHandler: recognizeAccurateTextHandler)
                accurateRequest.usesCPUOnly = false
                accurateRequest.recognitionLevel = .accurate
                accurateRequest.recognitionLanguages = ["ES"]
                accurateRequest.usesLanguageCorrection = false
                return accurateRequest
            }()
            
            counter += 1
            
            print("Proccessing certificate #\(counter)")
            
            do {
                try handler.0.perform([request1])
                            
                print("Successfully processed certificate #\(counter) front side")
            } catch {
                print(error)
            }
            
            do {
                try handler.1.perform([request2])
                
                print("Successfully processed certificate #\(counter) rear side")
            } catch {
                print(error)
            }

        }
        
        self.isLoading = false
        
    }
    
    #endif
    
    public func process(cgImage: CGImage) {
        self.isLoading = true
                
        currentProccessingIndex = 0
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        
        accurateRequest = VNRecognizeTextRequest(completionHandler: recognizeAccurateTextHandler)
        accurateRequest.usesCPUOnly = false
        accurateRequest.recognitionLevel = .accurate
        accurateRequest.recognitionLanguages = ["ES"]
        accurateRequest.usesLanguageCorrection = false
                        
        do {
            try requestHandler.perform([accurateRequest])
            print("Successfully processed certificate")
        } catch {
            print(error)
        }
        
        self.isLoading = false
        
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
        
//        // Log any found numbers.
//        featureTracker.logFrame(strings: features)
//
//        // Check if we have any temporally stable numbers.
//        if let certainText = featureTracker.getStableString() {
//            print("I'm confident of this observation: ", certainText)
//            fastResults.insert(certainText)
//            featureTracker.reset(string: certainText)
//        }
        
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
            
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            var fullText = ""
            let maximumCandidates = 1
            for observation in results {
                guard let candidate = observation.topCandidates(maximumCandidates).first else { continue }
                fullText += candidate.string
                fullText += "\n"
            }
            
        
            fullText += "\n"
            fullText += "\n"
        
//            print(fullText)
            
                                    
            self?.textObservations = results
            
            guard let index = self?.currentProccessingIndex, let currentCount = self?.certificates.count else { return }
            
            if index < currentCount {
                if self?.currentPage == .front {
                    self?.certificates[index].frontPage.boxes = results
                    self?.currentPage = .back
                    self?.certificates[index].frontPage.text = fullText

                } else {
                    self?.certificates[index].backPage.boxes = results
                    self?.currentPage = .front
                    self?.certificates[index].backPage.text = fullText
                    self?.currentProccessingIndex += 1
                    
                    // Still just extracting for one page at a time
                    guard let frontText = self?.certificates[index].backPage.text, let backText = self?.certificates[index].frontPage.text, let HASH = self?.cleanAndProcess(string: frontText + backText) else { return }
                    //
                    
                    self?.certificates[index].fullText = frontText + "\n" + backText

                    self?.certificates[index].hash = HASH
                    
                    self?.found = fullText
                }
            }
            
            #if os(macOS)
            
            self?.load(to: .both)
            
            #endif
            
            self?.shouldShowResults = true
            
        }
    }
}
