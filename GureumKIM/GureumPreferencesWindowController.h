//
//  GureumPreferencesWindowController.h
//  CharmIM
//
//  Created by youknowone on 11. 9. 22..
//  Copyright 2011 youknowone.org. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SRRecorderCell;

@interface GureumPreferencesWindowController : NSWindowController<NSWindowDelegate, NSToolbarDelegate, NSComboBoxDataSource> {
@private
    IBOutlet NSView *preferenceContainerView;
    IBOutlet NSView *commonButtonsView;
    IBOutlet NSView *gureumPreferenceView, *hangulPreferenceView;
    NSDictionary *preferenceViews;
    BOOL cancel;
    
    /* Gureum Preferences */
    IBOutlet SRRecorderCell *inputModeExchangeKeyRecorderCell;
    IBOutlet NSButton *autosaveDefaultInputModeCheckbox;
    IBOutlet NSComboBox *defaultHangulInputModeComboBox;
    
    IBOutlet NSButton *romanModeByEscapeKeyCheckbox;
 
    /* Hangul Preferences */
    IBOutlet NSComboBox *hangulCombinationModeComposingComboBox;
    IBOutlet NSComboBox *hangulCombinationModeCommitingComboBox;
}

- (IBAction)saveToConfiguration:(id)sender;
- (IBAction)selectPreferenceItem:(id)sender;
- (IBAction)cancelAndClose:(id)sender;

@end