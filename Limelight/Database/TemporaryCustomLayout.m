//
//  TemporaryCustomLayout.m
//  Moonlight
//

#import "TemporaryCustomLayout.h"

@implementation TemporaryCustomLayout

- (id)initFromCustomLayout:(CustomLayout *)layout {
    self = [self init];
    if (self == nil) {
        return nil;
    }

    self.layoutId = layout.id;
    self.name = layout.name;
    self.sortOrder = layout.sortOrder;

    NSError *error = nil;
    self.document = [CustomLayoutDocument layoutFromShareToken:layout.shareToken error:&error];
    if (self.document == nil) {
        Log(LOG_W, @"Discarding unreadable custom layout '%@': %@",
            layout.name, error.localizedDescription);
    }

    return self;
}

- (NSComparisonResult)compareSortOrder:(TemporaryCustomLayout *)other {
    if (self.sortOrder < other.sortOrder) {
        return NSOrderedAscending;
    }
    if (self.sortOrder > other.sortOrder) {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (void)propagateChangesToParent:(CustomLayout *)parent {
    // A row whose token could not be decoded is left as-is, so a corrupt or
    // newer-format layout is not destroyed by an unrelated save.
    if (self.document == nil) {
        return;
    }

    parent.id = self.layoutId;
    parent.name = self.name;
    parent.sortOrder = self.sortOrder;

    // Refresh the copy inside the document so the token stays self-contained
    // when it is shared or re-imported.
    self.document.name = self.name;
    parent.shareToken = [self.document shareToken];
}

@end
