//
//  CapturedContextDetailScrollViewController.m
//  AccessiblePhotos
//
//  Created by 原田 丞 on 12/08/09.
//  Copyright (c) 2012年 IBM Research - Tokyo. All rights reserved.
//

#import "CapturedContextDetailScrollViewController.h"
#import "CapturedContext.h"
#import "CapturedContextGroupingNodeDataBase.h"
#import "CapturedContextDetailView.h"
#import "CapturedContextManager.h"

@interface CapturedContextDetailScrollViewController () <UIScrollViewDelegate, UIAlertViewDelegate, CapturedContextDetailViewDelegate>

@property (nonatomic, weak) IBOutlet UIScrollView *scrollView;
@property (nonatomic, readonly) CapturedContext *focusedCapturedContext;
@property (nonatomic, readonly) CapturedContextDetailView *centerPageViewCache;

- (IBAction)deleteButtonTapped:(id)sender;

@end

static const int kMaxCachedPageViewCount = 3; // should be odd

@implementation CapturedContextDetailScrollViewController
{
    NSArray *leafNodes;

    UINib *pageViewNib;
    NSMutableArray *pageViewsCache;
    int centerPageViewRelativeIndex;
    
    int centerPageViewPageIndex;
    
    double previousScrollOffset;
    
    BOOL isInFullScreenMode;
    bool messageDisappear;
    bool facebookDisappear;
}

@synthesize delegate;
@synthesize rootNode = _rootNode;
@synthesize focusedPageIndex = _focusedPageIndex;
@synthesize titleText;
@synthesize scrollView;
@synthesize emailButton;
@synthesize facebookButton;
@synthesize toolBar;
@synthesize mySLComposerSheet;

#pragma mark - Property accessor methods

- (void)setRootNode:(TreeNode *)rootNode
{
    _rootNode = rootNode;

    if (self.scrollView != nil)
    {
        [self refreshCapturedContextList];
    }
}

- (void)setFocusedPageIndex:(int)focusedPageIndex
{
    if (focusedPageIndex != _focusedPageIndex)
    {
        _focusedPageIndex = focusedPageIndex;
        [self shiftCenterPageViewTo:_focusedPageIndex];
    }    
}

- (CapturedContext *)focusedCapturedContext
{
    return [self capturedContextAtIndex:self.focusedPageIndex];
}

- (CapturedContextDetailView *)centerPageViewCache
{
    if (pageViewsCache.count > 0 && centerPageViewPageIndex < pageViewsCache.count)
    {
        id objectAtIndex = [pageViewsCache objectAtIndex:centerPageViewPageIndex];
        if (objectAtIndex != [NSNull null])
        {
            return (CapturedContextDetailView *)objectAtIndex;
        }
    }
    return nil;
}

#pragma mark - UIViewController overrides

- (void)awakeFromNib
{
    [super awakeFromNib];

    centerPageViewPageIndex = -1;
    pageViewsCache = [NSMutableArray new];
    
    pageViewNib = [UINib nibWithNibName:@"CapturedContextDetailView" bundle:nil];
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (self.rootNode == nil)
    {
        self.rootNode = [CapturedContextManager sharedManager].dateBasedGroupingRoot;
    }

    // create three funky nav bar buttons
    //UIBarButtonItem *one = [[UIBarButtonItem alloc]initWithTitle:@"Delete" style:UIBarButtonSystemItemTrash target:self action:@selector(deleteButtonTapped:)];
    UIBarButtonItem *delete = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteButtonTapped:)];
    UIBarButtonItem *facebook = [[UIBarButtonItem alloc] initWithTitle:@"Facebook" style:UIBarButtonItemStylePlain target:self action:@selector(facebookSend:)];
    UIBarButtonItem *email = [[UIBarButtonItem alloc] initWithTitle:@"Email" style:UIBarButtonItemStylePlain target:self action:@selector(emailSend:)];
    
    // create a spacer
    UIBarButtonItem *space = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:self action:nil];
    space.width = 10;
    
    NSArray *buttons = @[delete, space, facebook, space, email];
    
    self.navigationItem.rightBarButtonItems = buttons;
}

- (void)viewWillAppear:(BOOL)animated
{
    messageDisappear = false;
    facebookButton = false;
    NSLog(@"####################### CapturedContextDetailScrollViewController: viewWillAppear called");
    NSLog(@"  isMovingToParentViewController: %d  isBeingPresented: %d", self.isMovingToParentViewController, self.isBeingPresented);

    [super viewWillAppear:animated];

    [self refreshCapturedContextList];
  
    // DOn'T know why this is not working
//    // FIX: may not be desirable in ByMonth view
//    if (self.isMovingToParentViewController == NO)
//    {
//        self.focusedPageIndex = 0;
//    }
//    else
//    {
        [self shiftCenterPageViewTo:self.focusedPageIndex];
//    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self handleFocusedPageChanged];
}

- (void)viewWillDisappear:(BOOL)animated
{
    NSLog(@"####################### CapturedContextDetailScrollViewController: viewWillDisappear called");
    NSLog(@"  isMovingFromParentViewController: %d  isBeingDismissed: %d", self.isMovingFromParentViewController, self.isBeingDismissed);
    
    [super viewWillDisappear:animated];
    
    if (self.centerPageViewCache != nil)
    {
        [self.centerPageViewCache stopPlayingAudio];
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    if (!(messageDisappear || facebookDisappear))
    {
        [super viewDidDisappear:animated];
        
        if (self.isMovingFromParentViewController == NO)
        {
            // If we're switching to another tab in the parent tab bar controller,
            // pop out of the detail view.
            [self.navigationController popViewControllerAnimated:NO];
        }
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

#pragma mark - IBAction methods

- (IBAction)deleteButtonTapped:(id)sender
{
    if (self.centerPageViewCache != nil)
    {
        [self.centerPageViewCache stopPlayingAudio];
    }
    
    NSString *timestampString = [NSDateFormatter localizedStringFromDate:self.focusedCapturedContext.timestamp dateStyle:NSDateFormatterLongStyle timeStyle:NSDateFormatterLongStyle];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete current photo?"
                                                    message:[NSString stringWithFormat:@"Are you sure you want to delete the photo and audio taken at %@?", timestampString]
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Delete", nil];
    [alert show];
}

#pragma mark - Private instance methods

- (CapturedContext *)capturedContextAtIndex:(int)index
{
    if (leafNodes.count > 0 && index < leafNodes.count && index >= 0)
    {
        return ((CapturedContextGroupingNodeDataBase *)((TreeNode *)[leafNodes objectAtIndex:index]).data).capturedContext;
    }
    return nil;
}

- (void)resizePageViewsCache
{
    // First, resize as necessary
    if (pageViewsCache.count != leafNodes.count)
    {
        // Create a new array of the new size
        NSMutableArray *newPageViewsCache = [NSMutableArray arrayWithCapacity:leafNodes.count];
        
        // Copy over as much of existing elements as can fit in the new array.
        for (int i = 0; i < leafNodes.count; i++)
        {
            if (i < pageViewsCache.count)
            {
                [newPageViewsCache addObject:[pageViewsCache objectAtIndex:i]];
            }
            else
            {
                [newPageViewsCache addObject:[NSNull null]];
            }
        }
        pageViewsCache = newPageViewsCache;
    }
}

- (void)refreshCapturedContextList
{
    if (self.rootNode != nil)
    {
        leafNodes = self.rootNode.leafNodes;
        
        if (leafNodes.count == 0)
        {
            // No captured contexts
            [self.navigationController popViewControllerAnimated:YES];
        }
        else
        {
            [self resizePageViewsCache];
            [self resizeScrollView];
        }
    }
}

- (void)resizeScrollView
{
    if (self.scrollView != nil)
    {
        double pageWidth = self.scrollView.frame.size.width;
        double oldContentOffset = self.scrollView.contentOffset.x;
        double newContentOffset = self.focusedPageIndex * pageWidth;
        double newContentSizeWidth = pageWidth * leafNodes.count;
        
        self.scrollView.contentSize = CGSizeMake(newContentSizeWidth, self.scrollView.frame.size.height);

        if (pageWidth > 0 && newContentOffset > newContentSizeWidth - pageWidth)
        {
            // If the previously-focused page was beyond the newly available
            // page range, shift the focused page to the last page.
            self.focusedPageIndex = leafNodes.count - 1;
            newContentOffset = self.focusedPageIndex * pageWidth;
        }
        
        if (newContentOffset != oldContentOffset)
        {
            self.scrollView.contentOffset = CGPointMake(newContentOffset, 0);
            [self handleFocusedPageChanged];
        }
    }
}

- (void)reloadPageViewCacheAt:(int)pageViewPageIndex
{
    if (pageViewPageIndex < pageViewsCache.count)
    {
        id objectAtIndex = [pageViewsCache objectAtIndex:pageViewPageIndex];

        if (objectAtIndex != [NSNull null])
        {
            CapturedContextDetailView *pageViewCache = (CapturedContextDetailView *)objectAtIndex;
            pageViewCache.capturedContext = [self capturedContextAtIndex:pageViewPageIndex];
        }
        else
        {
            NSLog(@"ERROR: CapturedContextDetailScrollViewController: attempt to reload non-existant page view cache at page %d", (pageViewPageIndex + 1));
        }
    }
}

- (void)reloadPageViewsCacheFromCenterPage
{
    for (int i = 0; i < ceil(kMaxCachedPageViewCount / 2.0); i++)
    {
        [self reloadPageViewCacheAt:centerPageViewPageIndex + i];
    }
}

- (void)shiftCenterPageViewTo:(int)newCenterPageViewPageIndex
{
    int oldCenterPageViewPageIndex = centerPageViewPageIndex;

    if (oldCenterPageViewPageIndex == newCenterPageViewPageIndex)
    {
        return;
    }
    
    int oldLeftMostPageViewPageIndex = oldCenterPageViewPageIndex - floor(kMaxCachedPageViewCount / 2.0);
    int oldRightMostPageViewPageIndex = oldLeftMostPageViewPageIndex + kMaxCachedPageViewCount - 1;
    
    if (oldCenterPageViewPageIndex < 0)
    {
        oldLeftMostPageViewPageIndex = -1;
        oldRightMostPageViewPageIndex = -1;
    }
    
    int newLeftMostPageViewPageIndex = newCenterPageViewPageIndex - floor(kMaxCachedPageViewCount / 2.0);
    int newRightMostPageViewPageIndex = newLeftMostPageViewPageIndex + kMaxCachedPageViewCount - 1;

    if (newCenterPageViewPageIndex  >= pageViewsCache.count)
    {
        NSLog(@"##### CapturedContextDetailScrollView: attempting to shift center page view to page %d beyond bounds (%d)", (newCenterPageViewPageIndex + 1), pageViewsCache.count);
        return;
    }
    
    NSMutableArray *recyclablePageViews = [NSMutableArray new];
    
    // First look for page view cache in the old array that are no longer in the range of new cached page views.
    for (int pageIndex = oldLeftMostPageViewPageIndex; pageIndex <= oldRightMostPageViewPageIndex; pageIndex++)
    {
        if (pageIndex < 0 || pageIndex >= leafNodes.count)
        {
            continue;
        }
        if (pageIndex < newLeftMostPageViewPageIndex || pageIndex > newRightMostPageViewPageIndex)
        {
            id objectAtIndex = [pageViewsCache objectAtIndex:pageIndex];
            if (objectAtIndex != [NSNull null])
            {
                CapturedContextDetailView *pageViewCache = (CapturedContextDetailView *)objectAtIndex;

                [recyclablePageViews addObject:pageViewCache];
                [pageViewsCache replaceObjectAtIndex:pageIndex withObject:[NSNull null]];
                
                // TODO: remove the pageViewCache from the scroll view
                if (pageViewCache.superview != nil)
                {
                    [pageViewCache removeFromSuperview];
                }
                pageViewCache.capturedContext = nil;
            }
        }
    }
    
    // Next, look for page view index where we need to have a page view cache but don't yet
    for (int pageIndex = newLeftMostPageViewPageIndex; pageIndex <= newRightMostPageViewPageIndex; pageIndex++)
    {
        if (pageIndex < 0 || pageIndex >= leafNodes.count)
        {
            continue;
        }
        // If this page is outside the bounds of the previous range of
        // cached page views, or if the page view is null,
        // attempt to stick in a pre-allocated page view from the
        // recycle bucket or instantiate a new one.
        if (pageIndex < oldLeftMostPageViewPageIndex ||
            pageIndex > newRightMostPageViewPageIndex ||
            [pageViewsCache objectAtIndex:pageIndex] == [NSNull null])
        {
            CapturedContextDetailView *pageViewCache;
            // First see if we could pop a recyclable page view cache
            if (recyclablePageViews.count > 0)
            {
                pageViewCache = recyclablePageViews.lastObject;
                [recyclablePageViews removeLastObject];
                [pageViewsCache replaceObjectAtIndex:pageIndex withObject:pageViewCache];
            }
            else
            {
                pageViewCache = [[pageViewNib instantiateWithOwner:self options:nil] objectAtIndex:0];
                // Need to create a new instance
                pageViewCache.delegate = self;
                if (isInFullScreenMode)
                {
                    [pageViewCache hideInformationOverlay];
                }
                else
                {
                    [pageViewCache showInformationOverlay];
                }
                [pageViewsCache replaceObjectAtIndex:pageIndex withObject:pageViewCache];
            }
            
            pageViewCache.frame = CGRectMake(pageIndex * scrollView.bounds.size.width, 0, scrollView.bounds.size.width, scrollView.bounds.size.height);
            
            // Reload the content of the moved or newly created page view cache.
            [self reloadPageViewCacheAt:pageIndex];
            
            if (pageViewCache.superview == nil)
            {
                [self.scrollView addSubview:pageViewCache];
            }
        }
    }
    
    centerPageViewPageIndex = newCenterPageViewPageIndex;
}

- (void)shiftCenterPageViewRight
{
    if (centerPageViewPageIndex < leafNodes.count - 1)
    {
        [self.centerPageViewCache stopPlayingAudio];

        [self shiftCenterPageViewTo:(centerPageViewPageIndex + 1)];
    }
}

- (void)shiftCenterPageViewLeft
{
    if (centerPageViewPageIndex > 0)
    {
        [self.centerPageViewCache stopPlayingAudio];
        
        [self shiftCenterPageViewTo:(centerPageViewPageIndex - 1)];
    }
}

- (void)handleFocusedPageChanged
{
    if (self.centerPageViewCache != nil)
    {
        [self.centerPageViewCache startPlayingAudio];
        
        if (self.titleText != nil)
        {
            self.navigationItem.title = [NSString stringWithFormat:@"%@ (%d of %d)", self.titleText, (self.focusedPageIndex + 1), leafNodes.count];
        }
        else
        {
            self.navigationItem.title = [NSString stringWithFormat:@"%d of %d", (self.focusedPageIndex + 1), leafNodes.count];
        }
        
        if ([self.delegate respondsToSelector:@selector(capturedContextDetailScrollViewController:focusedPageIndexChangedTo:)])
        {
            [self.delegate capturedContextDetailScrollViewController:self focusedPageIndexChangedTo:self.focusedPageIndex];
        }
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)sender
{
    BOOL contentScrollingTowardsLeft = self.scrollView.contentOffset.x > previousScrollOffset;
    previousScrollOffset = self.scrollView.contentOffset.x;
    
    int leftMostVisiblePageIndex = floor(self.scrollView.contentOffset.x / self.scrollView.frame.size.width);
    int rightMostVisiblePageIndex = ceil(self.scrollView.contentOffset.x / self.scrollView.frame.size.width);
     
    if (leftMostVisiblePageIndex != rightMostVisiblePageIndex)
    {
        if (contentScrollingTowardsLeft == YES &&
            centerPageViewPageIndex == leftMostVisiblePageIndex)
        {
            [self shiftCenterPageViewRight];
        }
        else if (contentScrollingTowardsLeft == NO &&
                 centerPageViewPageIndex == rightMostVisiblePageIndex)
        {
            [self shiftCenterPageViewLeft];
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)sender
{
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);

    int newFocusedPageIndex = floor(self.scrollView.contentOffset.x / self.scrollView.frame.size.width);
    
    if (centerPageViewPageIndex != newFocusedPageIndex)
    {
        [self shiftCenterPageViewTo:newFocusedPageIndex];
    }
    
    if (self.focusedPageIndex != newFocusedPageIndex)
    {
        self.focusedPageIndex = newFocusedPageIndex;
        
        // FIX: hmm, not really the right place?
        [self handleFocusedPageChanged];
    }
}

#pragma mark - UIAlertViewDelegate


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1)
    {
        [[CapturedContextManager sharedManager] permanentlyDeleteCapturedContext:self.focusedCapturedContext];

        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Deleted photo.");

        [self refreshCapturedContextList];
        [self reloadPageViewsCacheFromCenterPage];
        [self handleFocusedPageChanged];
    }
    
}

#pragma mark - CapturedContextDetailViewDelegate

- (void)capturedContextDetailViewPhotoTapped:(CapturedContextDetailView *)sender
{
    for (id pageViewObject in pageViewsCache)
    {
        if (pageViewObject != [NSNull null])
        {
            CapturedContextDetailView *pageView = pageViewObject;
            
            if (isInFullScreenMode)
            {
                [pageView showInformationOverlay];
                
                self.navigationController.navigationBarHidden = NO;
            }
            else
            {
                self.navigationController.navigationBarHidden = YES;

                [pageView hideInformationOverlay];
            }
        }
    }
    isInFullScreenMode = !isInFullScreenMode;
}

- (IBAction)facebookSend:(id)sender
{
    facebookDisappear = true;
    if([SLComposeViewController isAvailableForServiceType:SLServiceTypeFacebook]) //check if Facebook Account is linked
    {
        mySLComposerSheet = [[SLComposeViewController alloc] init]; //initiate the Social Controller
        mySLComposerSheet = [SLComposeViewController composeViewControllerForServiceType:SLServiceTypeFacebook]; //Tell him with what social plattform to use it, e.g. facebook or twitter
        [mySLComposerSheet setInitialText:[NSString stringWithFormat:@""]]; //the message you want to post
        CapturedContext *context = [self focusedCapturedContext];
        
        [mySLComposerSheet addImage:context.uiImage]; //an image you could post
        //for more instance methodes, go here:https://developer.apple.com/library/ios/#documentation/NetworkingInternet/Reference/SLComposeViewController_Class/Reference/Reference.html#//apple_ref/doc/uid/TP40012205
        [self presentViewController:mySLComposerSheet animated:YES completion:nil];
    }
    [mySLComposerSheet setCompletionHandler:^(SLComposeViewControllerResult result) {
        NSString *output;
        switch (result) {
            case SLComposeViewControllerResultCancelled:
                output = @"Action Cancelled";
                break;
            case SLComposeViewControllerResultDone:
                output = @"Post Successfull";
                break;
            default:
                break;
        } //check if everything worked properly. Give out a message on the state.
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Facebook" message:output delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
        [alert show];
    }];
}

- (IBAction)emailSend:(id)sender
{
    messageDisappear = true;
    MFMailComposeViewController* controller = [[MFMailComposeViewController alloc] init];
    controller.mailComposeDelegate = self;
    [controller setSubject:@"My Subject"];
    //NSData *data = [[NSData alloc] initWithContentsOfFile:@"0.jpg"];
    //UIImage *image = [UIImage imageNamed:@"0.jpg"];
    CapturedContext *context = [self focusedCapturedContext];
    NSData *data = UIImageJPEGRepresentation(context.uiImage, .5);
    [controller addAttachmentData:data mimeType:@"image/jpeg" fileName:@"0.jpg"];
    [controller setMessageBody:@"Hello there." isHTML:NO];
    
    if (controller)
    {
        [self presentViewController:controller animated:YES completion:nil];
    }
}

- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError*)error;
{
    if (result == MFMailComposeResultSent)
    {
        NSLog(@"It's away!");
    }
    [self dismissViewControllerAnimated:YES completion:nil];
    
}
@end
