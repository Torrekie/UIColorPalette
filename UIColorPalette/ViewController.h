//
//  ViewController.h
//  UIColorPalette
//
//  Created by Torrekie on 2025/11/4.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <UIPickerViewDataSource, UIPickerViewDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIPickerView *colorPicker;
@property (nonatomic, strong) UITableView *colorTableView; // Mac Catalyst alternative
@property (nonatomic, assign) BOOL isMacCatalyst;
@property (nonatomic, strong) UIScrollView *colorDisplayScrollView;
@property (nonatomic, strong) UIView *colorDisplayContainerView;
@property (nonatomic, strong) NSLayoutConstraint *containerWidthConstraint;
@property (nonatomic, strong) NSMutableArray<UIView *> *variantColorViews;
@property (nonatomic, strong) NSMutableArray<UILabel *> *variantLabels;
@property (nonatomic, strong) UITextView *colorDetailsTextView;
@property (nonatomic, strong) UITextView *codeGeneratorTextView;
@property (nonatomic, strong) NSArray *systemColors;
@property (nonatomic, strong) NSArray *filteredSystemColors;

@end

