//
//  PrinterView.m
//  Mariani
//
//  Created by sh95014 on 3/12/22.
//

#import "PrinterView.h"

#define PRINTER_DPI             72.0
#define PAPER_WIDTH             8.5
#define PAPER_HEIGHT            11

@interface PrinterString : NSObject
@property (strong) NSString *string;
@property (assign) CGPoint location;
@end

@implementation PrinterString
#ifdef DEBUG
- (NSString *)description {
    return [NSString stringWithFormat:@"%@ (%.1f, %.1f) \"%@\"", [super description], self.location.x, self.location.y, self.string];
}
#endif // DEBUG
@end

@interface PrinterPage : NSObject
@property (strong) NSMutableArray<PrinterString *> *strings;
@property (strong) NSMutableArray *bitmaps;
@end

@implementation PrinterPage

- (instancetype)init {
    if ((self = [super init]) != nil) {
        self.strings = [NSMutableArray array];
        // It's possible for a row of graphics to straddle two pages, so we
        // +1 for an overflow area that we then give to the next page when
        // it's created.
        self.bitmaps = [NSMutableArray arrayWithCapacity:PAPER_HEIGHT + 1];
        for (NSInteger i = 0; i < PAPER_HEIGHT + 1; i++) {
            [self.bitmaps addObject:[NSNull null]];
        }
    }
    return self;
}

@end

@interface PrinterView ()

@property (strong) NSFont *font;
@property (assign) CGFloat characterWidth;
@property (assign) CGFloat lineHeight;
@property (strong) NSDictionary *fontAttributes;
@property (strong) NSMutableArray<PrinterPage *> *pages;
@property (assign) NSInteger currentPage;

@end

@implementation PrinterView

- (void)awakeFromNib {
    self.pages = [NSMutableArray arrayWithObject:[[PrinterPage alloc] init]];
    self.currentPage = -1;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    const BOOL isDrawingToScreen = [NSGraphicsContext currentContextDrawingToScreen];
    
    [[NSColor whiteColor] setFill];
    NSRectFill(dirtyRect);
    
    PrinterPage *page;
    if (isDrawingToScreen) {
        if (self.currentPage < 0) {
            page = self.pages.lastObject;
        }
        else {
            page = [self.pages objectAtIndex:self.currentPage];
        }
    }
    else {
        NSInteger pageNumber = [[NSPrintOperation currentOperation] currentPage];
        page = [self.pages objectAtIndex:pageNumber - 1];
    }
    
    CGFloat dirtyRectTop = CGRectGetMinY(dirtyRect);
    CGFloat dirtyRectBottom = CGRectGetMaxY(dirtyRect);
    for (NSInteger i = floorf(dirtyRectTop / PRINTER_DPI); i < ceilf(dirtyRectBottom / PRINTER_DPI); i++) {
        if ([page.bitmaps[i] isKindOfClass:[NSBitmapImageRep class]]) {
            NSBitmapImageRep *bitmap = (NSBitmapImageRep *)page.bitmaps[i];
            CGRect destRect = CGRectMake(0, i * PRINTER_DPI, bitmap.pixelsWide, bitmap.pixelsHigh);
            if (!isDrawingToScreen) {
                NSRect printableRect = [[[NSPrintOperation currentOperation] printInfo] imageablePageBounds];
                NSRect bounds = self.bounds;
                destRect.origin.x = printableRect.origin.x + destRect.origin.x * (printableRect.size.width / bounds.size.width);
                destRect.origin.y = printableRect.origin.y + destRect.origin.y * (printableRect.size.height / bounds.size.height);
                CGFloat nextY = printableRect.origin.y + ((i + 1) * PRINTER_DPI) * (printableRect.size.height / bounds.size.height);
                NSAssert(bitmap.pixelsWide - bounds.size.width < FLT_EPSILON, @"bitmap expected to be as wide as paper");
                // actual formula is destRect.size.width = destRect.size.width * (printableRect.size.width / bounds.size.width)
                // but thanks to the assert above we can simplify to:
                destRect.size.width = printableRect.size.width;
                // actual formula is destRect.size.height = destRect.size.height * (printableRect.size.height / bounds.size.height)
                // but we want to make sure there are no gaps caused by floating point math
                destRect.size.height = nextY - destRect.origin.y;
            }
            [bitmap drawInRect:destRect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationCopy
                      fraction:1.0
                respectFlipped:YES
                         hints:@{ NSImageHintInterpolation: @(NSImageInterpolationNone) }];
        }
    }
    
    for (PrinterString *ps in page.strings) {
        CGPoint location = ps.location;
        if (location.y + self.lineHeight < CGRectGetMinY(dirtyRect) ||
            location.y > CGRectGetMaxY(dirtyRect)) {
            // string is outside dirtyRect, don't bother drawing it
            continue;
        }
        if (!isDrawingToScreen) {
            NSRect printableRect = [[[NSPrintOperation currentOperation] printInfo] imageablePageBounds];
            NSRect bounds = self.bounds;
            location.x = printableRect.origin.x + location.x * (printableRect.size.width / bounds.size.width);
            location.y = printableRect.origin.y + location.y * (printableRect.size.height / bounds.size.height);
        }
        [ps.string drawAtPoint:location withAttributes:self.fontAttributes];
    }
}

#pragma mark - NSPrinting

- (NSRect)rectForPage:(NSInteger)page {
    return [self bounds];
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    *range = NSMakeRange(1, self.pages.count);
    return YES;
}

#pragma mark -

- (void)addString:(NSString *)string atPoint:(CGPoint)location {
    PrinterString *printerString = [[PrinterString alloc] init];
    printerString.string = string;
    printerString.location = location;
    PrinterPage *page = self.pages.lastObject;
    [page.strings addObject:printerString];
    
    if (self.currentPage == -1 || self.currentPage == self.pages.count - 1) {
        [self setNeedsDisplay:YES];
    }

    [self.delegate printerView:self printedToPage:self.pages.count - 1];
}

- (void)setFontSize:(CGSize)size {
    // BasePrinter calculates the position of each character, but we draw them
    // as a string so need to fudge the spacing to match. self.characterWidth
    // is also fudged to make the thumbnail account for the kerning.
    CGFloat kerning = 0;
    if (size.width > 5.5) {
        self.font = [NSFont fontWithName:@"FXMatrix105MonoPicaRegular" size:9];
        kerning = 1.2;
        self.characterWidth = self.font.maximumAdvancement.width * 1.28;
    }
    else {
        self.font = [NSFont fontWithName:@"FXMatrix105MonoEliteRegular" size:9];
        kerning = 0.99;
        self.characterWidth = self.font.maximumAdvancement.width * 1.22;
    }
    self.lineHeight = self.font.ascender + self.font.descender + self.font.leading;
    
    self.fontAttributes = @{
        NSFontAttributeName: self.font,
        NSKernAttributeName: @(kerning),
    };
}

- (void)plotAtPoint:(CGPoint)location {
    PrinterPage *page = self.pages.lastObject;
    NSInteger pageIndex = floorf(location.y / PRINTER_DPI);
    NSBitmapImageRep *bitmap;
    if ([page.bitmaps[pageIndex] isKindOfClass:[NSBitmapImageRep class]]) {
        bitmap = (NSBitmapImageRep *)page.bitmaps[pageIndex];
    }
    else {
        bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                         pixelsWide:PRINTER_DPI * PAPER_WIDTH
                                                         pixelsHigh:PRINTER_DPI
                                                      bitsPerSample:8
                                                    samplesPerPixel:1
                                                           hasAlpha:NO
                                                           isPlanar:NO
                                                     colorSpaceName:NSDeviceWhiteColorSpace
                                                        bytesPerRow:PRINTER_DPI * PAPER_WIDTH
                                                       bitsPerPixel:8];
        // fill with white
        memset(bitmap.bitmapData, ~0, bitmap.bytesPerRow * bitmap.pixelsHigh);
        page.bitmaps[pageIndex] = bitmap;
    }
    
    NSUInteger black = 0;
    [bitmap setPixel:&black atX:location.x y:fmod(location.y, bitmap.pixelsHigh)];
    
    if (self.currentPage == -1 || self.currentPage == self.pages.count - 1) {
        [self setNeedsDisplay:YES];
    }
    
    [self.delegate printerView:self printedToPage:self.pages.count - 1];
}

- (void)addPage {
    PrinterPage *lastPage = self.pages.lastObject;
    PrinterPage *newPage = [[PrinterPage alloc] init];
    if ([lastPage.bitmaps.lastObject isKindOfClass:[NSBitmapImageRep class]]) {
        // the last page printed into the overflow bitmap, let's grab it and
        // use it as our top bitmap
        NSBitmapImageRep *bitmap = (NSBitmapImageRep *)lastPage.bitmaps.lastObject;
        [lastPage.bitmaps removeLastObject];
        newPage.bitmaps[0] = bitmap;
    }
    [self.pages addObject:newPage];
    
    [self setNeedsDisplay:YES];
    
    [self.delegate printerViewPageAdded:self];
}

- (NSImage *)imageThumbnailOfPage:(NSInteger)pageNumber withDPI:(NSInteger)dpi {
    NSBitmapImageRep *thumbnail =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                pixelsWide:dpi * PAPER_WIDTH
                                                pixelsHigh:dpi * PAPER_HEIGHT
                                             bitsPerSample:8
                                           samplesPerPixel:1
                                                  hasAlpha:NO
                                                  isPlanar:NO
                                            colorSpaceName:NSDeviceWhiteColorSpace
                                               bytesPerRow:dpi * PAPER_WIDTH
                                              bitsPerPixel:8];
    // fill with white
    memset(thumbnail.bitmapData, ~0, thumbnail.bytesPerRow * thumbnail.pixelsHigh);
    NSImage *image = [[NSImage alloc] initWithSize:thumbnail.size];
    [image addRepresentation:thumbnail];

    [image lockFocusFlipped:YES];
    PrinterPage *page = self.pages[pageNumber];
    for (NSInteger i = 0; i < PAPER_HEIGHT; i++) {
        if ([page.bitmaps[i] isKindOfClass:[NSBitmapImageRep class]]) {
            NSBitmapImageRep *bitmap = (NSBitmapImageRep *)page.bitmaps[i];
            CGRect destRect = CGRectMake(0, i * dpi, dpi * PAPER_WIDTH, dpi);
            [bitmap drawInRect:destRect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationCopy
                      fraction:1.0
                respectFlipped:YES
                         hints:@{ NSImageHintInterpolation: @(NSImageInterpolationHigh) }];
        }
    }
    
    CGFloat scale = dpi / PRINTER_DPI;
    NSBezierPath *path = [NSBezierPath bezierPath];
    [[NSColor colorWithWhite:0 alpha:0.3] setStroke];
    [path setLineWidth:(dpi / self.lineHeight) * 0.6];
    for (PrinterString *ps in page.strings) {
        CGFloat x = ps.location.x * scale;
        CGFloat y = ps.location.y * scale;
        CGFloat width = ps.string.length * self.characterWidth * scale;
        
        [path moveToPoint:CGPointMake(x, y)];
        [path lineToPoint:CGPointMake(x + width, y)];
    }
    [path stroke];

    [image unlockFocus];
    
    return image;
}

- (NSInteger)pageCount {
    return self.pages.count;
}

- (void)showPage:(NSInteger)pageNumber {
    self.currentPage = pageNumber;
    [self setNeedsDisplay:YES];
}

@end
