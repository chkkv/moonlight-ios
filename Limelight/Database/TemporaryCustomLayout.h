//
//  TemporaryCustomLayout.h
//  Moonlight
//
//  In-memory counterpart of the CustomLayout managed object, following the
//  same pattern as TemporaryApp / TemporaryHost.
//
//  The managed object stores metadata as columns (id, name, sortOrder) plus the
//  serialised layout as an opaque share token. `document` is the decoded form.
//
//  Ownership rule: the `name` column is authoritative for the display name, and
//  the token is regenerated from `document` on save. Renaming a layout only
//  needs to set `name`; the copy inside the document is refreshed on save.
//

#import <Foundation/Foundation.h>

#import "CustomLayoutDocument.h"
#import "CustomLayout+CoreDataClass.h"

@interface TemporaryCustomLayout : NSObject

@property (nullable, nonatomic, retain) NSString *layoutId;
@property (nullable, nonatomic, retain) NSString *name;
@property (nonatomic)                   int32_t sortOrder;

// nil when the stored token could not be decoded. Such a row is left untouched
// on save rather than being silently erased.
@property (nullable, nonatomic, retain) CustomLayoutDocument *document;

- (id)initFromCustomLayout:(CustomLayout *)layout;

- (NSComparisonResult)compareSortOrder:(TemporaryCustomLayout *)other;

- (void)propagateChangesToParent:(CustomLayout *)parent;

@end
