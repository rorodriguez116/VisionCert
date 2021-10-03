//
//  BlockchainManager.swift
//  VisionCertMac
//
//  Created by Rolando Rodriguez on 11/5/20.
//


import SwiftUI
import Web3
import Web3PromiseKit
import Web3ContractABI

class BlockchainManager: ObservableObject {
    enum ValidationState {
        case none
        case valid
        case invalid
    }
    
    @Published var validationState = ValidationState.none
    @Published var isWorking = false
    
    let web3 = Web3(rpcURL: "http://192.168.0.8:8543")
    
    init() {
      
    }
    
    func setup() {
        do {
            let myPrivateKey = try EthereumPrivateKey(hexPrivateKey: "1fe509288ba0ccff67be00a08342b19bcbfabade39d8e52e5fddc7b8d425f732")
            print("Address to write from:", myPrivateKey.address.ethereumValue())

            firstly {
                web3.eth.getBalance(address: myPrivateKey.address, block: .latest)
            }.done { ethereumQuantity in
                print(ethereumQuantity)
            }.catch { error in
                print("Error:", error.localizedDescription)
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func batchWrite(values: [String]) {
        
    }
    
    func writeValueToSmartContract(with value: String) {
//        Previous contract address: 0x8A9eB61240D5693E5f3cc0f9f18a7A7ea6e3E4A6
        do {
            let contractAddress = try EthereumAddress(hex: "0xE662ddB18d73E825dBddc47003d0351871Cac5a7", eip55: true)
            guard let path = Bundle.main.path(forResource: "SC4", ofType: "json") else { return }
            let url = URL(fileURLWithPath: path)
            let jsonData = try? Data(contentsOf: url)
            
            // You can optionally pass an abiKey param if the actual abi is nested and not the top level element of the json
            let contract = try web3.eth.Contract(json: jsonData!, abiKey: nil, address: contractAddress)
            
            let myPrivateKey = try EthereumPrivateKey(hexPrivateKey: "1fe509288ba0ccff67be00a08342b19bcbfabade39d8e52e5fddc7b8d425f732")
            //             Get gas price to write contract transaction
            firstly {
                contract["verify"]!(value).estimateGas()
            }.done { [weak self] gas in
               try self?.getNonce(for: contract, value: value, gas: gas, privateKey: myPrivateKey)
            }.catch { error in
                print("Error writeValueToSmartContract: ", error)
            }
                        
            //             Write value to contract
           
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func getNonce(for contract: DynamicContract, value: String, gas: EthereumQuantity, privateKey: EthereumPrivateKey) throws {
        firstly {
            self.web3.eth.getTransactionCount(address: privateKey.address, block: .latest)
        }.done { [weak self] nonce in
            try self?.buildTransactionWith(contract: contract, value: value, gas: gas, nonce: nonce, privateKey: privateKey)
        }.catch { error in
            print("Error getNonce:", error)
        }
    }
    
    func buildTransactionWith(contract: DynamicContract, value: String, gas: EthereumQuantity, nonce: EthereumQuantity, privateKey: EthereumPrivateKey) throws {
        print("Nonce for write:", nonce, "Estimated gas:", gas)
        
        guard let transaction = contract["register"]?(value).createTransaction(nonce: nonce, from: privateKey.address, value: 0, gas: 4097301, gasPrice: EthereumQuantity(quantity: 20.gwei)) else { return }
        
        let signexTx = try transaction.sign(with: privateKey, chainId: 2020)
        
        self.writeContract(with: signexTx)
    }
    
    func writeContract(with signexTx: EthereumSignedTransaction) {
        DispatchQueue.main.async {
            self.isWorking = true
        }
        
        firstly {
            web3.eth.sendRawTransaction(transaction: signexTx)
        }
        .done { [weak self] txHash in
            print("Transaction HASH:", txHash.ethereumValue())
//            print("Is Mining: ", txHash)
            
            self?.getReceipt(txHash: txHash)
        }.catch { error in
            print("Error on writeContract: ", error)
        }
    }
    
    
    func getReceipt(txHash: EthereumData) {
        firstly {
            web3.eth.getTransactionReceipt(transactionHash: txHash)
        }.done { output in
            print("Receipt Output:", output)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.isWorking = false
            }
        }.catch { error in
            print("Error on getReceipt: ", error)
        }
    }
    
    func readValueFromSmartContract(_ value: String) {
        do {
            let contractAddress = try EthereumAddress(hex: "0xE662ddB18d73E825dBddc47003d0351871Cac5a7", eip55: true)
            guard let path = Bundle.main.path(forResource: "SC4", ofType: "json") else { return }
            let url = URL(fileURLWithPath: path)
            let jsonData = try? Data(contentsOf: url)
            
            // You can optionally pass an abiKey param if the actual abi is nested and not the top level element of the json
            let contract = try web3.eth.Contract(json: jsonData!, abiKey: nil, address: contractAddress)
            
            // Read value of some address
            firstly {
                contract["verify"]!(value).call()
            }.done { [weak self] outputs in
                guard let output = outputs.first?.value as? Bool else { return }
                self?.validationState = output ? .valid : .invalid
                print("Verification status for \(value)", output)
            }.catch { error in
                print(error)
            }
            
        } catch {
            print(error.localizedDescription)
        }
    }
}
