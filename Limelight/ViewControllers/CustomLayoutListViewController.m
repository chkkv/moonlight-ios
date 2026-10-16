//
//  CustomLayoutListViewController.m
//  Moonlight
//

#import "CustomLayoutListViewController.h"
#import "CustomControlsEditorViewController.h"
#import "DataManager.h"

// Private surface, declared up front so the implementation order is irrelevant.
@interface CustomLayoutListViewController ()
- (void)reload;
- (void)doneTapped;
- (void)addTapped;
- (void)createLayoutNamed:(NSString *)name;
- (void)presentEditorForLayout:(TemporaryCustomLayout *)layout;
- (void)renameLayoutAtIndex:(NSInteger)index;
- (void)deleteLayoutAtIndex:(NSInteger)index;
- (void)exportLayoutAtIndex:(NSInteger)index fromView:(UIView *)sourceView;
- (void)presentShareSheetForToken:(NSString *)token
                         layoutName:(NSString *)layoutName
                           fromView:(UIView *)sourceView;
- (void)importTapped:(UIBarButtonItem *)sender;
- (void)importFromClipboard;
- (void)promptForToken;
- (void)importFromTokenString:(NSString *)rawToken;
- (NSString *)uniqueNameForImportedLayout:(NSString *)proposed;
- (void)showMessage:(NSString *)message;
@end

@implementation CustomLayoutListViewController {
    NSArray<TemporaryCustomLayout *> *_layouts;
    NSString *_activeLayoutId;
}

// UITableViewController's designated initialiser is -initWithStyle:, so be
// explicit instead of relying on what -init happens to default to.
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Custom Layouts";
    self.tableView.rowHeight = 60.0;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                         target:self
                                                                                         action:@selector(doneTapped)];
    // Import sits next to Add rather than in the table, because it acts on the
    // whole list rather than on one row.
    UIBarButtonItem *importItem = [[UIBarButtonItem alloc] initWithTitle:@"Import"
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(importTapped:)];
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                            target:self
                                                                            action:@selector(addTapped)];
    self.navigationItem.rightBarButtonItems = @[ importItem, addItem ];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The editor may have changed a layout while it was pushed.
    [self reload];
}

- (void)reload {
    DataManager *dataMan = [[DataManager alloc] init];
    _layouts = [dataMan getCustomLayouts];

    TemporaryCustomLayout *active = [dataMan getActiveCustomLayout];
    _activeLayoutId = active.layoutId;

    [self.tableView reloadData];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

- (void)addTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Layout"
                                                                  message:@"Give the layout a name. You can rename it later."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Layout name";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [weakSelf createLayoutNamed:(name.length > 0 ? name : @"Untitled")];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createLayoutNamed:(NSString *)name {
    TemporaryCustomLayout *layout = [[TemporaryCustomLayout alloc] init];
    layout.name = name;
    // Start from something usable rather than an overlay that draws nothing.
    layout.document = [CustomLayoutDocument starterLayoutWithName:name];

    DataManager *dataMan = [[DataManager alloc] init];
    [dataMan addCustomLayout:layout];

    // A freshly created layout is almost always the one you want to use.
    [dataMan activateCustomLayout:layout.layoutId];

    [self reload];
    [self presentEditorForLayout:layout];
}

// ---------------------------------------------------------------------------
// Activate / edit / rename / delete
// ---------------------------------------------------------------------------

- (void)presentEditorForLayout:(TemporaryCustomLayout *)layout {
    if (layout == nil) {
        return;
    }

    // A row whose token failed to decode has no document to edit, and saving it
    // would silently wipe the stored layout.
    if (layout.document == nil) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Cannot Edit Layout"
                                                message:@"This layout could not be read, so it cannot be edited. Delete it and create a new one."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // Presented rather than pushed: the editor is a full-screen canvas whose
    // geometry has to match the stream view exactly, so it must not be inset by
    // a navigation bar. Its own toolbar handles save and exit.
    CustomControlsEditorViewController *editor = [[CustomControlsEditorViewController alloc] initWithLayout:layout];
    editor.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:editor animated:YES completion:nil];
}

- (void)renameLayoutAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_layouts.count) {
        return;
    }

    TemporaryCustomLayout *layout = _layouts[index];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Layout"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = layout.name;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0) {
            return;
        }

        layout.name = name;
        [[[DataManager alloc] init] updateCustomLayout:layout];
        [weakSelf reload];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteLayoutAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_layouts.count) {
        return;
    }

    // DataManager clears activeLayoutId when the deleted row was the active one.
    [[[DataManager alloc] init] removeCustomLayout:_layouts[index]];
    [self reload];
}

// ---------------------------------------------------------------------------
// Table view
// ---------------------------------------------------------------------------

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _layouts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const cellIdentifier = @"CustomLayoutCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }

    TemporaryCustomLayout *layout = _layouts[indexPath.row];
    BOOL isActive = (_activeLayoutId != nil && [layout.layoutId isEqualToString:_activeLayoutId]);

    NSUInteger controlCount = layout.document.controls.count;

    cell.textLabel.text = layout.name;
    cell.textLabel.textColor = isActive ? self.view.tintColor : [UIColor labelColor];
    cell.detailTextLabel.text = isActive
        ? [NSString stringWithFormat:@"Active \u00b7 %lu controls", (unsigned long)controlCount]
        : [NSString stringWithFormat:@"%lu controls", (unsigned long)controlCount];
    // The detail button opens the editor; tapping the row activates the layout.
    cell.accessoryType = UITableViewCellAccessoryDetailButton;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    TemporaryCustomLayout *layout = _layouts[indexPath.row];
    [[[DataManager alloc] init] activateCustomLayout:layout.layoutId];
    [self reload];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    [self presentEditorForLayout:_layouts[indexPath.row]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) {
    __weak typeof(self) weakSelf = self;
    NSInteger row = indexPath.row;

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [weakSelf deleteLayoutAtIndex:row];
        completionHandler(YES);
    }];

    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                               title:@"Rename"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [weakSelf renameLayoutAtIndex:row];
        completionHandler(YES);
    }];

    // Export hands out the same base64 token the layout is stored as, so a layout
    // can be moved between devices by copy-paste or any share target.
    UIContextualAction *exportAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                               title:@"Export"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [weakSelf exportLayoutAtIndex:row fromView:sourceView];
        completionHandler(YES);
    }];
    exportAction.backgroundColor = [UIColor systemBlueColor];

    return [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction, renameAction, exportAction ]];
}

// ---------------------------------------------------------------------------
// Base64 export
// ---------------------------------------------------------------------------

- (void)exportLayoutAtIndex:(NSInteger)index fromView:(UIView *)sourceView {
    if (index < 0 || index >= (NSInteger)_layouts.count) {
        return;
    }

    TemporaryCustomLayout *layout = _layouts[index];
    NSString *token = [layout.document shareToken];
    if (token.length == 0) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Cannot Export Layout"
                                                message:@"This layout could not be read, so there is nothing to export."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [self presentShareSheetForToken:token layoutName:layout.name fromView:sourceView];
}

- (void)presentShareSheetForToken:(NSString *)token
                         layoutName:(NSString *)layoutName
                           fromView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Export Layout"
                                                                  message:layoutName
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Base64"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        // The token is the layout document verbatim, so pasting it into the app
        // on another device reproduces this layout exactly.
        [UIPasteboard generalPasteboard].string = token;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Share\u2026"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        UIActivityViewController *shareSheet =
            [[UIActivityViewController alloc] initWithActivityItems:@[ token ] applicationActivities:nil];
        // Required on iPad, otherwise presenting the share sheet throws.
        shareSheet.popoverPresentationController.sourceView = sourceView;
        shareSheet.popoverPresentationController.sourceRect = sourceView.bounds;
        [self presentViewController:shareSheet animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // Required on iPad, otherwise presenting an action sheet throws.
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
// Base64 import
// ---------------------------------------------------------------------------

- (void)importTapped:(UIBarButtonItem *)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Import Layout"
                                                                  message:@"Bring in a layout that was exported from Moonlight."
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Paste from Clipboard"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self importFromClipboard];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Enter Base64\u2026"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self promptForToken];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // Required on iPad, otherwise presenting an action sheet throws.
    sheet.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)importFromClipboard {
    // Reading the pasteboard happens on an explicit tap, so the system's paste
    // notice is expected here rather than a surprise.
    NSString *clipboard = [UIPasteboard generalPasteboard].string;
    if (clipboard.length == 0) {
        [self showMessage:@"The clipboard is empty."];
        return;
    }

    [self importFromTokenString:clipboard];
}

- (void)promptForToken {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Layout"
                                                                  message:@"Paste the exported Base64 token."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"MLOSC1:...";
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self importFromTokenString:alert.textFields.firstObject.text];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importFromTokenString:(NSString *)rawToken {
    NSString *token = [rawToken stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (token.length == 0) {
        [self showMessage:@"Nothing to import."];
        return;
    }

    // The very same reader the stored documents go through, so an imported layout
    // is validated exactly as strictly as one read back from the database, and
    // its error messages are the ones already written for that path.
    NSError *error = nil;
    CustomLayoutDocument *document = [CustomLayoutDocument layoutFromShareToken:token error:&error];
    if (document == nil) {
        [self showMessage:[NSString stringWithFormat:@"That is not a valid layout.\n\n%@",
                           error.localizedDescription ?: @"Unknown error."]];
        return;
    }

    TemporaryCustomLayout *layout = [[TemporaryCustomLayout alloc] init];
    layout.document = document;
    layout.name = [self uniqueNameForImportedLayout:document.name];

    DataManager *dataMan = [[DataManager alloc] init];
    [dataMan addCustomLayout:layout];

    [self reload];
    [self showMessage:[NSString stringWithFormat:@"Imported \u201c%@\u201d with %lu controls.",
                       layout.name, (unsigned long)document.controls.count]];
}

// Keeps imported layouts distinguishable when the same token arrives twice. The
// suffix is kept within the model's 40 character name limit.
- (NSString *)uniqueNameForImportedLayout:(NSString *)proposed {
    NSString *base = proposed.length ? proposed : @"Imported";
    if (base.length > 34) {
        base = [base substringToIndex:34];
    }

    NSMutableSet<NSString *> *existing = [NSMutableSet set];
    for (TemporaryCustomLayout *layout in _layouts) {
        if (layout.name.length) {
            [existing addObject:layout.name];
        }
    }

    if (![existing containsObject:base]) {
        return base;
    }

    for (NSInteger suffix = 2; suffix < 1000; suffix++) {
        NSString *candidate = [NSString stringWithFormat:@"%@ (%ld)", base, (long)suffix];
        if (![existing containsObject:candidate]) {
            return candidate;
        }
    }

    return base;
}

- (void)showMessage:(NSString *)message {
    // Chained presentations (an alert opened from an action sheet's handler, and
    // a result alert opened from that alert's handler) can be rejected while the
    // previous one is still dismissing, so wait a runloop turn.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                      message:message
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
