/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBHomeboardApplication.h"

#import "FBErrorBuilder.h"
#import "FBMathUtils.h"
#import "FBRunLoopSpinner.h"
#import "XCElementSnapshot+FBHelpers.h"
#import "XCElementSnapshot.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement+FBIsVisible.h"
#import "XCUIElement+FBUtilities.h"
#import "XCUIElement+FBTap.h"
#import "XCUIElement+FBScrolling.h"
#import "XCUIElement+FBTVFocuse.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"
#import "FBLogger.h"

#if TARGET_OS_IOS
NSString *const HOMEBOARD_BUNDLE_ID = @"com.apple.springboard";
#elif TARGET_OS_TV
NSString *const HOMEBOARD_BUNDLE_ID = @"com.apple.HeadBoard";
#endif

@implementation FBHomeboardApplication

+ (instancetype)fb_homeboard
{
  static FBHomeboardApplication *_homeboardApp;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _homeboardApp = [[FBHomeboardApplication alloc] initPrivateWithPath:nil bundleID:HOMEBOARD_BUNDLE_ID];
  });
  [_homeboardApp query];
  _homeboardApp.safeQueryResolutionEnabled = YES;
  [_homeboardApp resolve];
  return _homeboardApp;
}

- (BOOL)fb_openApplicationWithIdentifier:(NSString *)identifier error:(NSError **)error
{
#if TARGET_OS_IOS
  return [self fb_tapApplicationWithIdentifier:identifier error:error];
#else
  return [self fb_selectApplicationWithIdentifier:identifier error:error];
#endif
}

#if TARGET_OS_IOS

- (BOOL)fb_tapApplicationWithIdentifier:(NSString *)identifier error:(NSError **)error
{
  XCUIElementQuery *appElementsQuery = [[self descendantsMatchingType:XCUIElementTypeIcon] matchingIdentifier:identifier];
  NSArray<XCUIElement *> *matchedAppElements = [appElementsQuery allElementsBoundByIndex];
  if (0 == matchedAppElements.count) {
    return [[[FBErrorBuilder builder]
             withDescriptionFormat:@"Cannot locate Springboard icon for '%@' application", identifier]
            buildError:error];
  }
  // Select the most recent installed application if there are multiple matches
  XCUIElement *appElement = [matchedAppElements lastObject];
  if (!appElement.fb_isVisible) {
    CGRect startFrame = appElement.frame;
    NSString *errorDescription = [NSString stringWithFormat:@"Cannot scroll to Springboard icon for '%@' application", identifier];
    BOOL shouldSwipeToTheRight = startFrame.origin.x < 0;
    do {
      if (shouldSwipeToTheRight) {
        [self swipeRight];
      } else {
        [self swipeLeft];
      }

      BOOL isSwipeSuccessful = [appElement fb_waitUntilFrameIsStable] &&
      [[[[FBRunLoopSpinner new]
         timeout:1]
        timeoutErrorMessage:errorDescription]
       spinUntilTrue:^BOOL{
         return !FBRectFuzzyEqualToRect(startFrame, appElement.frame, FBDefaultFrameFuzzyThreshold);
       }
       error:error];
      if (!isSwipeSuccessful) {
        return NO;
      }
    } while (!appElement.fb_isVisible);
  }
  if (![appElement fb_tapWithError:error]) {
    return NO;
  }
  return
  [[[[FBRunLoopSpinner new]
     interval:0.3]
    timeoutErrorMessage:@"Timeout waiting for application to activate"]
   spinUntilTrue:^BOOL{
     FBApplication *activeApp = [FBApplication fb_activeApplication];
     return activeApp &&
     activeApp.processID != self.processID &&
     activeApp.fb_isVisible;
   } error:error];
}

#elif TARGET_OS_TV

- (BOOL)fb_selectApplicationWithIdentifier:(NSString *)identifier error:(NSError **)error
{
  XCUIElementQuery *appElementsQuery = [[self descendantsMatchingType:XCUIElementTypeIcon] matchingIdentifier:identifier];
  NSArray<XCUIElement *> *matchedAppElements = [appElementsQuery allElementsBoundByIndex];
  if (0 == matchedAppElements.count) {
    return [[[FBErrorBuilder builder]
             withDescriptionFormat:@"Cannot locate Headboard icon for '%@' application", identifier]
            buildError:error];
  }
  // Select the most recent installed application if there are multiple matches
  XCUIElement *appElement = [matchedAppElements lastObject];
  if (![appElement fb_selectWithError:error]) {
    return NO;
  }
  [[XCUIRemote sharedRemote] pressButton: XCUIRemoteButtonSelect];
  return
  [[[[FBRunLoopSpinner new]
     interval:0.3]
    timeoutErrorMessage:@"Timeout waiting for application to activate"]
   spinUntilTrue:^BOOL{
     FBApplication *activeApp = [FBApplication fb_activeApplication];
     return activeApp &&
     activeApp.processID != self.processID &&
     activeApp.fb_isVisible;
   } error:error];
}
#endif

- (BOOL)fb_waitUntilApplicationBoardIsVisible:(NSError **)error
{
  return
  [[[[FBRunLoopSpinner new]
     timeout:10.]
    timeoutErrorMessage:@"Timeout waiting until SpringBoard is visible"]
   spinUntilTrue:^BOOL{
     return self.fb_isApplicationBoardVisible;
   } error:error];
}

- (BOOL)fb_isApplicationBoardVisible
{
  [self resolve];
#if TARGET_OS_IOS
  // the dock (and other icons) don't seem to be consistently reported as
  // visible. esp on iOS 11 but also on 10.3.3
  return self.otherElements[@"Dock"].isEnabled;
#elif TARGET_OS_TV
  return self.collectionViews[@"GridCollectionView"].isEnabled;
#endif
}

@end
