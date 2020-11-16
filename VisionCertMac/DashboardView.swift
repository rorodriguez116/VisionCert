//
//  ContentView.swift
//  VisionCertMac
//
//  Created by Rolando Rodriguez on 11/4/20.
//

import SwiftUI
import Foundation

struct DashboardView: View {
    @ObservedObject var analyzer: CertAnalyzer
    @ObservedObject var manager: BlockchainManager
    
    var load: Bool {
        analyzer.frontImage != nil
    }
    
    @State var resultColor = Color.white
    
    var body: some View {
        ZStack {
            HStack(spacing: 50) {
                VStack {
                    Text("Bienvenido a Certchain")
                        .font(.title)
                        .padding(.bottom, 30)
                    
                    HStack(spacing: 50) {
                        HStack(spacing: 4) {
                            Circle()
                                .foregroundColor(.green)
                                .frame(width: 12, height: 12, alignment: .center)
                            Text("Valido")
                        }
                        
                        
                        HStack(spacing: 4) {
                            Circle()
                                .frame(width: 12, height: 12, alignment: .center)
                                .foregroundColor(.red)
                            
                            Text("Invalido")
                        }
                        
                    }
                    
                    Text("Resultado obtenido:")
                        .font(.headline)
                        .padding(.bottom, 10)
                    
                    if analyzer.selectedCertificate != nil && analyzer.selectedCertificate?.hash != "" {
                        Text("HASH: \(analyzer.selectedCertificate!.hash)")
                            .padding(.bottom, 30)
                    }
                    
                    if analyzer.selectedCertificate != nil {
                        ScrollView(.vertical) {
                            Text(analyzer.selectedCertificate!.fullText)
                                .foregroundColor(resultColor)
                                .fixedSize()
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text("Agrega un certificado académico para ver validarlo o registrarlo en Certchain.")
                            .fixedSize()
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    HStack {
                        Button("Registrar") {
                            if analyzer.selectedCertificate != nil {
                                manager.writeValueToSmartContract(with: analyzer.selectedCertificate!.hash)
                            }
                        }
                        .disabled(!load && !manager.isWorking)

                        
                        Button("Validar") {
                            if analyzer.selectedCertificate != nil {
                                manager.readValueFromSmartContract(analyzer.selectedCertificate!.hash)
                            } else {
                                print("Will not run verification on Blockchain with an empty value")
                            }
                        }
                        .disabled(!load && !manager.isWorking)
                        
                    }
                }
                
                VStack(spacing: 25) {
                    if analyzer.selectedCertificate != nil {
                        ScrollView {
                            VStack(spacing: 5) {
                                Image(nsImage: analyzer.frontImage!)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .overlay(
                                        CertAnalyzerView(boxes: ObservationsGroup(text: analyzer.selectedCertificate!.frontPage.boxes, rectangles: analyzer.rectangleObservations))
                                    )
                                    .frame(width: 800, height: 500)
                                
                                if analyzer.backImage != nil {
                                    Image(nsImage: analyzer.backImage!)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .overlay(
                                            CertAnalyzerView(boxes: ObservationsGroup(text: analyzer.selectedCertificate!.backPage.boxes, rectangles: analyzer.rectangleObservations))
                                        )
                                        .frame(width: 800, height: 500)
                                }
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray, lineWidth: 6)
                            .overlay(Text("Carga el anverso y reverso de tu certificado."))
                            .frame(width: 800, height: 500)
                            
                    }
                    
                    if analyzer.certificates.count > 0 {
                        HStack {
                            Button("<") {
                                analyzer.showPrev()
                            }
                            
                            Text("\(analyzer.currentIndex + 1)/\(analyzer.certificates.count)")
                            
                            Button(">") {
                                analyzer.showNext()
                            }
                            .disabled(!load)
                        }
                    }
                    
                    HStack {
                        Button("Cargar Anversos") {
                            resultColor = .white
                            analyzer.selectFiles(for: .front)
                        }
                        
                        Button("Cargar Reversos") {
                            resultColor = .white
                            analyzer.selectFiles(for: .back)
                        }
                        
                        Button("Extraer características") {
                            analyzer.process()
                        }
                        .disabled(!load || analyzer.selectedCertificate?.backPage.fileUrl == nil)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if analyzer.isLoading {
                Color.black
                    .opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                
                ProgressIndicator()
            }
        }
        .onAppear {
            manager.setup()
        }
        .onReceive(manager.$validationState, perform: { state in
            if state != .none {
                resultColor = state == .valid ? .green : .red
            }
        })
        
    }
    
    private func selectFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.begin { (result) in
            if result == .OK, let url = openPanel.url {
                analyzer.textObservations.removeAll()
                analyzer.frontImage = NSImage(contentsOf: url)
            }
        }
    }
}

struct ProgressIndicator: NSViewRepresentable {
    
    
    func makeNSView(context: NSViewRepresentableContext<ProgressIndicator>) -> NSProgressIndicator {
        
        let nsView = NSProgressIndicator()
        
        nsView.isIndeterminate = true
        nsView.style = .spinning
        nsView.controlTint = .defaultControlTint
        
        return nsView
    }
    
    func updateNSView(_ nsView: NSProgressIndicator, context: NSViewRepresentableContext<ProgressIndicator>) {
        nsView.startAnimation(self)

    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(analyzer: CertAnalyzer(), manager: BlockchainManager())
    }
}
