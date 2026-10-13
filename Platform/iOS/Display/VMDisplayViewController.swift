//
// Copyright © 2021 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import SwiftUI

private var memoryAlertOnce = false

@objc public extension VMDisplayViewController {
    var runInBackground: Bool {
        boolForSetting("RunInBackground")
    }
    
    var disableIdleTimer: Bool {
        boolForSetting("DisableIdleTimer")
    }
}

// MARK: - View Loading
public extension VMDisplayViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    /// UIKit asks the window's root view controller who decides on the pointer lock and the home indicator,
    /// and follows the answers down. SwiftUI's controllers answer nobody, so UTMPatches lets each be told
    /// its child for the purpose. Telling only our parent reaches us when the parent is the root; with any
    /// controller in between (a navigation stack, whatever a later SwiftUI puts there) the chain broke at
    /// the root, the pointer was never locked, and a trackpad did nothing at all: GCMouse reports movement
    /// only under the lock. So every ancestor is told the child that leads here.
    private func setLockChain(_ on: Bool) {
        var child: UIViewController = self
        var ancestor = parent
        while let a = ancestor {
            a.setChildForHomeIndicatorAutoHidden(on ? child : nil)
            a.setChildViewControllerForPointerLock(on ? child : nil)
            child = a
            ancestor = a.parent
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if parent != nil {
            setLockChain(false)
            UIPress.pressResponderOverride = nil
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if parent != nil {
            setLockChain(true)
            UIPress.pressResponderOverride = self
        }
        #if !os(visionOS) && WITH_LOCATION_BACKGROUND
        if runInBackground {
            logger.info("Start location tracking to enable running in background")
            UTMLocationManager.sharedInstance().startUpdatingLocation()
        }
        #endif
        delegate.displayDidAppear()
    }
}

@objc extension VMDisplayViewController {
    func enterSuspended(isBusy busy: Bool) {
        if !busy {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    func enterLive() {
        UIApplication.shared.isIdleTimerDisabled = disableIdleTimer
    }
}

// MARK: Toolbar hiding
public extension VMDisplayViewController {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch.type == .direct {
                delegate.displayDidAssertUserInteraction()
                break
            }
        }
        super.touchesBegan(touches, with: event)
    }
}

// MARK: Helper functions
@objc public extension VMDisplayViewController {
    /*
     - (void)onDelay:(float)delay action:(void (^)(void))block {
         dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC*0.1), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), block);
     }

     - (BOOL)boolForSetting:(NSString *)key {
         return [[NSUserDefaults standardUserDefaults] boolForKey:key];
     }

     - (NSInteger)integerForSetting:(NSString *)key {
         return [[NSUserDefaults standardUserDefaults] integerForKey:key];
     }
     */
    func onDelay(_ delay: Float, action: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(100), execute: action)
    }
    
    func boolForSetting(_ key: String) -> Bool {
        return UserDefaults.standard.bool(forKey: key)
    }
    
    func integerForSetting(_ key: String) -> Int {
        return UserDefaults.standard.integer(forKey: key)
    }

    @discardableResult
    func debounce(_ delaySeconds: Int, context: Any? = nil, action: @escaping () -> Void) -> Any {
        if context != nil {
            let previous = context as! DispatchWorkItem
            previous.cancel()
        }
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds), execute: item)
        return item
    }
}
