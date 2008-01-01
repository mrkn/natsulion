#import "Twitter.h"
#import "TwitterStatus.h"

@implementation TwitterPostCallbackHandler

- (id) initWithCallback:(id<TwitterPostInternalCallback>)callback {
    _callback = callback;
    return self;
}

- (void) responseArrived:(NSData*)response statusCode:(int)code {
    [_callback finishedToPost];
//    NSString *responseStr = [NSString stringWithCString:[response bytes] encoding:NSUTF8StringEncoding];
//    NSLog(@"post responseArrived:%@", responseStr);
}

- (void) connectionFailed:(NSError*)error {
    [_callback failedToPost:[error localizedDescription]];
}

@end


@implementation Twitter

// internal 
- (NSArray*) arrayWithSet:(NSSet*)set {
    NSMutableArray* array = [[[NSMutableArray alloc] initWithCapacity:10] autorelease];
    
    NSEnumerator *e = [set objectEnumerator];
    id i = [e nextObject];
    while (i) {
        [array addObject:i];
        i = [e nextObject];
    }
    
    return array;
}

- (void) updateDownloadStatus {
    if (_postingMessage || _downloadingTimeline || [_waitingIconTwitterStatuses count] > 0) {
        [_friendTimelineCallback started];
    }
    
    if (!_postingMessage && !_downloadingTimeline && [_waitingIconTwitterStatuses count] == 0) {
        [_friendTimelineCallback stopped];
    }
}

- (void) startDownloading {
    _downloadingTimeline = TRUE;
    [self updateDownloadStatus];
}

- (void) stopDownloading {
    _downloadingTimeline = FALSE;
    [self updateDownloadStatus];
}

- (void) startPosting {
    _postingMessage = TRUE;
    [self updateDownloadStatus];
}

- (void) stopPosting {
    _postingMessage = FALSE;
    [self updateDownloadStatus];
}


- (void) finishWaiting:(NSString*)key {
    [_waitingIconTwitterStatuses removeObjectForKey:key];
    [self updateDownloadStatus];
}


- (NSString*) stringValueFromNSXMLNode:(NSXMLNode*)node byXPath:(NSString*)xpath {
    NSArray *nodes = [node nodesForXPath:xpath error:NULL];
    if ([nodes count] != 1) {
        return nil;
    }
    return [(NSXMLNode *)[nodes objectAtIndex:0] stringValue];
}

- (NSString*) convertToLargeIconUrl:(NSString*)url {
    return url;
    
    //    // [@"_normal.jpg" length] = 11
    //    int loc = [url length] - 11;
    //    NSRange normalSuffixRange;
    //    normalSuffixRange.location = loc;
    //    normalSuffixRange.length = 7; // "_normal"
    //    NSString *suffix = [url substringWithRange:normalSuffixRange];
    //    if ([suffix isEqualToString:@"_normal"]) {
    //        NSMutableString *u = [url mutableCopy];
    //        NSRange r;
    //        r.location = loc;
    //        r.length = 7;
    //        [u deleteCharactersInRange:r];
    //        [u insertString:@"_bigger" atIndex:loc];
    //        return u;
    //    }
    //
    //    return url;
}

////////////////////////////////////////////////////////////////////
- (id) init {
    [super init];
    _waitingIconTwitterStatuses = [[NSMutableDictionary alloc] initWithCapacity:100];
    _iconRepository = [[IconRepository alloc] initWithCallback:self];
    return self;
}

- (void) dealloc {
    if (_friendTimelineCallback) {
        [_friendTimelineCallback release];
    }
    [_waitingIconTwitterStatuses release];
    [_iconRepository release];
    [super dealloc];
}

////////////////////////////////////////////////////////////////////
- (void) friendTimelineWithUsername:(NSString*)username password:(NSString*)password callback:(NSObject<TimelineCallback>*)callback {
    
    if (_friendTimelineCallback) {
        NSLog(@"friendTimelineWithCallback: called while running");
    }
    [_friendTimelineCallback release];
    _friendTimelineCallback = callback;
    [_friendTimelineCallback retain];
    
    AsyncUrlConnection *connection = [[AsyncUrlConnection alloc] initWithUrl:@"http://twitter.com/statuses/friends_timeline.xml" 
                                                                    username:username
                                                                    password:password
                                                                    callback:self];
    if (!connection) {
        NSLog(@"failed to get connection.");
        return;
    }

    [self startDownloading];

    NSLog(@"sending friend timeline request.");
    
}

- (void) responseArrived:(NSData*)response statusCode:(int)code {

    [self stopDownloading];

    NSString *responseStr = [NSString stringWithCString:[response bytes] encoding:NSUTF8StringEncoding];
    
//    NSLog(@"responseArrived:%@", responseStr);
    
    NSXMLDocument *document;
    
    document = [[[NSXMLDocument alloc] initWithXMLString:responseStr options:0 error:NULL] autorelease];
    if (!document) {
        NSLog(@"parse error");
        NSLog(@"responseArrived:%@", responseStr);
        
        [_friendTimelineCallback failedToGetTimeline:@"This error might be caused by API limitation."];
        return;
    }
    
    NSArray *statuses = [document nodesForXPath:@"/statuses/status" error:NULL];
    for (NSXMLNode *status in statuses) {
        TwitterStatus *backStatus = [[[TwitterStatus alloc] init] autorelease];
        
        [backStatus setStatusId:[self stringValueFromNSXMLNode:status byXPath:@"id/text()"]];
        [backStatus setName:[self stringValueFromNSXMLNode:status byXPath:@"user/name/text()"]];
        [backStatus setScreenName:[self stringValueFromNSXMLNode:status byXPath:@"user/screen_name/text()"]];
        [backStatus setText:[self stringValueFromNSXMLNode:status byXPath:@"text/text()"]];
        [backStatus setTimestamp:[NSDate dateWithNaturalLanguageString:[self stringValueFromNSXMLNode:status byXPath:@"created_at/text()"]]];

        NSString *iconUrl = [self convertToLargeIconUrl:[self stringValueFromNSXMLNode:status byXPath:@"user/profile_image_url/text()"]];
        
        NSMutableSet *set = [_waitingIconTwitterStatuses objectForKey:iconUrl];
        if (!set) {
            set = [[[NSMutableSet alloc] initWithCapacity:3] autorelease];
            [_waitingIconTwitterStatuses setObject:set forKey:iconUrl];
        }
        
        [backStatus finishedToSetProperties];
        
        [set addObject:backStatus];
        [_iconRepository registerUrl:iconUrl];
        
//        NSLog(@"%@, %@", [backStatus statusId], [backStatus name]);
    }

}

- (void) connectionFailed:(NSError*)error {
    [_friendTimelineCallback failedToGetTimeline:[error localizedDescription]];
}

- (void) sendMessage:(NSString*)message username:(NSString*)username password:(NSString*)password callback:(NSObject<TwitterPostCallback>*)callback {
    
    if (_twitterPostCallback) {
        NSLog(@"sendMessageWithCallback: called while running");
    }
    [_twitterPostCallback release];
    _twitterPostCallback = callback;
    [_twitterPostCallback retain];
    
    TwitterPostCallbackHandler *handler = [[[TwitterPostCallbackHandler alloc] initWithCallback:self] autorelease];
    NSString *requestStr =  [@"status=" stringByAppendingString:message];
    requestStr = [requestStr stringByAppendingString:@"&source=NatsuLion"];
    AsyncUrlConnection *connection = [[[AsyncUrlConnection alloc] initPostConnectionWithUrl:@"http://twitter.com/statuses/update.xml"
                                                                                 bodyString:requestStr 
                                                                                   username:username
                                                                                   password:password
                                                                                   callback:handler] autorelease];
    
    NSLog(@"sent data [%@]", requestStr);
    
    if (!connection) {
        [_twitterPostCallback failedToPost:@"Posting a message failure. unable to get connection."];
        [_twitterPostCallback release];
        _twitterPostCallback = nil;
        return;
    }

    [self startPosting];
//    NSLog(@"sending post status request.");
}


// TwitterPostInternalCallback method /////////////////////////////////////////////////
- (void) finishedToPost {
    [self stopPosting];
    [_twitterPostCallback finishedToPost];
    [_twitterPostCallback release];
    _twitterPostCallback = nil;
}

- (void) failedToPost:(NSString*)message {
    [self stopPosting];
    [_twitterPostCallback failedToPost:message];
    [_twitterPostCallback release];
    _twitterPostCallback = nil;
}

// /////////////////////////////////////////////////////////////////////////////
- (void) finishedToGetIcon:(NSImage*)icon forKey:(NSString*)key {
    NSMutableArray *back = [[[NSMutableArray alloc] initWithCapacity:20] autorelease];

    NSSet* set = [_waitingIconTwitterStatuses objectForKey:key];
    NSEnumerator *e = [set objectEnumerator];
    TwitterStatus *s = [e nextObject];
    while (s) {
        NSSize size;
        size.width = 48;
        size.height = 48;
        [icon setSize:size];
        [s setIcon:icon];
        [back addObject:s];
        s = [e nextObject];        
    }
    
    [self finishWaiting:key];
    [_friendTimelineCallback finishedToGetTimeline:back];
}

- (void) failedToGetIconForKey:(NSString*)key {
    NSMutableArray *back = [[[NSMutableArray alloc] initWithCapacity:20] autorelease];
    [back addObjectsFromArray:[self arrayWithSet:[_waitingIconTwitterStatuses objectForKey:key]]];

    [self finishWaiting:key];
    [_friendTimelineCallback finishedToGetTimeline:back];
}


@end

///////////////////////////////////////////


@implementation TwitterCheck

- (void) checkAuthentication:(NSString*)username password:(NSString*)password callback:(NSObject<TwitterCheckCallback>*)callback {

    _callback = callback;
    [_callback retain];
    
    _connection = [[AsyncUrlConnection alloc] initWithUrl:@"http://twitter.com/account/verify_credentials.xml" 
                                                username:username
                                                password:password
                                                callback:self];
    if (!_connection) {
        NSLog(@"failed to get connection.");
        [_callback finishedToCheck:NTLN_TWITTERCHECK_FAILURE];
    }
}

- (void) dealloc {
    [_callback release];
    [_connection release];
    [super dealloc];
}

- (void) responseArrived:(NSData*)response statusCode:(int)code {
    switch (code) {
        case 200:
            [_callback finishedToCheck:NTLN_TWITTERCHECK_SUCESS];
            break;
            
        case 401:
            [_callback finishedToCheck:NTLN_TWITTERCHECK_AUTH_FAILURE];
            break;
            
        default:
            [_callback finishedToCheck:NTLN_TWITTERCHECK_FAILURE];
            NSLog(@"%s: code=%d", __PRETTY_FUNCTION__, code);
            break;
    }
}

- (void) connectionFailed: (NSError*)error {
    [_callback finishedToCheck:NTLN_TWITTERCHECK_FAILURE];
}

@end
