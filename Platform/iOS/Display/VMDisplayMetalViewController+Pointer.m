//
// Copyright © 2020 osy. All rights reserved.
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

#import "VMDisplayMetalViewController.h"
#import "VMDisplayMetalViewController+Private.h"
#import "VMDisplayMetalViewController+Touch.h"
#import "VMDisplayMetalViewController+Pointer.h"
#import "VMCursor.h"
#import "CSDisplay.h"
#import "VMScroll.h"
#import "UTMLogging.h"
#import "UTM-Swift.h"

@interface VMDisplayMetalViewController ()

- (BOOL)switchMouseType:(VMMouseType)type; // defined in VMDisplayMetalViewController+Touch.m

@end

@implementation VMDisplayMetalViewController (Pointer)

#pragma mark - GCMouse

- (void)startGCMouse {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(mouseDidBecomeCurrent:) name:GCMouseDidBecomeCurrentNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(mouseDidStopBeingCurrent:) name:GCMouseDidStopBeingCurrentNotification object:nil];
    GCMouse *current = GCMouse.current;
    if (current) {
        // send the current mouse if already connected
        [NSNotificationCenter.defaultCenter postNotificationName:GCMouseDidBecomeCurrentNotification object:current];
    }
}

- (void)stopGCMouse {
    GCMouse *current = GCMouse.current;
    [NSNotificationCenter.defaultCenter removeObserver:self name:GCMouseDidBecomeCurrentNotification object:nil];
    if (current) {
        // send the current mouse if already connected
        [NSNotificationCenter.defaultCenter postNotificationName:GCMouseDidStopBeingCurrentNotification object:current];
    }
    [NSNotificationCenter.defaultCenter removeObserver:self name:GCMouseDidStopBeingCurrentNotification object:nil];
}

- (void)mouseDidBecomeCurrent:(NSNotification *)notification {
    GCMouse *mouse = notification.object;
    UTMLog(@"mouseDidBecomeCurrent: %p", mouse);
    if (!mouse) {
        UTMLog(@"invalid mouse object!");
        return;
    }
    // GCMouse speaks for the device only while the pointer is locked. Unlocked, the same movement and the
    // same buttons also arrive as the system's pointer (regionForRequest, the indirect touches), which
    // positions the guest's cursor; GCMouse reported them as well on an M4 iPad, each movement then asked
    // for the relative mouse and the pointer for the tablet, and the guest's pointer device was switched
    // up to 150 times a second, with every button sent twice (debug.log, 2026-10-13).
    mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput * _Nonnull mouse, float deltaX, float deltaY) {
        if (!self.isPointerLocked) {
            return;
        }
        [self switchMouseType:VMMouseTypeRelative];
        [self.vmInput sendMouseMotion:self.mouseButtonDown relativePoint:CGPointMake(deltaX, -deltaY)];
    };
    mouse.mouseInput.leftButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        if (!self.isPointerLocked) {
            return;
        }
        self.mouseLeftDown = pressed;
        [self.vmInput sendMouseButton:kCSInputButtonLeft mask:self.mouseButtonDown pressed:pressed];
    };
    mouse.mouseInput.rightButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        if (!self.isPointerLocked) {
            return;
        }
        self.mouseRightDown = pressed;
        [self.vmInput sendMouseButton:kCSInputButtonRight mask:self.mouseButtonDown pressed:pressed];

    };
    mouse.mouseInput.middleButton.pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
        if (!self.isPointerLocked) {
            return;
        }
        self.mouseMiddleDown = pressed;
        [self.vmInput sendMouseButton:kCSInputButtonMiddle mask:self.mouseButtonDown pressed:pressed];
    };
    for (int i = 0; i < MIN(2, mouse.mouseInput.auxiliaryButtons.count); i++) {
        mouse.mouseInput.auxiliaryButtons[i].pressedChangedHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
            switch (i) {
                case 0: self.mouseSideDown = pressed; [self.vmInput sendMouseButton:kCSInputButtonSide mask:self.mouseButtonDown pressed:pressed]; break;
                case 1: self.mouseExtraDown = pressed; [self.vmInput sendMouseButton:kCSInputButtonExtra mask:self.mouseButtonDown pressed:pressed]; break;
                default: break;
            }
        };
    }
    // no handler to the gcmouse scroll event, gestureScroll works fine.
}

- (void)mouseDidStopBeingCurrent:(NSNotification *)notification {
    GCMouse *mouse = notification.object;
    UTMLog(@"mouseDidStopBeingCurrent: %p", mouse);
    mouse.mouseInput.mouseMovedHandler = nil;
    mouse.mouseInput.leftButton.pressedChangedHandler = nil;
    mouse.mouseInput.rightButton.pressedChangedHandler = nil;
    mouse.mouseInput.middleButton.pressedChangedHandler = nil;
    for (int i = 0; i < MIN(4, mouse.mouseInput.auxiliaryButtons.count); i++) {
        mouse.mouseInput.auxiliaryButtons[i].pressedChangedHandler = nil;
    }
}

#pragma mark - Pointer lock

// A mouse or trackpad reaches the VM in one of two ways. With the pointer locked the system hides its own
// pointer and GCMouse reports movement, which goes to the guest as a relative mouse. The system grants the
// lock only to a scene that is full screen and frontmost, and says nothing when it does not: GCMouse then
// reported no movement at all (it can: see mouseDidBecomeCurrent), and with indirect touches ignored (as
// they must be under the lock) the device did nothing. So what counts is the lock the system reports, not
// the one asked for: without it the pointer is the system's own and drives the guest's cursor by position,
// the way visionOS always has, and GCMouse is not listened to.
//
// And that is the default here. UTM asks for the lock whenever a VM runs; on an M4 iPad with a keyboard's
// trackpad that left the trackpad dead (2026-10-12: GCMouse devices came and went in the log and not one
// movement arrived). A pointer that positions the cursor needs no lock, works in a window as well as full
// screen, and is what a desktop guest wants. Capture is for a guest without a tablet, which has no other
// way, and for whoever asks (a game that reads relative movement).

- (BOOL)wantsPointerLock {
    return self.delegate.qemuInputLegacy || [self boolForSetting:@"MouseIndirectCapture"];
}

- (BOOL)isPointerLocked {
#if TARGET_OS_VISION
    return NO;
#else
    return self.view.window.windowScene.pointerLockState.locked;
#endif
}

- (void)pointerLockStateDidChange:(NSNotification *)notification {
    BOOL locked = self.isPointerLocked;
    BOOL fillsScreen = NO;
#if !TARGET_OS_VISION
    UIWindow *window = self.view.window;
    fillsScreen = window && CGSizeEqualToSize(window.windowScene.coordinateSpace.bounds.size, window.screen.bounds.size);
#endif
    UTMLog(@"pointer lock: %@ (asked: %d, scene fills the screen: %d, GCMouse: %p)",
           locked ? @"locked, the mouse is relative" : @"not locked, the pointer moves the cursor by position",
           self.prefersPointerLocked, fillsScreen, GCMouse.current);
    self.view.window.isIndirectPointerTouchIgnored = locked;
    for (id<UIInteraction> interaction in self.mtkView.interactions) {
        if ([interaction isKindOfClass:[UIPointerInteraction class]]) {
            [(UIPointerInteraction *)interaction invalidate];
        }
    }
}

- (void)startObservingPointerLock {
#if !TARGET_OS_VISION
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIPointerLockStateDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pointerLockStateDidChange:) name:UIPointerLockStateDidChangeNotification object:nil];
#endif
    [self pointerLockStateDidChange:nil];
    // (the system decides after the run loop turns, and announces only a change)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.prefersPointerLocked) {
            [self pointerLockStateDidChange:nil];
        }
    });
}

- (void)stopObservingPointerLock {
#if !TARGET_OS_VISION
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIPointerLockStateDidChangeNotification object:nil];
#endif
    self.view.window.isIndirectPointerTouchIgnored = NO;
}

#pragma mark - UIPointerInteractionDelegate

// Add pointer interaction to VM view
-(void)initPointerInteraction {
    [self.mtkView addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
    
    UIPanGestureRecognizer *scroll = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(gestureScroll:)];
    scroll.allowedScrollTypesMask = UIScrollTypeMaskAll;
    scroll.minimumNumberOfTouches = 0;
    scroll.maximumNumberOfTouches = 0;
    [self.mtkView addGestureRecognizer:scroll];
}

- (BOOL)hasTouchpadPointer {
    return !self.delegate.qemuInputLegacy && !self.vmInput.serverModeCursor && self.indirectMouseType != VMMouseTypeRelative;
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region {
    // Hide cursor while hovering in VM view
    if (interaction.view == self.mtkView && self.hasTouchpadPointer) {
#if TARGET_OS_VISION
        return nil; // FIXME: hidden pointer seems to jump around due to following gaze
#else
        return [UIPointerStyle hiddenPointerStyle];
#endif
    }
    return nil;
}

- (bool)isPointOnVMDisplay:(CGPoint)pos {
    CGSize screenSize = self.mtkView.drawableSize;
    CGSize scaledSize = {
        self.vmDisplay.displaySize.width * self.renderer.viewportScale,
        self.vmDisplay.displaySize.height * self.renderer.viewportScale
    };
    CGRect drawRect = CGRectMake(
        self.renderer.viewportOrigin.x + screenSize.width/2 - scaledSize.width/2,
        self.renderer.viewportOrigin.y + screenSize.height/2 - scaledSize.height/2,
        scaledSize.width,
        scaledSize.height
    );
    pos.x -= drawRect.origin.x;
    pos.y -= drawRect.origin.y;
    return 0 <= pos.x && pos.x <= scaledSize.width && 0 <= pos.y && pos.y <= scaledSize.height;
}


- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction regionForRequest:(UIPointerRegionRequest *)request defaultRegion:(UIPointerRegion *)defaultRegion {
#if !TARGET_OS_VISION
    if (self.isPointerLocked) {
        return nil;
    }
    // Not locked: the system's pointer positions the guest's cursor, which takes the tablet. A guest left
    // on its relative mouse (a finger dragging the cursor, or a desktop that opened the mouse last) is
    // asked over; the pointer takes effect once it has switched.
    if (interaction.view == self.mtkView && !self.delegate.qemuInputLegacy && self.vmInput.serverModeCursor) {
        [self switchMouseType:VMMouseTypeAbsolute];
        return nil;
    }
#endif
    // Requesting region for the VM display?
    if (interaction.view == self.mtkView && self.hasTouchpadPointer) {
        // Then we need to find out if the pointer is in the actual display area or outside
        CGPoint location = [self.mtkView convertPoint:[request location] fromView:nil];
        CGPoint translated = location;
        translated.x = CGPointToPixel(self.view, translated.x);
        translated.y = CGPointToPixel(self.view, translated.y);
        
        if ([self isPointOnVMDisplay:translated]) {
            // move vm cursor, hide iOS cursor
            [self.cursor updateMovement:location];
            return [UIPointerRegion regionWithRect:[self.mtkView bounds] identifier:@"vm view"];
        } else {
            // don't move vm cursor, show iOS cursor
            return nil;
        }
    } else {
        return nil;
    }
}

#pragma mark - Scroll Gesture

- (IBAction)gestureScroll:(UIPanGestureRecognizer *)sender {
    [self scrollWithInertia:sender];
}

@end
