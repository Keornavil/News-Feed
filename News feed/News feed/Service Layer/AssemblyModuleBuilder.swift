//
//  AssemblyModuleBuilder.swift
//  News feed
//
//  Created by Василий Максимов on 21.11.2025.
//

import Foundation
import UIKit
import CoreData

protocol AssemblyModuleBuilderProtocol: AnyObject {
    func createMainViewModule() -> UIViewController
}

class AssemblyModuleBuilder: AssemblyModuleBuilderProtocol {
    func createMainViewModule() -> UIViewController {
        let networkService = NetworkServiceWithAlamofire()
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            fatalError("AppDelegate not found")
        }
        let backgroundContext = appDelegate.persistentContainer.newBackgroundContext()
        let livenessService = NetworkLivenessService()
        let repository = NewsRepository(networkService: networkService, context: backgroundContext, livenessService: livenessService)
        let viewModel = MainViewModel(repository: repository, livenessService: livenessService)
        let view = MainViewController(viewModel: viewModel)
        return view
    }
}
