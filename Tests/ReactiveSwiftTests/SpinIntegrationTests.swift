//
//  SpinIntegrationTests.swift
//  
//
//  Created by Thibault Wittemberg on 2019-12-31.
//

import ReactiveSwift
import SpinReactiveSwift
import SpinCommon
import XCTest

fileprivate enum StringAction {
    case append(String)
}

final class SpinIntegrationTests: XCTestCase {

    private let disposeBag = CompositeDisposable()

    func test_multiple_feedbacks_produces_incremental_states_while_executed_on_default_executer() throws {
        let exp = expectation(description: "incremental states")
        var receivedStates = [String]()

        // Given: an initial state, feedbacks and a reducer
        var counterA = 0
        let effectA = { (state: String) -> SignalProducer<StringAction, Never> in
            counterA += 1
            let counter = counterA
            return SignalProducer<StringAction, Never>(value: .append("_a\(counter)"))
        }

        var counterB = 0
        let effectB = { (state: String) -> SignalProducer<StringAction, Never> in
            counterB += 1
            let counter = counterB
            return SignalProducer<StringAction, Never>(value: .append("_b\(counter)"))
        }

        var counterC = 0
        let effectC = { (state: String) -> SignalProducer<StringAction, Never> in
            counterC += 1
            let counter = counterC
            return SignalProducer<StringAction, Never>(value: .append("_c\(counter)"))
        }

        let reducerFunction = { (state: String, action: StringAction) -> String in
            switch action {
            case .append(let suffix):
                return state+suffix
            }
        }

        // When: spinning the feedbacks and the reducer on the default executer
        let spin = Spinner
            .initialState("initialState")
            .feedback(Feedback(effect: effectA))
            .feedback(Feedback(effect: effectB))
            .feedback(Feedback(effect: effectC))
            .reducer(Reducer(reducerFunction))

        SignalProducer<String, Never>.stream(from: spin)
            .take(first: 7)
            .collect()
            .startWithValues({ (states) in
                receivedStates = states
                exp.fulfill()
            })
            .disposed(by: self.disposeBag)

        waitForExpectations(timeout: 5)

        // Then: the states is constructed incrementally
        XCTAssertEqual(receivedStates, ["initialState",
                                        "initialState_a1",
                                        "initialState_a1_b1",
                                        "initialState_a1_b1_c1",
                                        "initialState_a1_b1_c1_a2",
                                        "initialState_a1_b1_c1_a2_b2",
                                        "initialState_a1_b1_c1_a2_b2_c2"])
    }

    func test_multiple_feedbacks_produces_incremental_states_while_executed_on_default_executer_using_declarative_syntax() throws {
        let exp = expectation(description: "incremental states")
        var receivedStates = [String]()

        // Given: an initial state, feedbacks and a reducer
        var counterA = 0
        let effectA = { (state: String) -> SignalProducer<StringAction, Never> in
            counterA += 1
            let counter = counterA
            return SignalProducer<StringAction, Never>(value: .append("_a\(counter)"))
        }

        var counterB = 0
        let effectB = { (state: String) -> SignalProducer<StringAction, Never> in
            counterB += 1
            let counter = counterB
            return SignalProducer<StringAction, Never>(value: .append("_b\(counter)"))
        }

        var counterC = 0
        let effectC = { (state: String) -> SignalProducer<StringAction, Never> in
            counterC += 1
            let counter = counterC
            return SignalProducer<StringAction, Never>(value: .append("_c\(counter)"))
        }

        let reducerFunction = { (state: String, action: StringAction) -> String in
            switch action {
            case .append(let suffix):
                return state+suffix
            }
        }

        let spin = Spin<String, StringAction>(initialState: "initialState") {
            Feedback(effect: effectA).execute(on: QueueScheduler.main)
            Feedback(effect: effectB).execute(on: QueueScheduler.main)
            Feedback(effect: effectC).execute(on: QueueScheduler.main)
            Reducer(reducerFunction)
        }

        // When: spinning the feedbacks and the reducer on the default executer
        SignalProducer<String, Never>.stream(from: spin)
            .take(first: 7)
            .collect()
            .startWithValues({ (states) in
                receivedStates = states
                exp.fulfill()
            })
            .disposed(by: self.disposeBag)

        waitForExpectations(timeout: 5)

        // Then: the states is constructed incrementally
        XCTAssertEqual(receivedStates, ["initialState",
                                        "initialState_a1",
                                        "initialState_a1_b1",
                                        "initialState_a1_b1_c1",
                                        "initialState_a1_b1_c1_a2",
                                        "initialState_a1_b1_c1_a2_b2",
                                        "initialState_a1_b1_c1_a2_b2_c2"])
    }
}

extension SpinIntegrationTests {
    ////////////////////////////////////////////////////////////////
    // CHECK AUTHORIZATION SPIN
    ///////////////////////////////////////////////////////////////

    // events:    checkAuthorization                 revokeUser
    //                   ↓                               ↓
    // states:   initial -> AuthorizationShouldBeChecked -> userHasBeenRevoked

    private enum CheckAuthorizationSpinState: Equatable {
        case initial
        case authorizationShouldBeChecked
        case userHasBeenRevoked
    }

    private enum CheckAuthorizationSpinEvent {
        case checkAuthorization
        case revokeUser
    }

    ////////////////////////////////////////////////////////////////
    // FETCH FEATURE FEEDBACKLOOP
    ///////////////////////////////////////////////////////////////

    // events:   userIsNotAuthorized
    //                  ↓
    // states:  initial -> unauthorized

    private enum FetchFeatureSpinState: Equatable {
        case initial
        case unauthorized
    }

    private enum FetchFeatureSpinEvent {
        case userIsNotAuthorized
    }

    ////////////////////////////////////////////////////////////////
    // Gear
    ///////////////////////////////////////////////////////////////

    private enum GearEvent {
        case authorizedIssueDetected
    }

    func testAttach_trigger_checkAuthorizationSpin_when_fetchFeatureSpin_trigger_gear() {
        let exp = expectation(description: "Gear")

        var receivedStates = [Any]()

        // Given: 2 independents spins and a shared gear
        let gear = Gear<GearEvent>()
        let fetchFeatureSpin = self.makeFetchFeatureSpin(attachedTo: gear)
        let checkAuthorizationSpin = self.makeCheckAuthorizationSpin(attachedTo: gear)

        // When: executing the 2 spins
        SignalProducer
            .stream(from: checkAuthorizationSpin)
            .startWithValues({ state in
                receivedStates.append(state)
                if state == .userHasBeenRevoked {
                    exp.fulfill()
                }
            })
            .disposed(by: self.disposeBag)

        SignalProducer
            .stream(from:fetchFeatureSpin)
            .startWithValues({ state in
                receivedStates.append(state)
            }).disposed(by: self.disposeBag)

        waitForExpectations(timeout: 0.5)

        // Then: the stream of states produced by the spins are the expected one thanks to the propagation of the gear
        XCTAssertEqual(receivedStates[0] as? CheckAuthorizationSpinState, CheckAuthorizationSpinState.initial)
        XCTAssertEqual(receivedStates[1] as? FetchFeatureSpinState, FetchFeatureSpinState.initial)
        XCTAssertEqual(receivedStates[2] as? FetchFeatureSpinState, FetchFeatureSpinState.unauthorized)
        XCTAssertEqual(receivedStates[3] as? CheckAuthorizationSpinState, CheckAuthorizationSpinState.authorizationShouldBeChecked)
        XCTAssertEqual(receivedStates[4] as? CheckAuthorizationSpinState, CheckAuthorizationSpinState.userHasBeenRevoked)
    }
}

private extension SpinIntegrationTests {
    private func makeCheckAuthorizationSpin(attachedTo gear: Gear<GearEvent>) -> Spin<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent> {
        let checkAuthorizationSpinReducer: (CheckAuthorizationSpinState, CheckAuthorizationSpinEvent) -> CheckAuthorizationSpinState = { state, event in
            switch (state, event) {
            case (.initial, .checkAuthorization):
                return .authorizationShouldBeChecked
            case (.authorizationShouldBeChecked, .revokeUser):
                return .userHasBeenRevoked
            default:
                return state
            }
        }

        let checkAuthorizationSideEffect: (CheckAuthorizationSpinState) -> SignalProducer<CheckAuthorizationSpinEvent, Never> = { state in
            guard state == .authorizationShouldBeChecked else { return .empty }
            return SignalProducer<CheckAuthorizationSpinEvent, Never>(value: .revokeUser)
        }

        let attachedCheckAuthorizationFeedback = Feedback<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent>(attachTo: gear,
                                                                                                                    propagating: { (event: GearEvent) in
                                                                                                                        if event == .authorizedIssueDetected {
                                                                                                                            return CheckAuthorizationSpinEvent.checkAuthorization
                                                                                                                        }
                                                                                                                        return nil
        })

        let spin = Spin<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent>(initialState: .initial) {
            Feedback<CheckAuthorizationSpinState, CheckAuthorizationSpinEvent>(effect: checkAuthorizationSideEffect)
            attachedCheckAuthorizationFeedback
            Reducer(checkAuthorizationSpinReducer)
        }

        return spin
    }

    private func makeFetchFeatureSpin(attachedTo gear: Gear<GearEvent>) -> Spin<FetchFeatureSpinState, FetchFeatureSpinEvent> {
        let fetchFeatureSpinReducer: (FetchFeatureSpinState, FetchFeatureSpinEvent) -> FetchFeatureSpinState = { state, event in
            switch (state, event) {
            case (.initial, .userIsNotAuthorized):
                return .unauthorized
            default:
                return state
            }
        }

        let fetchFeatureSideEffect: (FetchFeatureSpinState) -> SignalProducer<FetchFeatureSpinEvent, Never> = { state in
            guard state == .initial else { return .empty }
            return SignalProducer<FetchFeatureSpinEvent, Never>(value: .userIsNotAuthorized)
        }

        let attachedFetchFeatureFeedback = Feedback<FetchFeatureSpinState, FetchFeatureSpinEvent>(attachTo: gear,
                                                                                                  propagating: { (state: FetchFeatureSpinState) in
                                                                                                    if state == .unauthorized {
                                                                                                        return GearEvent.authorizedIssueDetected
                                                                                                    }
                                                                                                    return nil
        })

        let spin = Spin<FetchFeatureSpinState, FetchFeatureSpinEvent>(initialState: .initial) {
            Feedback<FetchFeatureSpinState, FetchFeatureSpinEvent>(effect: fetchFeatureSideEffect)
            attachedFetchFeatureFeedback
            Reducer(fetchFeatureSpinReducer)
        }

        return spin
    }
}
