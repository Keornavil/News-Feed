//
//  Coordinator.swift
//  News feed
//
//  Created by Василий Максимов on 21.11.2025.
//

import Foundation
import UIKit

protocol CoordinatorProtocol: AnyObject {
    var navigationController: UINavigationController? { get set }
    var assemblyBuilder: AssemblyModuleBuilderProtocol? {get set}
    func initialMainViewController()
}

final class Coordinator: CoordinatorProtocol {
    var navigationController: UINavigationController?
    var assemblyBuilder: AssemblyModuleBuilderProtocol?
    
    init(navigationController: UINavigationController, assemblyBuilder: AssemblyModuleBuilderProtocol) {
        self.navigationController = navigationController
        self.assemblyBuilder = assemblyBuilder
    }
    func initialMainViewController() {
        guard let navigationController = navigationController,
              let mainViewController = assemblyBuilder?.createMainViewModule() else {return}
        navigationController.viewControllers = [mainViewController]
    }
}
