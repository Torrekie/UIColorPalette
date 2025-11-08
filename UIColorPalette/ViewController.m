//
//  ViewController.m
//  UIColorPalette
//
//  Created by Torrekie on 2025/11/4.
//

#import "ViewController.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

@interface CALayer ()
@property (atomic, assign) BOOL wantsExtendedDynamicRangeContent;
@end

@interface UIColor (Private)
@property (nonatomic, strong, getter=_systemColorName, setter=_setSystemColorName:) NSString *systemColorName;
@end

@interface ViewController ()
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
    
    // Detect Mac Catalyst environment
#if TARGET_OS_MACCATALYST
    self.isMacCatalyst = YES;
#else
    self.isMacCatalyst = NO;
#endif
    
    // Initialize Metal device for EDR support (only on real devices)
#if !TARGET_OS_SIMULATOR
    self.metalDevice = MTLCreateSystemDefaultDevice();
#endif
    
    [self setupSystemColors];
    [self setupUI];
    
    // Ensure picker is reloaded after colors are discovered
    NSLog(@"About to reload picker - filteredSystemColors count: %lu", (unsigned long)self.filteredSystemColors.count);
    
    // Force a reload and check if it worked
    if (self.isMacCatalyst) {
        // Use table view for Mac Catalyst
        [self.colorTableView reloadData];
        
        // Add a small delay to ensure the reload completes
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"Table view sections after reload: %ld", (long)[self.colorTableView numberOfSections]);
            NSLog(@"Table view rows in section 0: %ld", (long)[self.colorTableView numberOfRowsInSection:0]);
            
            // Only update color display if we have colors
            if (self.filteredSystemColors.count > 0) {
                [self updateColorDisplay];
            } else {
                NSLog(@"WARNING: No colors discovered, skipping initial color display");
            }
        });
    } else {
        // Use picker view for iOS
        [self.colorPicker reloadAllComponents];
        
        // Add a small delay to ensure the reload completes
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"Picker components after reload: %ld", (long)[self.colorPicker numberOfComponents]);
            NSLog(@"Picker rows in component 0: %ld", (long)[self.colorPicker numberOfRowsInComponent:0]);
            
            // Only update color display if we have colors
            if (self.filteredSystemColors.count > 0) {
                [self updateColorDisplay];
            } else {
                NSLog(@"WARNING: No colors discovered, skipping initial color display");
            }
        });
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Layout EDR layers after views have proper frames
    for (UIView *variantView in self.variantColorViews) {
        [self layoutEDRLayerForView:variantView];
    }
}

- (void)setupSystemColors {
    // Dynamically discover all UIColor class methods that return colors at runtime
    NSMutableArray *colorSelectors = [NSMutableArray array];
    
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(object_getClass([UIColor class]), &methodCount);
    
    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        SEL selector = method_getName(method);
        NSString *selectorName = NSStringFromSelector(selector);
        
        // Filter criteria:
        // 1. Method name should end with "Color"
        // 2. Should be a class method (already filtered by object_getClass)
        // 3. Should not take any arguments
        // 4. Should return a UIColor (checked by attempting to call it)
        
        if (![selectorName hasSuffix:@"Color"]) {
            continue;
        }
        
        // Check if method takes no arguments (only has implicit self and _cmd)
        unsigned int argCount = method_getNumberOfArguments(method);
        if (argCount != 2) {  // 2 = self + _cmd (no actual parameters)
            continue;
        }
        
        // Try to invoke the method and check if it returns a UIColor
        @try {
            if ([UIColor respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id result = [UIColor performSelector:selector];
#pragma clang diagnostic pop
                
                // Verify the result is a UIColor and not nil
                if (result && [result isKindOfClass:[UIColor class]]) {
                    // Additional validation - try to get CGColor to ensure it's valid
                    UIColor *colorResult = (UIColor *)result;
                    CGColorRef cgColor = colorResult.CGColor;
                    if (cgColor) {
                        [colorSelectors addObject:selectorName];
                    }
                }
            }
        } @catch (NSException *exception) {
            // Skip selectors that throw exceptions
            NSLog(@"Skipping selector %@ due to exception: %@", selectorName, exception);
        } @catch (...) {
            // Catch any other types of crashes (like EXC_BAD_ACCESS)
            NSLog(@"Skipping selector %@ due to crash", selectorName);
        }
    }
    
    free(methods);
    
    // Sort the color selectors alphabetically for consistent display
    [colorSelectors sortUsingSelector:@selector(compare:)];
    
    self.systemColors = [colorSelectors copy];
    self.filteredSystemColors = self.systemColors; // Initially show all colors
    
    NSLog(@"Discovered %lu color selectors", (unsigned long)colorSelectors.count);
    NSLog(@"systemColors: %@", self.systemColors);
    NSLog(@"filteredSystemColors: %@", self.filteredSystemColors);
    
    // Additional Mac Catalyst debugging
#if TARGET_OS_MACCATALYST
    NSLog(@"Running on Mac Catalyst");
#endif
}

- (void)setupUI {
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    
    // Create and configure the search bar
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.placeholder = @"Search colors...";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];
    
    // Create and configure the picker view or table view based on platform
    if (self.isMacCatalyst) {
        // Use UITableView for Mac Catalyst (UIPickerView has issues)
        self.colorTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        self.colorTableView.translatesAutoresizingMaskIntoConstraints = NO;
        self.colorTableView.dataSource = self;
        self.colorTableView.delegate = self;
        self.colorTableView.rowHeight = 44;
        self.colorTableView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.colorTableView.layer.cornerRadius = 8;
        [self.colorTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ColorCell"];
        [self.view addSubview:self.colorTableView];
        
        NSLog(@"Table view created for Mac Catalyst - dataSource: %@, delegate: %@", self.colorTableView.dataSource, self.colorTableView.delegate);
    } else {
        // Use UIPickerView for iOS
        self.colorPicker = [[UIPickerView alloc] init];
        self.colorPicker.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.colorPicker];
        
        // Set data source and delegate AFTER adding to view hierarchy
        self.colorPicker.dataSource = self;
        self.colorPicker.delegate = self;
        
        NSLog(@"Picker view created for iOS - dataSource: %@, delegate: %@", self.colorPicker.dataSource, self.colorPicker.delegate);
    }
    
    // Create and configure the color display scroll view
    self.colorDisplayScrollView = [[UIScrollView alloc] init];
    self.colorDisplayScrollView.layer.cornerRadius = 12;
    self.colorDisplayScrollView.layer.borderWidth = 1;
    self.colorDisplayScrollView.layer.borderColor = UIColor.separatorColor.CGColor;
    self.colorDisplayScrollView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.colorDisplayScrollView.showsHorizontalScrollIndicator = YES;
    self.colorDisplayScrollView.showsVerticalScrollIndicator = NO;
    self.colorDisplayScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.colorDisplayScrollView];
    
    // Create container view for color variants
    self.colorDisplayContainerView = [[UIView alloc] init];
    self.colorDisplayContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.colorDisplayContainerView.userInteractionEnabled = YES; // Ensure container allows interaction
    [self.colorDisplayScrollView addSubview:self.colorDisplayContainerView];
    
    // Initialize arrays for dynamic variant views
    self.variantColorViews = [NSMutableArray array];
    self.variantLabels = [NSMutableArray array];
    
    // Create and configure the color details text view
    self.colorDetailsTextView = [[UITextView alloc] init];
    self.colorDetailsTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.colorDetailsTextView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.colorDetailsTextView.layer.cornerRadius = 8;
    self.colorDetailsTextView.editable = NO;
    self.colorDetailsTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.colorDetailsTextView];
    
    // Create and configure the code generator text view
    self.codeGeneratorTextView = [[UITextView alloc] init];
    self.codeGeneratorTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.codeGeneratorTextView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    self.codeGeneratorTextView.layer.cornerRadius = 8;
    self.codeGeneratorTextView.layer.borderWidth = 1;
    self.codeGeneratorTextView.layer.borderColor = UIColor.separatorColor.CGColor;
    self.codeGeneratorTextView.editable = NO;
    self.codeGeneratorTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.codeGeneratorTextView];
    
    // Setup constraints
    NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
        // Search bar constraints
        [self.searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
    
    // Add picker/table view constraints based on platform
    UIView *pickerOrTableView;
    if (self.isMacCatalyst) {
        pickerOrTableView = self.colorTableView;
        [constraints addObjectsFromArray:@[
            [self.colorTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:5],
            [self.colorTableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [self.colorTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            [self.colorTableView.heightAnchor constraintEqualToConstant:200], // Slightly taller for table
        ]];
    } else {
        pickerOrTableView = self.colorPicker;
        [constraints addObjectsFromArray:@[
            [self.colorPicker.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:5],
            [self.colorPicker.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [self.colorPicker.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            [self.colorPicker.heightAnchor constraintEqualToConstant:150],
        ]];
    }
    
    // Add remaining constraints
    [constraints addObjectsFromArray:@[
        
        // Color display scroll view constraints
        [self.colorDisplayScrollView.topAnchor constraintEqualToAnchor:pickerOrTableView.bottomAnchor constant:20],
        [self.colorDisplayScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.colorDisplayScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.colorDisplayScrollView.heightAnchor constraintEqualToConstant:100],
        
        // Color display container view constraints
        [self.colorDisplayContainerView.topAnchor constraintEqualToAnchor:self.colorDisplayScrollView.topAnchor],
        [self.colorDisplayContainerView.leadingAnchor constraintEqualToAnchor:self.colorDisplayScrollView.leadingAnchor],
        [self.colorDisplayContainerView.trailingAnchor constraintEqualToAnchor:self.colorDisplayScrollView.trailingAnchor],
        [self.colorDisplayContainerView.bottomAnchor constraintEqualToAnchor:self.colorDisplayScrollView.bottomAnchor],
        [self.colorDisplayContainerView.heightAnchor constraintEqualToAnchor:self.colorDisplayScrollView.heightAnchor],
        
        // Code generator text view constraints
        [self.codeGeneratorTextView.topAnchor constraintEqualToAnchor:self.colorDisplayScrollView.bottomAnchor constant:10],
        [self.codeGeneratorTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.codeGeneratorTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.codeGeneratorTextView.heightAnchor constraintEqualToConstant:120],
        
        // Color details text view constraints
        [self.colorDetailsTextView.topAnchor constraintEqualToAnchor:self.codeGeneratorTextView.bottomAnchor constant:10],
        [self.colorDetailsTextView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.colorDetailsTextView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.colorDetailsTextView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
    
    [NSLayoutConstraint activateConstraints:constraints];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        // Show all colors when search is empty
        self.filteredSystemColors = self.systemColors;
    } else {
        // Filter colors based on search text
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSString *selectorName, NSDictionary *bindings) {
            // Search in selector name
            if ([selectorName localizedCaseInsensitiveContainsString:searchText]) {
                return YES;
            }
            
            // Search in system color name (from private property)
            UIColor *color = [self colorFromSelector:selectorName];
            NSString *systemColorName = color.systemColorName;
            if (systemColorName && [systemColorName localizedCaseInsensitiveContainsString:searchText]) {
                return YES;
            }
            
            return NO;
        }];
        
        self.filteredSystemColors = [self.systemColors filteredArrayUsingPredicate:predicate];
    }
    
    if (self.isMacCatalyst) {
        [self.colorTableView reloadData];
        
        // Select first result if available
        if (self.filteredSystemColors.count > 0) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
            [self.colorTableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionTop];
            [self updateColorDisplay];
        }
    } else {
        [self.colorPicker reloadAllComponents];
        
        // Select first result if available
        if (self.filteredSystemColors.count > 0) {
            [self.colorPicker selectRow:0 inComponent:0 animated:NO];
            [self updateColorDisplay];
        }
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UIPickerViewDataSource

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    NSLog(@"numberOfComponentsInPickerView called - returning 1");
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    NSInteger count = self.filteredSystemColors ? self.filteredSystemColors.count : 0;
    NSLog(@"Picker numberOfRows requested: %ld", (long)count);
    return count;
}

#pragma mark - UIPickerViewDelegate

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    if (!self.filteredSystemColors || row >= self.filteredSystemColors.count) {
        NSLog(@"ERROR: Invalid row %ld for filteredSystemColors count %lu", (long)row, (unsigned long)self.filteredSystemColors.count);
        return @"Invalid";
    }
    
    NSString *selectorName = self.filteredSystemColors[row];
    UIColor *color = [self colorFromSelector:selectorName];
    NSString *systemColorName = color.systemColorName ?: selectorName;
    NSLog(@"Picker title for row %ld: %@", (long)row, systemColorName);
    return systemColorName;
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    [self updateColorDisplay];
}

#pragma mark - UITableViewDataSource (Mac Catalyst alternative)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = self.filteredSystemColors ? self.filteredSystemColors.count : 0;
    NSLog(@"Table numberOfRows requested: %ld", (long)count);
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ColorCell" forIndexPath:indexPath];
    
    if (!self.filteredSystemColors || indexPath.row >= self.filteredSystemColors.count) {
        NSLog(@"ERROR: Invalid row %ld for filteredSystemColors count %lu", (long)indexPath.row, (unsigned long)self.filteredSystemColors.count);
        cell.textLabel.text = @"Invalid";
        return cell;
    }
    
    NSString *selectorName = self.filteredSystemColors[indexPath.row];
    UIColor *color = [self colorFromSelector:selectorName];
    NSString *systemColorName = color.systemColorName ?: selectorName;
    
    cell.textLabel.text = systemColorName;
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    // Add a small color preview
    UIView *colorPreview = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    colorPreview.backgroundColor = color;
    colorPreview.layer.cornerRadius = 3;
    colorPreview.layer.borderWidth = 0.5;
    colorPreview.layer.borderColor = UIColor.tertiaryLabelColor.CGColor;
    cell.accessoryView = colorPreview;
    
    NSLog(@"Table cell for row %ld: %@", (long)indexPath.row, systemColorName);
    return cell;
}

#pragma mark - UITableViewDelegate (Mac Catalyst alternative)

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self updateColorDisplay];
}

- (UIColor *)colorFromSelector:(NSString *)selectorName {
    SEL selector = NSSelectorFromString(selectorName);
    if ([UIColor respondsToSelector:selector]) {
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id result = [UIColor performSelector:selector];
#pragma clang diagnostic pop
            
            // Verify the result is a UIColor and not nil
            if (result && [result isKindOfClass:[UIColor class]]) {
                UIColor *colorResult = (UIColor *)result;
                // Additional validation - ensure CGColor is valid
                if (colorResult.CGColor) {
                    return colorResult;
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"Exception calling selector %@: %@", selectorName, exception);
        } @catch (...) {
            NSLog(@"Crash calling selector %@", selectorName);
        }
    }
    return nil;
}

- (void)updateColorDisplay {
    NSInteger selectedRow;
    
    if (self.isMacCatalyst) {
        NSIndexPath *selectedIndexPath = self.colorTableView.indexPathForSelectedRow;
        selectedRow = selectedIndexPath ? selectedIndexPath.row : 0;
    } else {
        selectedRow = [self.colorPicker selectedRowInComponent:0];
    }
    
    NSLog(@"updateColorDisplay called - selectedRow: %ld", (long)selectedRow);
    NSLog(@"systemColors count: %lu", (unsigned long)self.systemColors.count);
    NSLog(@"filteredSystemColors count: %lu", (unsigned long)self.filteredSystemColors.count);
    NSLog(@"filteredSystemColors: %@", self.filteredSystemColors);
    
    if (!self.filteredSystemColors || self.filteredSystemColors.count == 0) {
        NSLog(@"ERROR: filteredSystemColors is empty or nil!");
        return;
    }
    
    if (selectedRow >= 0 && selectedRow < self.filteredSystemColors.count) {
        NSString *selectorName = self.filteredSystemColors[selectedRow];
        NSLog(@"Selected selector: %@", selectorName);
        
        UIColor *selectedColor = [self colorFromSelector:selectorName];
        NSLog(@"Selected color: %@", selectedColor);
        
        if (!selectedColor) return;
        
        // Get all color variants
        NSDictionary *colorVariants = [self getAllColorVariants:selectedColor];
        
        // Clear existing variant views
        [self clearVariantViews];
        
        // Create new variant views for all detected variants
        [self createVariantViews:colorVariants];
        
        // Get the color name from the private property
        NSString *colorName = selectedColor.systemColorName ?: selectorName;
        
        // Update the color details with all variants
        [self updateColorDetails:selectedColor withName:colorName variants:colorVariants];
        
        // Generate the compat code with all variants
        [self generateCompatCode:selectedColor withName:selectorName variants:colorVariants];
    }
}

- (void)clearVariantViews {
    // Remove all existing variant views and labels
    for (UIView *view in self.variantColorViews) {
        [view removeFromSuperview];
    }
    for (UILabel *label in self.variantLabels) {
        [label removeFromSuperview];
    }
    
    [self.variantColorViews removeAllObjects];
    [self.variantLabels removeAllObjects];
}

- (void)createVariantViews:(NSDictionary *)colorVariants {
    NSArray *sortedKeys = [[colorVariants allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    NSLog(@"Creating variant views for %lu variants", (unsigned long)sortedKeys.count);
    
    CGFloat viewWidth = 85;
    CGFloat viewHeight = 45;
    CGFloat labelHeight = 28;
    CGFloat spacing = 8;
    CGFloat currentX = 8;
    
    for (NSString *variantKey in sortedKeys) {
        UIColor *variantColor = colorVariants[variantKey];
        
        // Create label for variant name
        UILabel *variantLabel = [[UILabel alloc] init];
        variantLabel.text = [self formatVariantNameShort:variantKey];
        variantLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
        variantLabel.textColor = UIColor.secondaryLabelColor;
        variantLabel.textAlignment = NSTextAlignmentCenter;
        variantLabel.numberOfLines = 3;
        variantLabel.lineBreakMode = NSLineBreakByWordWrapping;
        variantLabel.adjustsFontSizeToFitWidth = YES;
        variantLabel.minimumScaleFactor = 0.7;
        variantLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.colorDisplayContainerView addSubview:variantLabel];
        [self.variantLabels addObject:variantLabel];
        
        // Create color view for variant with EDR support
        UIView *variantColorView = [[UIView alloc] init];
        variantColorView.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Setup EDR-capable Metal layer for extended color range
        [self setupEDRLayerForView:variantColorView withColor:variantColor];
        
        variantColorView.layer.cornerRadius = 6;
        variantColorView.layer.borderWidth = 0.5;
        variantColorView.layer.borderColor = UIColor.tertiaryLabelColor.CGColor;
        
        // Store variant key BEFORE adding gesture (important!)
        objc_setAssociatedObject(variantColorView, @"variantKey", variantKey, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Add tap gesture to jump to corresponding section
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(variantColorViewTapped:)];
        [variantColorView addGestureRecognizer:tapGesture];
        variantColorView.userInteractionEnabled = YES;
        
        NSLog(@"Setup tap for variant: %@ on view: %p", variantKey, variantColorView);
        
        [self.colorDisplayContainerView addSubview:variantColorView];
        [self.variantColorViews addObject:variantColorView];
        
        // Set up constraints for this variant
        [NSLayoutConstraint activateConstraints:@[
            // Label constraints
            [variantLabel.topAnchor constraintEqualToAnchor:self.colorDisplayContainerView.topAnchor constant:4],
            [variantLabel.leadingAnchor constraintEqualToAnchor:self.colorDisplayContainerView.leadingAnchor constant:currentX],
            [variantLabel.widthAnchor constraintEqualToConstant:viewWidth],
            [variantLabel.heightAnchor constraintEqualToConstant:labelHeight],
            
            // Color view constraints
            [variantColorView.topAnchor constraintEqualToAnchor:variantLabel.bottomAnchor constant:3],
            [variantColorView.leadingAnchor constraintEqualToAnchor:self.colorDisplayContainerView.leadingAnchor constant:currentX],
            [variantColorView.widthAnchor constraintEqualToConstant:viewWidth],
            [variantColorView.heightAnchor constraintEqualToConstant:viewHeight]
        ]];
        
        currentX += viewWidth + spacing;
    }
    
    // Update container width to fit all variants
    CGFloat totalWidth = MAX(currentX - spacing + 8, self.colorDisplayScrollView.frame.size.width);
    
    // Deactivate old width constraint if exists
    if (self.containerWidthConstraint) {
        self.containerWidthConstraint.active = NO;
    }
    
    // Create and store new width constraint
    self.containerWidthConstraint = [self.colorDisplayContainerView.widthAnchor constraintEqualToConstant:totalWidth];
    self.containerWidthConstraint.active = YES;
    
    // Update scroll view content size
    self.colorDisplayScrollView.contentSize = CGSizeMake(totalWidth, 100);
    
    // Force layout to update bounds, then setup EDR layers
    [self.view layoutIfNeeded];
    
    // Now setup EDR layers with proper bounds
    for (UIView *variantView in self.variantColorViews) {
        NSString *keyBefore = objc_getAssociatedObject(variantView, @"variantKey");
        NSLog(@"Before layoutEDR - view %p has key: %@", variantView, keyBefore);
        
        [self layoutEDRLayerForView:variantView];
        
        NSString *keyAfter = objc_getAssociatedObject(variantView, @"variantKey");
        NSLog(@"After layoutEDR - view %p has key: %@", variantView, keyAfter);
    }
}

- (NSString *)formatVariantNameShort:(NSString *)variantKey {
    NSArray *components = [variantKey componentsSeparatedByString:@"_"];
    if (components.count != 4) return variantKey;
    
    NSString *style = [components[0] capitalizedString];
    NSString *idiomStr = components[1];
    NSString *gamut = [components[2] uppercaseString];
	NSString *contrast = [components[3] isEqualToString:@"standard"] ? @"" : [components[3] capitalizedString];
    
    // Create shorter idiom names
    NSString *idiom;
    if ([idiomStr isEqualToString:@"unspecified"]) {
        idiom = @"";
    } else if ([idiomStr isEqualToString:@"phone"]) {
        idiom = @" iPhone";
    } else if ([idiomStr isEqualToString:@"pad"]) {
        idiom = @" iPad";
    } else if ([idiomStr isEqualToString:@"tv"]) {
        idiom = @" TV";
    } else if ([idiomStr isEqualToString:@"carplay"]) {
        idiom = @" CarPlay";
    } else if ([idiomStr isEqualToString:@"mac"]) {
        idiom = @" Mac";
    } else {
        idiom = [idiomStr capitalizedString];
    }
    
    // Create compact display format based on user's formatting changes
    NSString *formattedText;
    
    if ([idiom isEqualToString:@""] && [gamut isEqualToString:@"SRGB"] && [contrast isEqualToString:@""]) {
        // Basic variant: just "Light" or "Dark"
        formattedText = style;
    } else if ([gamut isEqualToString:@"SRGB"] && [contrast isEqualToString:@""]) {
        // Style + idiom only
        formattedText = [NSString stringWithFormat:@"%@%@", style, idiom];
    } else if ([idiom isEqualToString:@""] && [gamut isEqualToString:@"SRGB"]) {
        // Style + contrast only
        formattedText = [NSString stringWithFormat:@"%@ %@", style, contrast];
    } else if ([contrast isEqualToString:@""]) {
        // Style + idiom + gamut
        formattedText = [NSString stringWithFormat:@"%@ %@\n%@", style, idiom, gamut];
    } else if ([idiom isEqualToString:@""]) {
        // Style + gamut + contrast
        formattedText = [NSString stringWithFormat:@"%@ %@ %@", style, gamut, contrast];
    } else {
        // All components
        formattedText = [NSString stringWithFormat:@"%@%@\n%@ %@", style, idiom, gamut, contrast];
    }
    
    return formattedText;
}

- (BOOL)isColorP3:(UIColor *)color {
    // Check UIColor's colorSpaceName property (more reliable than CGColorSpace name)
    NSString *colorSpaceName = [color valueForKey:@"colorSpaceName"];
    if (colorSpaceName && [colorSpaceName containsString:@"P3"]) {
        return YES;
    }
    
    // Fallback: check CGColorSpace name
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(color.CGColor);
    CFStringRef cgColorSpaceName = CGColorSpaceCopyName(colorSpace);
    if (cgColorSpaceName) {
        NSString *spaceName = (__bridge NSString *)cgColorSpaceName;
        BOOL isP3 = [spaceName containsString:@"DisplayP3"];
        CFRelease(cgColorSpaceName);
        return isP3;
    }
    
    return NO;
}

- (BOOL)getP3Components:(UIColor *)color red:(CGFloat *)outR green:(CGFloat *)outG blue:(CGFloat *)outB alpha:(CGFloat *)outA {
    if (!color) return NO;
    
    CGColorSpaceRef p3Space = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    if (!p3Space) return NO;
    
    CGColorRef converted = CGColorCreateCopyByMatchingToColorSpace(p3Space,
                                                                    kCGRenderingIntentDefault,
                                                                    color.CGColor,
                                                                    NULL);
    CGColorSpaceRelease(p3Space);
    
    if (!converted) return NO;
    
    size_t numComponents = CGColorGetNumberOfComponents(converted);
    const CGFloat *components = CGColorGetComponents(converted);
    
    if (components && (numComponents == 4 || numComponents == 2)) {
        if (numComponents == 4) {
            *outR = components[0];
            *outG = components[1];
            *outB = components[2];
            *outA = components[3];
        } else {
            // Grayscale + alpha
            CGFloat gray = components[0];
            *outR = gray;
            *outG = gray;
            *outB = gray;
            *outA = components[1];
        }
        CGColorRelease(converted);
        return YES;
    }
    
    CGColorRelease(converted);
    return NO;
}

- (BOOL)isColorExtendedRange:(UIColor *)color {
    // Check if any color component exceeds 1.0 or is below 0.0 (extended range)
    // This is the ONLY reliable way to detect extended range - not the colorspace name!
    const CGFloat *components = CGColorGetComponents(color.CGColor);
    size_t numComponents = CGColorGetNumberOfComponents(color.CGColor);
    
    BOOL hasExtendedValues = NO;
    const CGFloat tolerance = 0.0001; // Small tolerance for floating point
    
    for (size_t i = 0; i < numComponents; i++) {
        if (components[i] > (1.0 + tolerance) || components[i] < (0.0 - tolerance)) {
            hasExtendedValues = YES;
            break;
        }
    }
    
    return hasExtendedValues;
}

- (void)setupEDRLayerForView:(UIView *)view withColor:(UIColor *)color {
    BOOL isExtendedRange = [self isColorExtendedRange:color];
    
    // Check if this is a P3 color using the reliable method
    BOOL useP3 = [self isColorP3:color];
    
#if !TARGET_OS_SIMULATOR
    // On real devices, use Metal layer for EDR support
    if (isExtendedRange && self.metalDevice) {
        // Store color and setup info for later layout
        objc_setAssociatedObject(view, @"edrColor", color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, @"useP3", @(useP3), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, @"useEDR", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Set a placeholder background
        view.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.1];
        
        // Add visual indicator that EDR is active
        view.layer.borderWidth = 1.5;
        view.layer.borderColor = UIColor.systemOrangeColor.CGColor;
        
        return;
    }
#endif
    
    // For Simulator, Mac Catalyst, or non-EDR colors
    if (isExtendedRange) {
        // Store color info for deferred setup
        objc_setAssociatedObject(view, @"edrColor", color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, @"useP3", @(useP3), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, @"useEDR", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Add visual indicator that this is an extended range color (shown without true EDR)
        view.layer.borderWidth = 1.5;
        view.layer.borderColor = UIColor.systemYellowColor.CGColor; // Yellow for simulated EDR
    } else {
        // For standard colors, set background immediately
        view.backgroundColor = color;
        
        // Mark as non-EDR so layoutEDRLayerForView won't process it
        objc_setAssociatedObject(view, @"useEDR", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)layoutEDRLayerForView:(UIView *)view {
    UIColor *edrColor = objc_getAssociatedObject(view, @"edrColor");
    NSNumber *useP3Num = objc_getAssociatedObject(view, @"useP3");
    NSNumber *useEDRNum = objc_getAssociatedObject(view, @"useEDR");
    
    if (!edrColor || ![useEDRNum boolValue]) return;
    
    BOOL useP3 = [useP3Num boolValue];
    
    // Remove old layers
    CALayer *oldLayer = objc_getAssociatedObject(view, @"metalLayer");
    if (oldLayer) {
        [oldLayer removeFromSuperlayer];
    }
    
#if !TARGET_OS_SIMULATOR
    // On real devices, use Metal layer for EDR support
    if (self.metalDevice) {
        CAMetalLayer *metalLayer = [CAMetalLayer layer];
        metalLayer.device = self.metalDevice;
        metalLayer.wantsExtendedDynamicRangeContent = YES;
        metalLayer.pixelFormat = MTLPixelFormatBGR10A2Unorm; // 10-bit per channel
        metalLayer.opaque = NO;
        
        // Set appropriate color space
        CGColorSpaceRef edrColorSpace;
        if (useP3) {
            edrColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedDisplayP3);
        } else {
            edrColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
        }
        
        if (edrColorSpace) {
            metalLayer.colorspace = edrColorSpace;
            CGColorSpaceRelease(edrColorSpace);
        }
        
        metalLayer.frame = view.bounds;
        metalLayer.backgroundColor = edrColor.CGColor;
        
        // Important: Insert at index 0 so it doesn't block user interaction
        if (view.layer.sublayers.count > 0) {
            [view.layer insertSublayer:metalLayer atIndex:0];
        } else {
            [view.layer addSublayer:metalLayer];
        }
        
        // Store the metal layer as associated object
        objc_setAssociatedObject(view, @"metalLayer", metalLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        return;
    }
#endif
    
    // Fallback for Simulator/Catalyst - use extended color space layer
    CALayer *edrLayer = [CALayer layer];
    
    // Set appropriate extended color space
    CGColorSpaceRef edrColorSpace;
    if (useP3) {
        edrColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedDisplayP3);
    } else {
        edrColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
    }
    
    if (edrColorSpace) {
        // Create a new CGColor in the extended color space
        const CGFloat *components = CGColorGetComponents(edrColor.CGColor);
        size_t numComponents = CGColorGetNumberOfComponents(edrColor.CGColor);
        CGColorRef extendedColor = CGColorCreate(edrColorSpace, components);
        
        edrLayer.backgroundColor = extendedColor;
        edrLayer.frame = view.bounds;
        
        CGColorRelease(extendedColor);
        CGColorSpaceRelease(edrColorSpace);
        
        // Important: Insert at index 0 so it doesn't block user interaction
        if (view.layer.sublayers.count > 0) {
            [view.layer insertSublayer:edrLayer atIndex:0];
        } else {
            [view.layer addSublayer:edrLayer];
        }
        
        // Store the layer as associated object
        objc_setAssociatedObject(view, @"metalLayer", edrLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        // Final fallback - use the original color
        view.backgroundColor = edrColor;
    }
}

- (NSDictionary *)getAllColorVariants:(UIColor *)color {
    NSMutableDictionary *allVariants = [NSMutableDictionary dictionary];
    NSMutableDictionary *uniqueColors = [NSMutableDictionary dictionary];
    
    // Define all possible trait collection combinations
    NSArray *userInterfaceStyles = @[
        @(UIUserInterfaceStyleLight),
        @(UIUserInterfaceStyleDark)
    ];
    
    NSArray *userInterfaceIdioms = @[
        @(UIUserInterfaceIdiomUnspecified),
        @(UIUserInterfaceIdiomPhone),
        @(UIUserInterfaceIdiomPad),
        @(UIUserInterfaceIdiomTV),
        @(UIUserInterfaceIdiomCarPlay),
        @(UIUserInterfaceIdiomMac)
    ];
    
    NSArray *displayGamuts = @[
        @(UIDisplayGamutSRGB),
        @(UIDisplayGamutP3)
    ];
    
    NSArray *accessibilityContrasts = @[
        @(UIAccessibilityContrastNormal),
        @(UIAccessibilityContrastHigh)
    ];
    
    // Get the default/baseline color (light, unspecified, sRGB, normal contrast)
    UITraitCollection *defaultTrait = [self createTraitCollection:UIUserInterfaceStyleLight
                                                           idiom:UIUserInterfaceIdiomUnspecified
                                                          gamut:UIDisplayGamutSRGB
                                                       contrast:UIAccessibilityContrastNormal];
    UIColor *defaultColor = [color resolvedColorWithTraitCollection:defaultTrait];
    
    // Test all combinations and collect all variants
    for (NSNumber *styleNum in userInterfaceStyles) {
        UIUserInterfaceStyle style = [styleNum integerValue];
        NSString *styleStr = (style == UIUserInterfaceStyleDark) ? @"dark" : @"light";
        
        for (NSNumber *idiomNum in userInterfaceIdioms) {
            UIUserInterfaceIdiom idiom = [idiomNum integerValue];
            NSString *idiomStr = [self idiomToString:idiom];
            
            for (NSNumber *gamutNum in displayGamuts) {
                UIDisplayGamut gamut = [gamutNum integerValue];
                NSString *gamutStr = (gamut == UIDisplayGamutP3) ? @"p3" : @"srgb";
                
                for (NSNumber *contrastNum in accessibilityContrasts) {
                    UIAccessibilityContrast contrast = [contrastNum integerValue];
                    NSString *contrastStr = (contrast == UIAccessibilityContrastHigh) ? @"high" : @"standard";
                    
                    // Create trait collection for this combination
                    UITraitCollection *trait = [self createTraitCollection:style idiom:idiom gamut:gamut contrast:contrast];
                    UIColor *resolvedColor = [color resolvedColorWithTraitCollection:trait];
                    
                    // Create variant key
                    NSString *variantKey = [NSString stringWithFormat:@"%@_%@_%@_%@", styleStr, idiomStr, gamutStr, contrastStr];
                    
                    // Store all variants for analysis
                    allVariants[variantKey] = resolvedColor;
                }
            }
        }
    }
    
    // Now intelligently filter variants
    return [self filterSignificantVariants:allVariants defaultColor:defaultColor];
}

- (UITraitCollection *)createTraitCollection:(UIUserInterfaceStyle)style
                                       idiom:(UIUserInterfaceIdiom)idiom
                                       gamut:(UIDisplayGamut)gamut
                                    contrast:(UIAccessibilityContrast)contrast {
    NSArray *traits = @[
        [UITraitCollection traitCollectionWithUserInterfaceStyle:style],
        [UITraitCollection traitCollectionWithUserInterfaceIdiom:idiom],
        [UITraitCollection traitCollectionWithDisplayGamut:gamut],
        [UITraitCollection traitCollectionWithAccessibilityContrast:contrast]
    ];
    
    return [UITraitCollection traitCollectionWithTraitsFromCollections:traits];
}

- (NSDictionary *)filterSignificantVariants:(NSDictionary *)allVariants defaultColor:(UIColor *)defaultColor {
    NSMutableDictionary *filteredVariants = [NSMutableDictionary dictionary];
    NSMutableDictionary *colorToKeys = [NSMutableDictionary dictionary];
    
    // Group variants by their actual color values
    for (NSString *variantKey in allVariants.allKeys) {
        UIColor *variantColor = allVariants[variantKey];
        NSString *colorKey = [self colorToKey:variantColor];
        
        NSMutableArray *keysForColor = colorToKeys[colorKey];
        if (!keysForColor) {
            keysForColor = [NSMutableArray array];
            colorToKeys[colorKey] = keysForColor;
        }
        [keysForColor addObject:variantKey];
    }
    
    // For each unique color, determine the most representative variant key
    for (NSString *colorKey in colorToKeys.allKeys) {
        NSArray *variantKeys = colorToKeys[colorKey];
        UIColor *color = allVariants[variantKeys.firstObject];
        
        // Skip if this color is the same as default
        if ([self colorsAreEqual:color to:defaultColor]) {
            // Always include the baseline variant
            if ([variantKeys containsObject:@"light_unspecified_srgb_standard"]) {
                filteredVariants[@"light_unspecified_srgb_standard"] = color;
            }
            continue;
        }
        
        // Find the most representative key for this unique color
        NSString *bestKey = [self selectBestVariantKey:variantKeys];
        filteredVariants[bestKey] = color;
    }
    
    // Ensure we always have the baseline
    if (!filteredVariants[@"light_unspecified_srgb_standard"]) {
        filteredVariants[@"light_unspecified_srgb_standard"] = defaultColor;
    }
    
    return [filteredVariants copy];
}

- (NSString *)colorToKey:(UIColor *)color {
    CGFloat red, green, blue, alpha;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    
    // Create a key with sufficient precision for comparison
    return [NSString stringWithFormat:@"%.6f_%.6f_%.6f_%.6f", red, green, blue, alpha];
}

- (NSString *)selectBestVariantKey:(NSArray *)variantKeys {
    // Priority rules for selecting the best representative key:
    // 1. Prefer sRGB over P3 (if colors are identical)
    // 2. Prefer unspecified idiom over specific idioms (if colors are identical)
    // 3. Prefer standard contrast over high contrast (if colors are identical)
    // 4. Prefer light over dark (for baseline comparison)
    
    NSString *bestKey = variantKeys.firstObject;
    
    for (NSString *key in variantKeys) {
        NSArray *components = [key componentsSeparatedByString:@"_"];
        NSArray *bestComponents = [bestKey componentsSeparatedByString:@"_"];
        
        if (components.count != 4 || bestComponents.count != 4) continue;
        
        NSString *style = components[0];
        NSString *idiom = components[1];
        NSString *gamut = components[2];
        NSString *contrast = components[3];
        
        NSString *bestStyle = bestComponents[0];
        NSString *bestIdiom = bestComponents[1];
        NSString *bestGamut = bestComponents[2];
        NSString *bestContrast = bestComponents[3];
        
        BOOL isBetter = NO;
        
        // Rule 1: Prefer sRGB over P3
        if ([gamut isEqualToString:@"srgb"] && [bestGamut isEqualToString:@"p3"]) {
            isBetter = YES;
        } else if ([gamut isEqualToString:@"p3"] && [bestGamut isEqualToString:@"srgb"]) {
            continue; // Current is worse
        }
        
        // Rule 2: Prefer unspecified idiom
        else if ([idiom isEqualToString:@"unspecified"] && ![bestIdiom isEqualToString:@"unspecified"]) {
            isBetter = YES;
        } else if (![idiom isEqualToString:@"unspecified"] && [bestIdiom isEqualToString:@"unspecified"]) {
            continue; // Current is worse
        }
        
        // Rule 3: Prefer standard contrast
        else if ([contrast isEqualToString:@"standard"] && [bestContrast isEqualToString:@"high"]) {
            isBetter = YES;
        } else if ([contrast isEqualToString:@"high"] && [bestContrast isEqualToString:@"standard"]) {
            continue; // Current is worse
        }
        
        // Rule 4: Prefer light over dark for baseline
        else if ([style isEqualToString:@"light"] && [bestStyle isEqualToString:@"dark"]) {
            isBetter = YES;
        }
        
        if (isBetter) {
            bestKey = key;
        }
    }
    
    return bestKey;
}

- (NSString *)idiomToString:(UIUserInterfaceIdiom)idiom {
    switch (idiom) {
        case UIUserInterfaceIdiomUnspecified:
            return @"unspecified";
        case UIUserInterfaceIdiomPhone:
            return @"phone";
        case UIUserInterfaceIdiomPad:
            return @"pad";
        case UIUserInterfaceIdiomTV:
            return @"tv";
        case UIUserInterfaceIdiomCarPlay:
            return @"carplay";
        case UIUserInterfaceIdiomMac:
            return @"mac";
        default:
            return @"unknown";
    }
}

- (BOOL)colorsAreEqual:(UIColor *)color1 to:(UIColor *)color2 {
    CGFloat r1, g1, b1, a1;
    CGFloat r2, g2, b2, a2;
    
    [color1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [color2 getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    
    const CGFloat tolerance = 0.001;
    return (fabs(r1 - r2) < tolerance &&
            fabs(g1 - g2) < tolerance &&
            fabs(b1 - b2) < tolerance &&
            fabs(a1 - a2) < tolerance);
}

- (void)updateColorDetails:(UIColor *)color withName:(NSString *)name variants:(NSDictionary *)variants {
    NSMutableString *details = [NSMutableString string];
    
    [details appendFormat:@"Color Name: %@\n", name];
    
    // Check if color uses extended range
    BOOL isExtendedRange = [self isColorExtendedRange:color];
    if (isExtendedRange) {
        [details appendString:@"⚠️ EXTENDED DYNAMIC RANGE (EDR/HDR)\n"];
#if TARGET_OS_SIMULATOR
        [details appendString:@"Running on Simulator - EDR shown with extended colorspace (clamped)\n"];
#else
        if (self.metalDevice) {
            [details appendString:@"Using Metal layer with 10-bit BGR10A2 format\n"];
        } else {
            [details appendString:@"Metal device unavailable - using extended colorspace layer\n"];
        }
#endif
    }
    
    [details appendString:@"\n"];
    
    // Get current trait collection info
    UITraitCollection *currentTrait = self.traitCollection;
    NSString *currentStyle = currentTrait.userInterfaceStyle == UIUserInterfaceStyleDark ? @"Dark" : @"Light";
    NSString *currentIdiom = currentTrait.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
    NSString *currentGamut = currentTrait.displayGamut == UIDisplayGamutP3 ? @"P3" : @"sRGB";
    NSString *currentContrast = currentTrait.accessibilityContrast == UIAccessibilityContrastHigh ? @"High" : @"Normal";
    
    [details appendFormat:@"Current Trait Collection:\n"];
    [details appendFormat:@"  Style: %@\n", currentStyle];
    [details appendFormat:@"  Idiom: %@\n", currentIdiom];
    [details appendFormat:@"  Gamut: %@\n", currentGamut];
    [details appendFormat:@"  Contrast: %@\n", currentContrast];
    [details appendString:@"\n"];
    
    // Display variant count
    [details appendFormat:@"Total Color Variants Found: %lu\n", (unsigned long)variants.count];
    [details appendString:@"\n"];
    
    // Helper block to add color details for a specific variant
    void (^addVariantDetails)(UIColor *, NSString *) = ^(UIColor *resolvedColor, NSString *variantName) {
        [details appendFormat:@"=== %@ ===\n", [variantName uppercaseString]];
        
        // Get the color space information
        CGColorSpaceRef colorSpace = CGColorGetColorSpace(resolvedColor.CGColor);
        CFStringRef colorSpaceName = CGColorSpaceCopyName(colorSpace);
        NSString *spaceName = colorSpaceName ? (__bridge NSString *)colorSpaceName : @"Unknown";
        BOOL isP3 = [spaceName containsString:@"P3"];
        BOOL isExtendedSpace = [spaceName containsString:@"Extended"];
        
        // Check if this variant is extended range
        BOOL variantIsEDR = [self isColorExtendedRange:resolvedColor];
        if (variantIsEDR) {
            [details appendString:@"[Extended Dynamic Range]\n"];
        }
        
        // Get RGB components in the NATIVE colorspace to avoid conversion artifacts
        const CGFloat *components = CGColorGetComponents(resolvedColor.CGColor);
        size_t numComponents = CGColorGetNumberOfComponents(resolvedColor.CGColor);
        
        CGFloat red, green, blue, alpha;
        
        // Check if this is a P3 color using UIColor's colorSpaceName
        BOOL isP3Color = [self isColorP3:resolvedColor];
        
        if (isP3Color) {
            // For P3 colors, get the CORRECT P3 components using conversion
            if ([self getP3Components:resolvedColor red:&red green:&green blue:&blue alpha:&alpha]) {
                [details appendString:@"Display P3 Values (Native):\n"];
                [details appendFormat:@"  Red: %.6f (%.0f)\n", red, red * 255.0];
                [details appendFormat:@"  Green: %.6f (%.0f)\n", green, green * 255.0];
                [details appendFormat:@"  Blue: %.6f (%.0f)\n", blue, blue * 255.0];
                [details appendFormat:@"  Alpha: %.6f\n", alpha];
                [details appendFormat:@"  Hex: #%02X%02X%02X\n", (int)(red * 255), (int)(green * 255), (int)(blue * 255)];
                [details appendString:@"\n"];
            }
            
            // Also show sRGB conversion for reference (shows what happens when converted)
            CGFloat sRGBRed, sRGBGreen, sRGBBlue, sRGBAlpha;
            if ([resolvedColor getRed:&sRGBRed green:&sRGBGreen blue:&sRGBBlue alpha:&sRGBAlpha]) {
                [details appendString:@"sRGB Values (Converted from P3):\n"];
                [details appendFormat:@"  Red: %.6f (%.0f)", sRGBRed, sRGBRed * 255.0];
                if (sRGBRed > 1.0 || sRGBRed < 0.0) [details appendString:@" ⚠️ OUT OF GAMUT"];
                [details appendString:@"\n"];
                
                [details appendFormat:@"  Green: %.6f (%.0f)", sRGBGreen, sRGBGreen * 255.0];
                if (sRGBGreen > 1.0 || sRGBGreen < 0.0) [details appendString:@" ⚠️ OUT OF GAMUT"];
                [details appendString:@"\n"];
                
                [details appendFormat:@"  Blue: %.6f (%.0f)", sRGBBlue, sRGBBlue * 255.0];
                if (sRGBBlue > 1.0 || sRGBBlue < 0.0) [details appendString:@" ⚠️ OUT OF GAMUT"];
                [details appendString:@"\n"];
                
                int clampedRed = (int)fmax(0, fmin(255, sRGBRed * 255));
                int clampedGreen = (int)fmax(0, fmin(255, sRGBGreen * 255));
                int clampedBlue = (int)fmax(0, fmin(255, sRGBBlue * 255));
                [details appendFormat:@"  Hex (clamped): #%02X%02X%02X\n", clampedRed, clampedGreen, clampedBlue];
            }
            [details appendString:@"\n"];
        } else if (numComponents >= 4) {
            // For sRGB/Extended colors, getRed works correctly
            if ([resolvedColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
                [details appendString:@"RGB Values:\n"];
                [details appendFormat:@"  Red: %.6f (%.0f)", red, red * 255.0];
                if (red > 1.0 || red < 0.0) [details appendString:@" ⚠️ OUT OF RANGE"];
                [details appendString:@"\n"];
                
                [details appendFormat:@"  Green: %.6f (%.0f)", green, green * 255.0];
                if (green > 1.0 || green < 0.0) [details appendString:@" ⚠️ OUT OF RANGE"];
                [details appendString:@"\n"];
                
                [details appendFormat:@"  Blue: %.6f (%.0f)", blue, blue * 255.0];
                if (blue > 1.0 || blue < 0.0) [details appendString:@" ⚠️ OUT OF RANGE"];
                [details appendString:@"\n"];
                
                [details appendFormat:@"  Alpha: %.6f\n", alpha];
                
                // For extended range colors, show clamped hex
                int clampedRed = (int)fmax(0, fmin(255, red * 255));
                int clampedGreen = (int)fmax(0, fmin(255, green * 255));
                int clampedBlue = (int)fmax(0, fmin(255, blue * 255));
                [details appendFormat:@"  Hex (clamped): #%02X%02X%02X", clampedRed, clampedGreen, clampedBlue];
                if (variantIsEDR) [details appendString:@" (values clamped to 0-255)"];
                [details appendString:@"\n\n"];
            }
        } else if (numComponents >= 2) {
            // Grayscale color
            [details appendString:@"Grayscale Values:\n"];
            [details appendFormat:@"  White: %.6f (%.0f)\n", components[0], components[0] * 255.0];
            [details appendFormat:@"  Alpha: %.6f\n", components[1]];
            [details appendString:@"\n"];
        }
        
        if (colorSpaceName) {
            CFRelease(colorSpaceName);
        }
        
        // Extract HSB components
        CGFloat hue, saturation, brightness;
        if ([resolvedColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
            [details appendString:@"HSB Values:\n"];
            [details appendFormat:@"  Hue: %.6f (%.1f°)\n", hue, hue * 360.0];
            [details appendFormat:@"  Saturation: %.6f (%.1f%%)\n", saturation, saturation * 100.0];
            [details appendFormat:@"  Brightness: %.6f (%.1f%%)\n", brightness, brightness * 100.0];
            [details appendString:@"\n"];
        }
        
        // Color space information
        colorSpace = CGColorGetColorSpace(resolvedColor.CGColor);
        if (colorSpace) {
            CFStringRef colorSpaceName = CGColorSpaceCopyName(colorSpace);
            if (colorSpaceName) {
                [details appendFormat:@"Color Space: %@\n", (__bridge NSString *)colorSpaceName];
                CFRelease(colorSpaceName);
            }
        }
        [details appendString:@"\n"];
    };
    
    // Sort variant keys for consistent display
    NSArray *sortedKeys = [[variants allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    // Add details for each variant
    for (NSString *variantKey in sortedKeys) {
        UIColor *variantColor = variants[variantKey];
        NSString *displayName = [self formatVariantName:variantKey];
        addVariantDetails(variantColor, displayName);
    }
    
    // Add comparison section if there are multiple variants
    if (variants.count > 1) {
        [details appendString:@"=== VARIANT ANALYSIS ===\n"];
        
        UIColor *baseColor = variants[@"light_unspecified_srgb_standard"];
        if (baseColor) {
            CGFloat baseRed, baseGreen, baseBlue, baseAlpha;
            [baseColor getRed:&baseRed green:&baseGreen blue:&baseBlue alpha:&baseAlpha];
            
            for (NSString *variantKey in sortedKeys) {
                if ([variantKey isEqualToString:@"light_unspecified_srgb_standard"]) continue;
                
                UIColor *variantColor = variants[variantKey];
                CGFloat varRed, varGreen, varBlue, varAlpha;
                [variantColor getRed:&varRed green:&varGreen blue:&varBlue alpha:&varAlpha];
                
                CGFloat colorDistance = sqrt(pow(varRed - baseRed, 2) + pow(varGreen - baseGreen, 2) + pow(varBlue - baseBlue, 2));
                
                [details appendFormat:@"%@:\n", [self formatVariantName:variantKey]];
                [details appendFormat:@"  ΔRed: %+.6f (%+.0f)\n", varRed - baseRed, (varRed - baseRed) * 255.0];
                [details appendFormat:@"  ΔGreen: %+.6f (%+.0f)\n", varGreen - baseGreen, (varGreen - baseGreen) * 255.0];
                [details appendFormat:@"  ΔBlue: %+.6f (%+.0f)\n", varBlue - baseBlue, (varBlue - baseBlue) * 255.0];
                [details appendFormat:@"  Distance: %.6f\n", colorDistance];
                [details appendString:@"\n"];
            }
        }
    }
    
    self.colorDetailsTextView.text = details;
}

- (NSString *)formatVariantName:(NSString *)variantKey {
    NSArray *components = [variantKey componentsSeparatedByString:@"_"];
    if (components.count != 4) return variantKey;
    
    NSString *style = [components[0] capitalizedString];
    NSString *idiomStr = components[1];
    NSString *idiom;
    
    if ([idiomStr isEqualToString:@"unspecified"]) {
        idiom = @"";
    } else if ([idiomStr isEqualToString:@"phone"]) {
        idiom = @" iPhone";
    } else if ([idiomStr isEqualToString:@"pad"]) {
        idiom = @" iPad";
    } else if ([idiomStr isEqualToString:@"tv"]) {
        idiom = @" Apple TV";
    } else if ([idiomStr isEqualToString:@"carplay"]) {
        idiom = @" CarPlay";
    } else if ([idiomStr isEqualToString:@"mac"]) {
        idiom = @" Mac";
    } else {
        idiom = [idiomStr capitalizedString];
    }
    
    NSString *gamut = [components[2] uppercaseString];
	NSString *contrast = [components[3] isEqualToString:@"standard"] ? @"" : @" High";
    
    return [NSString stringWithFormat:@"%@%@ %@%@", style, idiom, gamut, contrast];
}

- (void)generateCompatCode:(UIColor *)color withName:(NSString *)name variants:(NSDictionary *)variants {
    // Generate function name
    NSString *functionName = [self generateCompatFunctionName:name];
    
    NSMutableString *code = [NSMutableString string];
    
    // Add header comment
    [code appendFormat:@"// Generated iOS 12+ compatible function for %@\n", name];
    [code appendFormat:@"// Found %lu distinct color variants\n", (unsigned long)variants.count];
    [code appendString:@"// Supports all trait collection combinations\n"];
    [code appendString:@"\n"];
    
    // Function signature
    [code appendFormat:@"+ (instancetype)%@ {\n", functionName];
    
    // Add iOS 13+ availability check first
    [code appendString:@"    if (@available(iOS 13.0, *)) {\n"];
    [code appendFormat:@"        return UIColor.%@;\n", name];
    [code appendString:@"    }\n"];
    [code appendString:@"\n"];
    
    if (variants.count > 1) {
        // Generate comprehensive trait collection detection
        [code appendString:@"    // iOS 12 compatible comprehensive trait collection detection\n"];
        [code appendString:@"    UITraitCollection *currentTrait = [UIScreen mainScreen].traitCollection;\n"];
        [code appendString:@"    \n"];
        [code appendString:@"    // Extract trait collection properties\n"];
        [code appendString:@"    UIUserInterfaceStyle style = UIUserInterfaceStyleLight;\n"];
        [code appendString:@"    UIUserInterfaceIdiom idiom = UIUserInterfaceIdiomUnspecified;\n"];
        [code appendString:@"    UIDisplayGamut gamut = UIDisplayGamutSRGB;\n"];
        [code appendString:@"    UIAccessibilityContrast contrast = UIAccessibilityContrastNormal;\n"];
        [code appendString:@"    \n"];
        [code appendString:@"    if (@available(iOS 12.0, *)) {\n"];
        [code appendString:@"        style = currentTrait.userInterfaceStyle;\n"];
        [code appendString:@"        idiom = currentTrait.userInterfaceIdiom;\n"];
        [code appendString:@"        if (@available(iOS 10.0, *)) {\n"];
        [code appendString:@"            gamut = currentTrait.displayGamut;\n"];
        [code appendString:@"        }\n"];
        [code appendString:@"        if (@available(iOS 13.0, *)) {\n"];
        [code appendString:@"            contrast = currentTrait.accessibilityContrast;\n"];
        [code appendString:@"        }\n"];
        [code appendString:@"    }\n"];
        [code appendString:@"    \n"];
        
        // Generate decision tree for variants
        [self generateVariantDecisionTree:code variants:variants];
        
    } else {
        // Single variant - static color
        [code appendString:@"    // Static color - single variant\n"];
        UIColor *singleColor = [[variants allValues] firstObject];
        [self appendColorCreationCodeFromColor:code color:singleColor comment:@"Static color"];
    }
    
    [code appendString:@"}\n"];
    
    // Add usage example
    [code appendString:@"\n"];
    [code appendString:@"// Usage example:\n"];
    [code appendFormat:@"// UIColor *myColor = [UIColor %@];\n", functionName];
    [code appendFormat:@"// self.view.backgroundColor = [UIColor %@];\n", functionName];
    
    // Add variant information
    [code appendString:@"\n"];
    [code appendString:@"// Color variants found:\n"];
    NSArray *sortedKeys = [[variants allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *variantKey in sortedKeys) {
        UIColor *variantColor = variants[variantKey];
        CGFloat red, green, blue, alpha;
        [variantColor getRed:&red green:&green blue:&blue alpha:&alpha];
        [code appendFormat:@"// %@: R:%.3f G:%.3f B:%.3f A:%.3f\n", 
         [self formatVariantName:variantKey], red, green, blue, alpha];
    }
    
    self.codeGeneratorTextView.text = code;
}

- (void)generateVariantDecisionTree:(NSMutableString *)code variants:(NSDictionary *)variants {
    // Group variants by style first (most common distinction)
    NSMutableDictionary *lightVariants = [NSMutableDictionary dictionary];
    NSMutableDictionary *darkVariants = [NSMutableDictionary dictionary];
    
    for (NSString *variantKey in variants.allKeys) {
        if ([variantKey hasPrefix:@"light_"]) {
            lightVariants[variantKey] = variants[variantKey];
        } else if ([variantKey hasPrefix:@"dark_"]) {
            darkVariants[variantKey] = variants[variantKey];
        }
    }
    
    [code appendString:@"    // Style-based branching\n"];
    [code appendString:@"    if (style == UIUserInterfaceStyleDark) {\n"];
    
    if (darkVariants.count > 1) {
        [self generateSubVariantCode:code variants:darkVariants indent:@"        "];
    } else if (darkVariants.count == 1) {
        UIColor *darkColor = [[darkVariants allValues] firstObject];
        [self appendColorCreationCodeFromColor:code color:darkColor comment:@"Dark mode" indent:@"        "];
    } else {
        // Fallback to light variant
        UIColor *lightColor = [[lightVariants allValues] firstObject];
        [self appendColorCreationCodeFromColor:code color:lightColor comment:@"Dark mode fallback" indent:@"        "];
    }
    
    [code appendString:@"    } else {\n"];
    
    if (lightVariants.count > 1) {
        [self generateSubVariantCode:code variants:lightVariants indent:@"        "];
    } else if (lightVariants.count == 1) {
        UIColor *lightColor = [[lightVariants allValues] firstObject];
        [self appendColorCreationCodeFromColor:code color:lightColor comment:@"Light mode" indent:@"        "];
    } else {
        // This shouldn't happen, but provide a fallback
        UIColor *fallbackColor = [[variants allValues] firstObject];
        [self appendColorCreationCodeFromColor:code color:fallbackColor comment:@"Light mode fallback" indent:@"        "];
    }
    
    [code appendString:@"    }\n"];
}

- (void)generateSubVariantCode:(NSMutableString *)code variants:(NSDictionary *)variants indent:(NSString *)indent {
    // Further subdivide by idiom, gamut, and contrast
    NSArray *sortedKeys = [[variants allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    if (variants.count == 1) {
        UIColor *color = [[variants allValues] firstObject];
        [self appendColorCreationCodeFromColor:code color:color comment:@"Single variant" indent:indent];
        return;
    }
    
    // Check if variants differ by idiom
    NSMutableSet *idioms = [NSMutableSet set];
    for (NSString *key in sortedKeys) {
        NSArray *components = [key componentsSeparatedByString:@"_"];
        if (components.count >= 2) {
            [idioms addObject:components[1]];
        }
    }
    
    if (idioms.count > 1) {
        [code appendFormat:@"%s// Idiom-based branching\n", [indent UTF8String]];
        
        // Generate switch-like structure for multiple idioms
        NSArray *idiomPriority = @[@"mac", @"pad", @"tv", @"carplay", @"phone", @"unspecified"];
        BOOL firstCondition = YES;
        
        for (NSString *idiomType in idiomPriority) {
            if (![idioms containsObject:idiomType]) continue;
            
            NSMutableDictionary *idiomVariants = [NSMutableDictionary dictionary];
            for (NSString *key in sortedKeys) {
                if ([key containsString:[NSString stringWithFormat:@"_%@_", idiomType]]) {
                    idiomVariants[key] = variants[key];
                }
            }
            
            if (idiomVariants.count == 0) continue;
            
            NSString *condition;
            NSString *comment;
            
            if ([idiomType isEqualToString:@"unspecified"]) {
                condition = @"UIUserInterfaceIdiomUnspecified";
                comment = @"Unspecified idiom";
            } else if ([idiomType isEqualToString:@"phone"]) {
                condition = @"UIUserInterfaceIdiomPhone";
                comment = @"iPhone";
            } else if ([idiomType isEqualToString:@"pad"]) {
                condition = @"UIUserInterfaceIdiomPad";
                comment = @"iPad";
            } else if ([idiomType isEqualToString:@"tv"]) {
                condition = @"UIUserInterfaceIdiomTV";
                comment = @"Apple TV";
            } else if ([idiomType isEqualToString:@"carplay"]) {
                condition = @"UIUserInterfaceIdiomCarPlay";
                comment = @"CarPlay";
            } else if ([idiomType isEqualToString:@"mac"]) {
                condition = @"UIUserInterfaceIdiomMac";
                comment = @"Mac";
            } else {
                continue;
            }
            
            if (firstCondition) {
                [code appendFormat:@"%sif (idiom == %@) {\n", [indent UTF8String], condition];
                firstCondition = NO;
            } else {
                [code appendFormat:@"%s} else if (idiom == %@) {\n", [indent UTF8String], condition];
            }
            
            [self generateFinalVariantSelection:code variants:idiomVariants indent:[indent stringByAppendingString:@"    "]];
        }
        
        // Add final else clause with fallback
        [code appendFormat:@"%s} else {\n", [indent UTF8String]];
        UIColor *fallbackColor = [[variants allValues] firstObject];
        [self appendColorCreationCodeFromColor:code color:fallbackColor comment:@"Fallback for unknown idiom" indent:[indent stringByAppendingString:@"    "]];
        [code appendFormat:@"%s}\n", [indent UTF8String]];
    } else {
        [self generateFinalVariantSelection:code variants:variants indent:indent];
    }
}

- (void)generateFinalVariantSelection:(NSMutableString *)code variants:(NSDictionary *)variants indent:(NSString *)indent {
    if (variants.count == 1) {
        UIColor *color = [[variants allValues] firstObject];
        NSString *variantKey = [[variants allKeys] firstObject];
        NSString *comment = [self formatVariantName:variantKey];
        [self appendColorCreationCodeFromColor:code color:color comment:comment indent:indent];
        return;
    }
    
    // Check for contrast differences first (most specific)
    NSMutableSet *contrasts = [NSMutableSet set];
    for (NSString *key in variants.allKeys) {
        NSArray *components = [key componentsSeparatedByString:@"_"];
        if (components.count >= 4) {
            [contrasts addObject:components[3]];
        }
    }
    
    if (contrasts.count > 1) {
        [code appendFormat:@"%@// Contrast-based selection\n", indent];
        [code appendFormat:@"%@if (contrast == UIAccessibilityContrastHigh) {\n", indent];
        
        // Filter high contrast variants
        NSMutableDictionary *highVariants = [NSMutableDictionary dictionary];
        for (NSString *key in variants.allKeys) {
            if ([key hasSuffix:@"_high"]) {
                highVariants[key] = variants[key];
            }
        }
        
        if (highVariants.count > 1) {
            // Still need to check gamut
            [self generateGamutSelection:code variants:highVariants indent:[indent stringByAppendingString:@"    "]];
        } else if (highVariants.count == 1) {
            NSString *key = [[highVariants allKeys] firstObject];
            UIColor *color = highVariants[key];
            NSString *comment = [self formatVariantName:key];
            [self appendColorCreationCodeFromColor:code color:color comment:comment indent:[indent stringByAppendingString:@"    "]];
        }
        
        [code appendFormat:@"%@} else {\n", indent];
        
        // Filter standard contrast variants
        NSMutableDictionary *standardVariants = [NSMutableDictionary dictionary];
        for (NSString *key in variants.allKeys) {
            if ([key hasSuffix:@"_standard"]) {
                standardVariants[key] = variants[key];
            }
        }
        
        if (standardVariants.count > 1) {
            // Still need to check gamut
            [self generateGamutSelection:code variants:standardVariants indent:[indent stringByAppendingString:@"    "]];
        } else if (standardVariants.count == 1) {
            NSString *key = [[standardVariants allKeys] firstObject];
            UIColor *color = standardVariants[key];
            NSString *comment = [self formatVariantName:key];
            [self appendColorCreationCodeFromColor:code color:color comment:comment indent:[indent stringByAppendingString:@"    "]];
        }
        
        [code appendFormat:@"%@}\n", indent];
    } else {
        // No contrast difference, check for gamut
        [self generateGamutSelection:code variants:variants indent:indent];
    }
}

- (void)generateGamutSelection:(NSMutableString *)code variants:(NSDictionary *)variants indent:(NSString *)indent {
    if (variants.count == 1) {
        NSString *key = [[variants allKeys] firstObject];
        UIColor *color = [[variants allValues] firstObject];
        NSString *comment = [self formatVariantName:key];
        [self appendColorCreationCodeFromColor:code color:color comment:comment indent:indent];
        return;
    }
    
    // Check for gamut differences
    NSMutableSet *gamuts = [NSMutableSet set];
    for (NSString *key in variants.allKeys) {
        NSArray *components = [key componentsSeparatedByString:@"_"];
        if (components.count >= 3) {
            [gamuts addObject:components[2]];
        }
    }
    
    if (gamuts.count > 1) {
        [code appendFormat:@"%@// Gamut-based selection\n", indent];
        [code appendFormat:@"%@if (gamut == UIDisplayGamutP3) {\n", indent];
        
        // Find P3 variant
        NSString *p3Key = nil;
        UIColor *p3Color = nil;
        for (NSString *key in variants.allKeys) {
            if ([key containsString:@"_p3_"]) {
                p3Key = key;
                p3Color = variants[key];
                break;
            }
        }
        
        if (p3Color) {
            NSString *comment = [self formatVariantName:p3Key];
            [self appendColorCreationCodeFromColor:code color:p3Color comment:comment indent:[indent stringByAppendingString:@"    "]];
        } else {
            NSString *key = [[variants allKeys] firstObject];
            UIColor *fallbackColor = variants[key];
            NSString *comment = [self formatVariantName:key];
            [self appendColorCreationCodeFromColor:code color:fallbackColor comment:comment indent:[indent stringByAppendingString:@"    "]];
        }
        
        [code appendFormat:@"%@} else {\n", indent];
        
        // Find sRGB variant
        NSString *srgbKey = nil;
        UIColor *srgbColor = nil;
        for (NSString *key in variants.allKeys) {
            if ([key containsString:@"_srgb_"]) {
                srgbKey = key;
                srgbColor = variants[key];
                break;
            }
        }
        
        if (srgbColor) {
            NSString *comment = [self formatVariantName:srgbKey];
            [self appendColorCreationCodeFromColor:code color:srgbColor comment:comment indent:[indent stringByAppendingString:@"    "]];
        } else {
            NSString *key = [[variants allKeys] firstObject];
            UIColor *fallbackColor = variants[key];
            NSString *comment = [self formatVariantName:key];
            [self appendColorCreationCodeFromColor:code color:fallbackColor comment:comment indent:[indent stringByAppendingString:@"    "]];
        }
        
        [code appendFormat:@"%@}\n", indent];
    } else {
        // Just one gamut, pick the first available variant
        NSString *key = [[variants allKeys] firstObject];
        UIColor *color = variants[key];
        NSString *comment = [self formatVariantName:key];
        [self appendColorCreationCodeFromColor:code color:color comment:comment indent:indent];
    }
}

- (void)appendColorCreationCodeFromColor:(NSMutableString *)code color:(UIColor *)color comment:(NSString *)comment {
    [self appendColorCreationCodeFromColor:code color:color comment:comment indent:@""];
}

- (void)appendColorCreationCodeFromColor:(NSMutableString *)code color:(UIColor *)color comment:(NSString *)comment indent:(NSString *)indent {
    // Check if this is a P3 color using UIColor's colorSpaceName property
    BOOL isP3 = [self isColorP3:color];
    
    if (isP3) {
        // Get the correct P3 components
        CGFloat red, green, blue, alpha;
        if ([self getP3Components:color red:&red green:&green blue:&blue alpha:&alpha]) {
            // Generate code using colorWithDisplayP3Red
            int red255 = (int)round(red * 255.0);
            int green255 = (int)round(green * 255.0);
            int blue255 = (int)round(blue * 255.0);
            
            if (alpha == 1.0f) {
                [code appendFormat:@"%@return [UIColor colorWithDisplayP3Red:(%d.0f / 255) green:(%d.0f / 255) blue:(%d.0f / 255) alpha:1.0f]; // %@\n", 
                 indent, red255, green255, blue255, comment];
            } else {
                int alpha255 = (int)round(alpha * 255.0);
                [code appendFormat:@"%@return [UIColor colorWithDisplayP3Red:(%d.0f / 255) green:(%d.0f / 255) blue:(%d.0f / 255) alpha:(%d.0f / 255)]; // %@\n", 
                 indent, red255, green255, blue255, alpha255, comment];
            }
            return;
        }
    }
    
    // For non-P3 colors, use the standard approach
    const CGFloat *components = CGColorGetComponents(color.CGColor);
    size_t numComponents = CGColorGetNumberOfComponents(color.CGColor);
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(color.CGColor);
    
    [self appendColorCreationCode:code 
                       components:components 
                    numComponents:numComponents 
                       colorSpace:colorSpace 
                            isP3:NO
                          comment:comment 
                           indent:indent];
}

- (void)appendColorCreationCode:(NSMutableString *)code 
                     components:(const CGFloat *)components 
                  numComponents:(size_t)numComponents 
                     colorSpace:(CGColorSpaceRef)colorSpace 
                           isP3:(BOOL)isP3
                        comment:(NSString *)comment 
                         indent:(NSString *)indent {
    
    // Get colorspace name for better code generation
    CFStringRef colorSpaceName = CGColorSpaceCopyName(colorSpace);
    NSString *spaceName = colorSpaceName ? (__bridge NSString *)colorSpaceName : @"Unknown";
    
    if (numComponents == 4) {
        // Note: P3 colors are already handled in appendColorCreationCodeFromColor
        // This code only runs for sRGB colors
        // RGBA color - most common case
        // Convert to 0-255 range for better readability
        int red255 = (int)round(components[0] * 255.0);
        int green255 = (int)round(components[1] * 255.0);
        int blue255 = (int)round(components[2] * 255.0);
        
        if (components[3] == 1.0f) {
            // Alpha is 1.0, use simpler format
            [code appendFormat:@"%@return [UIColor colorWithRed:(%d.0f / 255) green:(%d.0f / 255) blue:(%d.0f / 255) alpha:1.0f]; // %@\n",
             indent, red255, green255, blue255, comment];
        } else {
            // Alpha is not 1.0, include alpha calculation
            int alpha255 = (int)round(components[3] * 255.0);
            [code appendFormat:@"%@return [UIColor colorWithRed:(%d.0f / 255) green:(%d.0f / 255) blue:(%d.0f / 255) alpha:(%d.0f / 255)]; // %@\n",
             indent, red255, green255, blue255, alpha255, comment];
        }
    } else if (numComponents == 2) {
        // Grayscale with alpha
        int white255 = (int)round(components[0] * 255.0);
        if (components[1] == 1.0f) {
            [code appendFormat:@"%@return [UIColor colorWithWhite:(%d.0f / 255) alpha:1.0f]; // %@ (Grayscale)\n",
             indent, white255, comment];
        } else {
            int alpha255 = (int)round(components[1] * 255.0);
            [code appendFormat:@"%@return [UIColor colorWithWhite:(%d.0f / 255) alpha:(%d.0f / 255)]; // %@ (Grayscale)\n",
             indent, white255, alpha255, comment];
        }
    } else {
        // Generic color creation with colorspace preservation
        [code appendFormat:@"%@// Creating color with preserved colorspace\n", indent];
        [code appendFormat:@"%@CGFloat colorComponents[] = {", indent];
        for (size_t i = 0; i < numComponents; i++) {
            // Convert to 0-255 range for better readability when possible
            if (components[i] >= 0.0 && components[i] <= 1.0) {
                int value255 = (int)round(components[i] * 255.0);
                [code appendFormat:@"(%d.0f / 255)", value255];
            } else {
                // For values outside 0-1 range, use decimal format
                [code appendFormat:@"%.6ff", components[i]];
            }
            if (i < numComponents - 1) [code appendString:@", "];
        }
        [code appendString:@"};\n"];
        
        // Try to use the appropriate colorspace
        if ([spaceName containsString:@"sRGB"] || [spaceName containsString:@"RGB"]) {
            [code appendFormat:@"%@CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);\n", indent];
        } else if ([spaceName containsString:@"Gray"]) {
            [code appendFormat:@"%@CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);\n", indent];
        } else {
            [code appendFormat:@"%@CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB); // Fallback\n", indent];
        }
        
        [code appendFormat:@"%@CGColorRef cgColor = CGColorCreate(colorSpace, colorComponents);\n", indent];
        [code appendFormat:@"%@UIColor *result = [UIColor colorWithCGColor:cgColor];\n", indent];
        [code appendFormat:@"%@CGColorRelease(cgColor);\n", indent];
        [code appendFormat:@"%@CGColorSpaceRelease(colorSpace);\n", indent];
        [code appendFormat:@"%@return result; // %@ (Colorspace: %@)\n", indent, comment, spaceName];
    }
    
    if (colorSpaceName) {
        CFRelease(colorSpaceName);
    }
}

- (NSString *)generateCompatFunctionName:(NSString *)colorName {
    NSString *functionName = colorName;
    
    // Remove "system" prefix if present
    if ([functionName hasPrefix:@"system"]) {
        functionName = [functionName substringFromIndex:6]; // Remove "system"
    }
    
    // Handle special cases
    NSDictionary *specialCases = @{
        @"label": @"compatLabelColor",
        @"secondaryLabel": @"compatSecondaryLabelColor",
        @"tertiaryLabel": @"compatTertiaryLabelColor",
        @"quaternaryLabel": @"compatQuaternaryLabelColor",
        @"systemFill": @"compatSystemFillColor",
        @"secondarySystemFill": @"compatSecondarySystemFillColor",
        @"tertiarySystemFill": @"compatTertiarySystemFillColor",
        @"quaternarySystemFill": @"compatQuaternarySystemFillColor",
        @"placeholderText": @"compatPlaceholderTextColor",
        @"systemBackground": @"compatSystemBackgroundColor",
        @"secondarySystemBackground": @"compatSecondarySystemBackgroundColor",
        @"tertiarySystemBackground": @"compatTertiarySystemBackgroundColor",
        @"systemGroupedBackground": @"compatSystemGroupedBackgroundColor",
        @"secondarySystemGroupedBackground": @"compatSecondarySystemGroupedBackgroundColor",
        @"tertiarySystemGroupedBackground": @"compatTertiarySystemGroupedBackgroundColor",
        @"separator": @"compatSeparatorColor",
        @"opaqueSeparator": @"compatOpaqueSeparatorColor",
        @"link": @"compatLinkColor",
        @"darkText": @"compatDarkTextColor",
        @"lightText": @"compatLightTextColor"
    };
    
    // Check for exact matches first
    if (specialCases[colorName]) {
        return specialCases[colorName];
    }
    
    // For system colors, create compat function name
    if ([colorName hasPrefix:@"system"] || [functionName length] > 0) {
        // Capitalize first letter
        if (functionName.length > 0) {
            functionName = [NSString stringWithFormat:@"%@%@", 
                           [[functionName substringToIndex:1] uppercaseString],
                           [functionName substringFromIndex:1]];
        }
        return [NSString stringWithFormat:@"compat%@Color", functionName];
    }
    
    return [NSString stringWithFormat:@"compat%@Color", [functionName capitalizedString]];
}

#pragma mark - Tap Gesture Handling

- (void)variantColorViewTapped:(UITapGestureRecognizer *)recognizer {
    UIView *tappedView = recognizer.view;
    
    NSLog(@"=== TAP DETECTED ===");
    NSLog(@"Tapped view: %p", tappedView);
    NSLog(@"View class: %@", NSStringFromClass([tappedView class]));
    NSLog(@"Superview: %p", tappedView.superview);
    NSLog(@"User interaction enabled: %d", tappedView.userInteractionEnabled);
    
    NSString *variantKey = objc_getAssociatedObject(tappedView, @"variantKey");
    NSLog(@"Retrieved variant key: %@", variantKey ?: @"(nil)");
    
    // Try to find which index this is in our array
    NSUInteger index = [self.variantColorViews indexOfObject:tappedView];
    NSLog(@"View index in variantColorViews array: %lu", (unsigned long)index);
    
    if (!variantKey) {
        NSLog(@"ERROR: No variant key found!");
        return;
    }
    
    // Format the variant name for searching
    NSString *variantDisplayName = [self formatVariantName:variantKey];
    NSString *variantSearchString = [NSString stringWithFormat:@"=== %@ ===", [variantDisplayName uppercaseString]];
    
    // Search in color details text view
    NSString *detailsText = self.colorDetailsTextView.text;
    NSRange detailsRange = [detailsText rangeOfString:variantSearchString];
    
    NSLog(@"Searching for: '%@'", variantSearchString);
    NSLog(@"Details text length: %lu", (unsigned long)detailsText.length);
    NSLog(@"Details range: %@", NSStringFromRange(detailsRange));
    
    if (detailsRange.location != NSNotFound) {
        // Scroll to this position in the color details
        NSLog(@"Scrolling details to position: %lu", (unsigned long)detailsRange.location);
        [self scrollTextView:self.colorDetailsTextView toRange:detailsRange];
    } else {
        NSLog(@"WARNING: Variant not found in details text!");
    }
    
    // Also search in code generator text view for the actual color creation
    NSString *codeText = self.codeGeneratorTextView.text;
    
    // Search for the return statement with this variant's comment
    // Looking for patterns like: "return [UIColor ... // Dark CarPlay SRGB High"
    NSString *returnComment = [NSString stringWithFormat:@"// %@", variantDisplayName];
    NSRange codeRange = [codeText rangeOfString:returnComment];
    
    if (codeRange.location != NSNotFound) {
        // Find the start of the line with "return" before this comment
        NSRange lineRange = [codeText lineRangeForRange:codeRange];
        NSString *line = [codeText substringWithRange:lineRange];
        
        // Check if this line contains "return"
        if ([line containsString:@"return"]) {
            // Found it - scroll to the return statement
            NSLog(@"Found return statement at line for variant: %@", variantDisplayName);
            [self scrollTextView:self.codeGeneratorTextView toRange:lineRange];
        } else {
            // Search backwards for the nearest "return" statement
            NSRange searchRange = NSMakeRange(0, codeRange.location);
            NSRange returnRange = [codeText rangeOfString:@"return " options:NSBackwardsSearch range:searchRange];
            
            if (returnRange.location != NSNotFound) {
                NSRange returnLineRange = [codeText lineRangeForRange:returnRange];
                NSLog(@"Found return statement above comment for variant: %@", variantDisplayName);
                [self scrollTextView:self.codeGeneratorTextView toRange:returnLineRange];
            } else {
                // Fallback to the comment location
                [self scrollTextView:self.codeGeneratorTextView toRange:codeRange];
            }
        }
    } else {
        NSLog(@"WARNING: Variant not found in code text!");
    }
    
    // Visual feedback - briefly highlight the tapped view
    [self highlightView:tappedView];
}

- (void)scrollTextView:(UITextView *)textView toRange:(NSRange)range {
    // Calculate the position to scroll to - we want the found range at the top
    // First, get the rect for the range
    UITextPosition *startPosition = [textView positionFromPosition:textView.beginningOfDocument offset:range.location];
    UITextPosition *endPosition = [textView positionFromPosition:startPosition offset:range.length];
    
    if (startPosition && endPosition) {
        UITextRange *textRange = [textView textRangeFromPosition:startPosition toPosition:endPosition];
        if (textRange) {
            CGRect rect = [textView firstRectForRange:textRange];
            
            // Scroll so that the found text appears near the top of the text view
            CGPoint scrollPoint = CGPointMake(0, MAX(0, rect.origin.y - 10));
            [textView setContentOffset:scrollPoint animated:YES];
            return;
        }
    }
    
    // Fallback: use the old method if the above doesn't work
    [textView scrollRangeToVisible:range];
}

- (void)highlightView:(UIView *)view {
    // Store original border color
    CGColorRef originalBorderColor = view.layer.borderColor;
    CGFloat originalBorderWidth = view.layer.borderWidth;
    
    // Highlight with a bright border
    view.layer.borderColor = UIColor.systemBlueColor.CGColor;
    view.layer.borderWidth = 3.0;
    
    // Animate back to original after a short delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            view.layer.borderColor = originalBorderColor;
            view.layer.borderWidth = originalBorderWidth;
        }];
    });
}

#pragma mark - Trait Collection Updates

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    // Check if the user interface style changed (light/dark mode)
    if (@available(iOS 13.0, *)) {
        if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
            // Update the border colors for views
            self.colorDisplayScrollView.layer.borderColor = UIColor.separatorColor.CGColor;
            self.codeGeneratorTextView.layer.borderColor = UIColor.separatorColor.CGColor;
            
            // Update border colors for variant views
            for (UIView *variantView in self.variantColorViews) {
                variantView.layer.borderColor = UIColor.tertiaryLabelColor.CGColor;
            }
            
            // Update the color display and details
            [self updateColorDisplay];
        }
    }
}

@end
