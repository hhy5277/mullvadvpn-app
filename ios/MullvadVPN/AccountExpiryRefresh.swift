//
//  AccountExpiryRefresh.swift
//  MullvadVPN
//
//  Created by pronebird on 28/05/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import ProcedureKit

private let kRefreshIntervalSeconds: TimeInterval = 60

class AccountExpiryRefresh {

    /// A singleton instance of the AccountExpiryRefresh
    static let shared = AccountExpiryRefresh()

    private let procedureQueue: ProcedureQueue = {
        let queue = ProcedureQueue()
        queue.qualityOfService = .utility
        return queue
    }()

    private var observers = WeakArray<Observer>([])
    private weak var repeatProcedure: RepeatProcedure<Operation>?

    private init() {}

    /// Adds the observer for periodic account expiry updates.
    /// This method is thread safe.
    func startMonitoringUpdates(with block: @escaping (Date) -> Void) -> Observer {
        let observer = Observer(with: block) { [weak self] (observer) in
            DispatchQueue.main.async {
                self?.removeObserver(observer)
            }
        }

        DispatchQueue.main.async {
            self.addObserver(observer)
        }

        return observer
    }

    private func addObserver(_ observer: Observer) {
        if self.observers.isEmpty {
            let procedure = self.makePeriodicUpdateProcedure()

            // Save the reference to the procedure so we can cancel it later
            self.repeatProcedure = procedure

            self.procedureQueue.addOperation(procedure)
        }

        self.observers.append(observer)
    }

    private func removeObserver(_ observer: Observer) {
        observers.removeAll { $0 === observer }

        if observers.isEmpty {
            repeatProcedure?.cancel()
        }
    }

    private func notifyObservers() {
        if let expiry = Account.expiry {
            for observer in observers {
                observer?.notify(with: expiry)
            }
        }
    }

    private func makePeriodicUpdateProcedure() -> RepeatProcedure<Operation> {
        let userDefaultsInteractor = UserDefaultsInteractor.sharedApplicationGroupInteractor

        return RepeatProcedure(wait: .constant(kRefreshIntervalSeconds)) { () -> Operation? in
            let requestProcedure = MullvadAPI.getAccountExpiry(accountToken: Account.token)

            let saveAccountExpiryProcedure = TransformProcedure { (response) throws -> Void in
                userDefaultsInteractor.accountExpiry = try response.result.get()
                }.injectResult(from: requestProcedure)

            let notifyObserversProcedure = UIBlockProcedure(block: { [weak self] in
                self?.notifyObservers()
            })

            notifyObserversProcedure.addDependency(saveAccountExpiryProcedure)

            return GroupProcedure(operations: [requestProcedure, saveAccountExpiryProcedure, notifyObserversProcedure])
        }
    }

    /// The account expiry observer.
    /// Automatically de-registers itself when released.
    class Observer {
        typealias UpdateBlock = (Date) -> Void
        typealias CancellationBlock = (Observer) -> Void

        private let block: UpdateBlock
        private let cancellation: CancellationBlock

        fileprivate init(with block: @escaping UpdateBlock, cancellation: @escaping CancellationBlock) {
            self.block = block
            self.cancellation = cancellation
        }

        deinit {
            cancel()
        }

        func cancel() {
            cancellation(self)
        }

        fileprivate func notify(with expiry: Date) {
            block(expiry)
        }
    }

}

final class WeakBox<A: AnyObject> {
    weak var unbox: A?
    init(_ value: A) {
        unbox = value
    }
}

struct WeakArray<Element: AnyObject> {
    private var items: [WeakBox<Element>] = []

    init(_ elements: [Element]) {
        items = elements.map { WeakBox($0) }
    }
}

extension WeakArray: Collection {
    var startIndex: Int { return items.startIndex }
    var endIndex: Int { return items.endIndex }

    subscript(_ index: Int) -> Element? {
        return items[index].unbox
    }

    func index(after idx: Int) -> Int {
        return items.index(after: idx)
    }
}
