#import <Cocoa/Cocoa.h>
#import "MessageTableViewController.h"
#import "Twitter.h"
#import "GrowlNotifier.h"
#import "AutoResizingTextField.h"

@interface MainWindowController : NSObject <TimelineCallback, TwitterPostCallback, AutoResizingTextFieldCallback> {
    IBOutlet NSWindow *mainWindow;
    IBOutlet MessageTableViewController *messageTableViewController;
    IBOutlet NSProgressIndicator *downloadProgress;
    IBOutlet AutoResizingTextField *messageTextField;
    
    IBOutlet NSArrayController *messageViewControllerArrayController;
    
    Twitter *_twitter;
    GrowlNotifier *_growl;
    int _messageTextFieldRow;
}

- (IBAction) sendMessage:(id) sender;

@end
