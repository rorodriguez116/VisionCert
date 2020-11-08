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
    
    @State var load = false
    @State var resultColor = Color.white
    @State var isWorking = false
    
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
                        .padding(.bottom, 30)
                    
                  

                    if analyzer.found != "" {
                   
                        ScrollView(.vertical) {
                            Text(analyzer.found)
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
                    Button("Cargar Certificado") {
                        load.toggle()
                    }
                    .disabled(load)
                    
                    Button("Extraer características") {
                        analyzer.analyzePhoto()
                    }
                    .disabled(!load)
                    
                    Button("Registrar") {
                        manager.writeValueToSmartContract()
//                        isWorking.toggle()
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
//                            isWorking.toggle()
//                        }
                    }
                    .disabled(!load)

                    
                    Button("Validar") {
                        if analyzer.hash != "" {
                            manager.readValueFromSmartContract(analyzer.hash)
                        } else {
                            print("Will not run verification on Blockchain with an empty value")
                        }
                    }
                    .disabled(!load)

                }
            }
            
            if load {
                Image("back")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(
                        CertAnalyzerView(boxes: ObservationsGroup(text: analyzer.textObservations, rectangles: analyzer.rectangleObservations))
                    )
                    .frame(width: 800, height: 500)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray, lineWidth: 6)
                    .frame(width: 800, height: 500)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if isWorking {
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
