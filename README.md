# UIColorPalette

A comprehensive iOS developer tool for inspecting, analyzing, and generating compatibility code for iOS system colors. This app dynamically discovers all available UIColor system colors at runtime and provides detailed information about their variants across different trait collections.

## Screenshot
<div style="width:20%; margin: auto;" align="middle">
<img width="25%" height="25%" alt="image" src="https://github.com/user-attachments/assets/b5ef7b0e-f451-472a-a8e5-351713b306f8" />
<img width="70%" height="70%" alt="image" src="https://github.com/user-attachments/assets/205a5e4f-b3f8-4a1f-b1aa-d517125887e3" />
</div>

## 🤖 AI-Generated Project

**This project was entirely written by AI (Claude).** The code, documentation, build system, and architecture were generated through AI assistance to demonstrate automated iOS development capabilities. While the functionality is complete and fully operational, this serves as an example of AI-generated software development.

## What does this project do?

UIColorPalette is designed to help iOS developers:

- **Inspect System Colors**: Dynamically discover and browse all available `UIColor` system colors (like `systemBlue`, `label`, `systemBackground`, etc.)
- **Analyze Color Variants**: View how colors change across different contexts:
  - Light/Dark appearance
  - Different device idioms (iPhone, iPad, Mac, Apple TV, CarPlay)
  - Color gamuts (sRGB vs Display P3)
  - Accessibility contrast levels (Standard vs High Contrast)
- **Extended Dynamic Range Support**: Properly display and analyze HDR/EDR colors with values outside the standard 0-1 range
- **Generate Compatibility Code**: Automatically generate iOS 12+ compatible color functions that work across all supported iOS versions
- **Color Analysis**: Get detailed RGB, HSB, and colorspace information for each color variant

This tool is particularly useful when creating custom color alternatives or understanding how system colors behave across different environments.

## Features

### 🎨 Dynamic Color Discovery
- Automatically finds all `UIColor` class methods that return colors
- Real-time filtering and search capabilities
- Alphabetically sorted color list for easy browsing

### 🔍 Comprehensive Color Analysis
- **Multiple Trait Collections**: Supports all combinations of:
  - User Interface Style (Light/Dark)
  - Device Idiom (iPhone/iPad/Mac/TV/CarPlay)
  - Display Gamut (sRGB/P3)
  - Accessibility Contrast (Standard/High)
- **Extended Dynamic Range**: Full EDR/HDR support with Metal-backed rendering on real devices
- **Color Space Awareness**: Proper handling of sRGB, Display P3, and extended color spaces

### 📱 Multi-Platform Support
- **iOS**: Native iOS app with UIPickerView interface
- **Mac Catalyst**: Optimized table view interface for macOS
- **iOS Simulator**: Full functionality with EDR simulation

### 🛠 Developer Tools
- **iOS 12+ Compatibility Code Generation**: Automatically generates backward-compatible color functions
- **Detailed Color Information**: RGB, HSB, hex values, and color space details
- **Interactive Color Variants**: Tap on color swatches to jump to relevant code sections
- **Color Comparison**: Side-by-side analysis of color variants

## Minimum Runtime OS Version

- **iOS**: 14.0+
- **Mac Catalyst**: macOS 11.0+
- **iOS Simulator**: 14.0+

## Build Requirements

- Xcode with command line tools
- iOS 14.0+ SDK
- macOS 11.0+ SDK (for Mac Catalyst builds)

## How to Build and Install

This project uses a comprehensive Makefile that supports multiple build targets:

### Quick Start
```bash
# Build all targets (iOS, iOS Simulator, Mac Catalyst)
make all

# Build specific targets
make ios        # Creates IPA for device installation
make iossim     # Creates app for iOS Simulator
make catalyst   # Creates Mac Catalyst app
```

### Build Targets

#### iOS Device Build
```bash
make ios
```
- Builds universal binary (arm64)
- Creates IPA package at `dist/UIColorPalette.ipa`
- Ready for device installation via Xcode or third-party tools

#### iOS Simulator Build
```bash
make iossim
```
- Builds for iOS Simulator (x86_64 + arm64)
- Creates app bundle at `build/iossim/UIColorPalette.app`
- Install by dragging to iOS Simulator

#### Mac Catalyst Build
```bash
make catalyst
```
- Builds universal Mac app (x86_64 + arm64)
- Creates app bundle at `build/catalyst/UIColorPalette.app`
- Automatically code-signed for local execution

### Installation Methods

#### iOS Device
1. Build IPA: `make ios`
2. Install via Xcode: Drag `dist/UIColorPalette.ipa` to Xcode's Devices window
3. Or use iOS App Installer, 3uTools, or similar tools

#### iOS Simulator
1. Build app: `make iossim`
2. Drag `build/iossim/UIColorPalette.app` to iOS Simulator
3. Or use: `xcrun simctl install booted build/iossim/UIColorPalette.app`

#### Mac (Catalyst)
1. Build app: `make catalyst`
2. Double-click `build/catalyst/UIColorPalette.app` to run directly

### Build Options

#### Single Architecture Builds
```bash
# Build for specific architecture only
ARCH=arm64 make ios      # iOS arm64 only
ARCH=x86_64 make iossim  # iOS Simulator x86_64 only
```

#### Clean Build Artifacts
```bash
make clean
```

## Usage

### Basic Usage
1. Launch the app
2. Browse available system colors using the picker (iOS) or table (Mac Catalyst)
3. Use the search bar to filter colors by name
4. View color variants in the horizontal scroll view
5. Tap on variant swatches to jump to detailed information
6. Copy generated compatibility code from the code generator section

### Understanding Color Variants
- **Light/Dark**: Basic appearance mode differences
- **Device Specific**: Colors optimized for different device types
- **P3 vs sRGB**: Wide color gamut vs standard color space
- **High Contrast**: Accessibility-enhanced variants
- **Extended Range**: HDR colors with values beyond 0-1 range

### Generated Code
The app automatically generates iOS 12+ compatible functions like:
```objc
+ (instancetype)compatSystemBlueColor {
    if (@available(iOS 13.0, *)) {
        return UIColor.systemBlueColor;
    }
    
    // Trait collection detection and variant selection
    // ... (comprehensive fallback implementation)
}
```

## Technical Details

### Extended Dynamic Range (EDR)
- Uses Metal layers on real devices for proper EDR display
- Supports 16-bit float color depth (RGBA16Float pixel format)
- Falls back to extended color space layers on Simulator
- Visual indicators distinguish EDR colors from standard colors

### Color Space Handling
- Maintains color space integrity throughout analysis
- Proper conversion between sRGB and Display P3
- Detects and preserves extended color space information
- Out-of-gamut detection and visualization

### Performance Optimizations
- Efficient runtime color discovery using Objective-C runtime
- Intelligent variant filtering to reduce redundancy
- Lazy evaluation of color properties
- Memory-efficient color storage and comparison

## Project Structure

```
UIColorPalette/
├── AppDelegate.h/m          # App lifecycle management
├── ViewController.h/m       # Main UI and color analysis logic
├── main.m                   # App entry point
├── Info.plist              # App configuration
├── AppIcon.png             # App icon
└── UIColorPalette.entitlements # Entitlements for Mac Catalyst
```

## Contributing

This tool is designed for iOS developers working with system colors. Contributions are welcome, particularly for:
- Additional color analysis features
- Enhanced compatibility code generation
- Performance improvements
- Support for new iOS versions and color APIs

## License

This project is intended as a developer tool for inspecting iOS system colors. Please ensure compliance with Apple's guidelines when using system color information in your projects.
