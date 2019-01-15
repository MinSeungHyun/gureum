//
//  InputMethodServer.swift
//  OSX
//
//  Created by yuaming on 2018. 9. 20..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Foundation
import InputMethodKit
import IOKit

let DEBUG_INPUT_SERVER = false
let DEBUG_INPUT_HANDLER = false
let DEBUG_IOKIT_EVENT = false

let CIMKeyMapLower = [
    "a", "s", "d", "f", "h", "g", "z", "x",
    "c", "v", nil, "b", "q", "w", "e", "r",
    "y", "t", "1", "2", "3", "4", "6", "5",
    "=", "9", "7", "-", "8", "0", "]", "o",
    "u", "[", "i", "p", nil, "l", "j", "'",
    "k", ";","\\", ",", "/", "n", "m", ".",
    nil, nil, "`",
]
// assert(keyMapLower.count == CIMKeyMapSize)

let CIMKeyMapUpper = [
    "A", "S", "D", "F", "H", "G", "Z", "X",
    "C", "V", nil, "B", "Q", "W", "E", "R",
    "Y", "T", "!", "@", "#", "$", "^", "%",
    "+", "(", "&", "_", "*", ")", "}", "O",
    "U", "{", "I", "P", nil, "L", "J", "\"",
    "K", ":", "|", "<", "?", "N", "M", ">",
    nil, nil, "~",
]

extension IMKServer {
    convenience init?(bundle: Bundle) {
        guard let connectionName = bundle.infoDictionary!["InputMethodConnectionName"] as? String else {
            return nil
        }
        self.init(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
    }
}

class IOKitty {
    var ref: IOKitty!

    let service: IOService
    let connect: IOConnect
    let manager: IOHIDManager
    private var defaultCapsLockState: Bool = false
    private var capsLockPressed: Bool = false

    init?() {
        guard let _service = try? IOService(name: kIOHIDSystemClass) else {
            return nil
        }
        guard let _connect = _service.open(owningTask: mach_task_self_, type: kIOHIDParamConnectType) else {
            return nil
        }

        service = _service
        connect = _connect

        manager = IOHIDManager.create()
        manager.setDeviceMatching(page: kHIDPage_GenericDesktop, usage: kHIDUsage_GD_Keyboard)
        manager.setInputValueMatching(min: kHIDUsage_KeyboardCapsLock, max: kHIDUsage_KeyboardCapsLock)

        ref = self
        // Set input value callback
        withUnsafeMutablePointer(to: &ref, {
            _self in
            manager.registerInputValueCallback({
                inContext, _, _, value in
                guard let inContext = inContext else {
                    dlog(DEBUG_IOKIT_EVENT, "IOKit callback inContext is nil")
                    return
                }
                let pressed = value.integerValue > 0
                dlog(DEBUG_IOKIT_EVENT, "caps lock pressed: \(pressed)")
                let _self = inContext.assumingMemoryBound(to: IOKitty.self).pointee
                if pressed {
                    _self.capsLockPressed = true
                    dlog(DEBUG_IOKIT_EVENT, "caps lock pressed set in context")
                }
                _self.connect.capsLockState = _self.defaultCapsLockState
            }, context: _self)
        })
        manager.schedule(runloop: .current, mode: .default)
        let r = manager.open()
        if r != 0 {
            dlog(DEBUG_IOKIT_EVENT, "IOHIDManagerOpen failed")
        }
    }

    deinit {
        manager.unschedule(runloop: .current, mode: .default)
        manager.unregisterInputValueCallback()
        let r = manager.close()
        assert(r == 0)
    }

    func testAndClearCapsLockState() -> Bool {
        let r = capsLockPressed
        capsLockPressed = false
        connect.capsLockState = defaultCapsLockState
        return r
    }
}

/*!
 @brief  공통적인 OSX의 입력기 구조를 다룬다.

 InputManager는 @ref CIMInputController 또는 테스트코드에 해당하는 외부에서 입력을 받아 입력기에서 처리 후 결과 값을 보관한다. 처리 후 그 결과를 확인하는 것은 사용자의 몫이다.

 IMKServer나 클라이언트와 무관하게 입력 값에 대해 출력 값을 생성해 내는 입력기. 입력 뿐만 아니라 여러 키보드 간 전환이나 입력기에 관한 단축키 등 입력기에 관한 모든 기능을 다룬다.

 @coclass    IMKServer CIMComposer
 */
// TODO: CIMInputTextDelegate를 제거하고 서버만 관리하도록 한다
public class InputMethodServer: CIMInputTextDelegate {
    public static let shared = InputMethodServer()
    //! @brief  현재 입력중인 서버
    let server: IMKServer
    //! @property
    let candidates: IMKCandidates
    //! @brief  입력기가 inputText: 문맥에 있는지 여부를 저장
    var inputting: Bool = false
    let io: IOKitty

    convenience init() {
        let bundle = Bundle.main
        var name = bundle.infoDictionary!["InputMethodConnectionName"] as! String
        #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                name += "_Test" + String(describing: Int.random(in: 0 ..< 0x10000))
            } else {
                name += "_Debug"
            }
        #endif

        self.init(name: name)
    }

    init(name: String) {
        dlog(DEBUG_INPUT_SERVER, "** InputMethodServer Init")

        server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
        candidates = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
        candidates.setSelectionKeysKeylayout(TISInputSource.currentKeyboardLayout())

        io = IOKitty()!
        dlog(DEBUG_INPUT_SERVER, "\t%@", description)
    }

    var description: String {
        return """
        <InputMethodServer server: "\(String(describing: self.server))" candidates: "\(String(describing: self.candidates))">
        """
    }

    // MARK: - IMKServerInputTextData

    // 일단 받은 입력은 모두 핸들러로 넘겨준다.
    func input(controller: CIMInputController, inputText string: String?, key keyCode: Int, modifiers flags: NSEvent.ModifierFlags, client sender: Any) -> CIMInputTextProcessResult {
        assert(controller.className.hasSuffix("InputController"))

        // 입력기용 특수 커맨드 처리
        var result = controller.composer.input(controller: controller, command: string, key: keyCode, modifiers: flags, client: sender)
        if result == .notProcessedAndNeedsCommit {
            return result
        }

        if result != .processed {
            // 옵션 키 변환 처리
            var string = string
            if flags.contains(.option) {
                let configuration = GureumConfiguration.shared
                dlog(DEBUG_INPUT_HANDLER, "option key: %ld", configuration.optionKeyBehavior)
                switch configuration.optionKeyBehavior {
                case 0:
                    // default
                    dlog(DEBUG_INPUT_HANDLER, " ** ESCAPE from option-key default behavior")
                    return .notProcessedAndNeedsCommit
                case 1:
                    // ignore
                    if keyCode < 0x33 {
                        if flags.contains(.capsLock) || flags.contains(.shift) {
                            string = CIMKeyMapUpper[keyCode] ?? string
                        } else {
                            string = CIMKeyMapLower[keyCode] ?? string
                        }
                    }
                default:
                    assert(false)
                }
            } else {
                if keyCode < 0x33 {
                    if flags.contains(.shift) {
                        string = CIMKeyMapUpper[keyCode] ?? string
                    } else {
                        string = CIMKeyMapLower[keyCode] ?? string
                    }
                }
            }

            // 특정 애플리케이션에서 커맨드/옵션/컨트롤 키 입력을 선점하지 못하는 문제를 회피한다
            if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
                dlog(DEBUG_INPUT_HANDLER, "-- CIMInputHandler -inputText: Command/Option key input / returned NO")
                return .notProcessedAndNeedsCommit
            }

            if string == nil {
                return .notProcessedAndNeedsCommit
            }

            result = controller.composer.input(controller: controller, inputText: string, key: keyCode, modifiers: flags, client: sender)
        }

        dlog(false, "******* FINAL STATE: %d", result.rawValue)
        // 합성 후보가 있다면 보여준다
        if controller.composer.hasCandidates {
            candidates.update()
            candidates.show(kIMKLocateCandidatesLeftHint)
        } else if candidates.isVisible() {
            candidates.hide()
        }
        return result
    }

    func controllerDidCommit(_ controller: CIMInputController) {
        if controller.composer.hasCandidates {
            candidates.update()
            candidates.show(kIMKLocateCandidatesLeftHint)
        } else if candidates.isVisible() {
            candidates.hide()
        }
    }
}