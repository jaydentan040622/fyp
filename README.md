# Flutter Accessibility App

A Flutter app designed with accessibility features for blind and visually impaired users.

## Features

### 🎯 Gesture Recognition for Accessibility

The app now includes advanced gesture recognition features specifically designed for blind users:

#### Available Gestures:
1. **Swipe Left/Right**: Navigate between pages
   - Swipe left to go to the previous page
   - Swipe right to go to the next page

2. **Downward Line**: Open user profile
   - Draw a straight line downward on the screen to open the user profile

3. **Swipe Up**: Confirm page selection
   - Swipe upward on the screen to confirm and navigate to the current page

#### Audio Feedback:
- **Home Page Announcements**: Every 5 seconds while on the home page, the app announces the current page
- **Gesture Confirmation**: Each gesture triggers audio feedback and haptic vibration
- **Navigation Feedback**: Audio confirmation when reaching first/last page

#### Controls:
- **Gesture Toggle**: Use the gesture icon in the top-right to enable/disable gestures
- **Visual Instructions**: When gestures are enabled, instruction text appears at the bottom

### 🔧 Technical Implementation

#### Gesture Recognition Service (`GestureRecognitionService`)
- **Custom Gesture Detection**: Analyzes touch patterns to detect specific gestures
- **Configurable Parameters**: Adjustable sensitivity for different gesture types
- **Haptic Feedback**: Different vibration patterns for each gesture type
- **Text-to-Speech Integration**: Built-in TTS for audio announcements

#### Gesture Detection Parameters:
- **Horizontal Swipe Detection**: Minimum 100px horizontal movement with <50px vertical deviation
- **Downward Line Detection**: Minimum 80px downward movement with <30px horizontal deviation  
- **Upward Swipe Detection**: Minimum 100px upward movement with <50px horizontal deviation

### 🎵 Audio Features:
- **Page Announcements**: "Current page: [Page Name]" (every 5 seconds on home page only)
- **Gesture Feedback**: "Swipe left detected", "Swipe up detected", etc.
- **Navigation Limits**: "Already at the first page", "Already at the last page"
- **Selection Confirmation**: "Confirming selection for [Page Name]"

### 🔄 Integration with Existing Features:
- **TTS Service**: Leverages existing `flutter_tts` package
- **Vibration Support**: Uses existing `vibration` package
- **Accessibility Service**: Integrates with existing navigation accessibility features

## Usage

1. **Enable Gestures**: Tap the gesture icon in the top-right corner
2. **Navigate**: Use swipe gestures to move between pages
3. **Access Profile**: Draw a downward line to open your profile
4. **Confirm Selection**: Swipe upward to go to the current page
5. **Listen**: The app will announce the current page every 5 seconds while on the home page

## Accessibility Benefits

This gesture system is specifically designed for blind users by providing:
- **Non-visual Navigation**: No need to locate specific buttons
- **Consistent Feedback**: Audio and haptic confirmation for every action
- **Simple Gestures**: Easy-to-remember movement patterns
- **Context-Aware Announcements**: Page announcements only on home page to avoid interruptions

## Technical Requirements

- Flutter SDK 3.7.0+
- Permissions for microphone and vibration
- Text-to-Speech support
- Touch screen capability

## Dependencies

The gesture recognition feature uses these existing packages:
- `flutter_tts`: For text-to-speech announcements
- `vibration`: For haptic feedback
- `dart:math`: For gesture calculation algorithms

---

*This accessibility feature makes the app more inclusive and user-friendly for individuals with visual impairments.*
