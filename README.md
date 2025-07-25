# fyp

A new Flutter project.

## Features

### 🎯 Comprehensive Gesture Recognition System

The app now includes advanced gesture recognition features specifically designed for blind users across all main pages:

#### **Home Page Gestures:**
1. **Swipe Left/Right**: Navigate between main pages (Image Processing, Crowdsourcing, Navigation)
2. **Downward Line**: Open user profile
3. **Swipe Up**: Confirm page selection and navigate to the current page

#### **Image Processing Page Gestures:**
1. **Swipe Up**: Enter Live Detection
2. **Swipe Down**: Open OCR Text Recognition  
3. **Swipe Left**: Return to main page

#### **Crowdsourcing Page Gestures:**
1. **Swipe Up**: Enter Chatbot
2. **Swipe Down**: Open Voice Note function
3. **Swipe Left**: Return to main page

#### **Navigation Page Gestures:**
1. **Swipe Up**: Enter Live Location Tracking
2. **Swipe Down**: Enter Transportation
3. **Swipe Left**: Return to main page

### 🎵 Smart Audio Announcement System

#### **Page-Specific Announcements:**
- **Home Page**: Announces current page every 5 seconds (only when on home page)
- **Image Processing Page**: Announces available features every 8 seconds
- **Crowdsourcing Page**: Announces available features every 8 seconds  
- **Navigation Page**: Announces available features every 8 seconds
- **No Overlap**: Announcements automatically pause when navigating to sub-pages

#### **Audio Feedback Features:**
- **Welcome Messages**: Each page announces available gestures upon entry
- **Gesture Confirmation**: Audio feedback for each detected gesture
- **Navigation Feedback**: Confirmation when reaching page limits
- **Context-Aware**: Announcements stop when leaving pages to avoid conflicts

### 🔧 Technical Implementation

#### **Gesture Detection Parameters:**
- **Horizontal Swipe Detection**: Minimum 100px horizontal movement with <50px vertical deviation
- **Downward Line Detection**: Minimum 80px downward movement with <30px horizontal deviation  
- **Upward Swipe Detection**: Minimum 100px upward movement with <50px horizontal deviation

#### **Smart Announcement Management:**
- **Individual Timers**: Each page has its own announcement timer
- **Lifecycle Management**: Proper cleanup when leaving pages
- **No Conflicts**: Announcements pause during navigation transitions
- **Memory Efficient**: Automatic disposal of resources

### 📱 User Experience Features

#### **Visual Indicators:**
- **Gesture Toggle Button**: Enable/disable gestures on each page
- **Gesture Instruction Panels**: Visual guide showing available gestures
- **Subtitle Hints**: Each feature button shows the associated gesture

#### **Haptic Feedback:**
- **Swipe Gestures**: 100ms vibration
- **Upward Swipe**: Pattern vibration (50ms x 5)
- **Downward Line**: Double vibration pattern (100-50-100ms)

## Usage

### **Getting Started:**
1. **Enable Gestures**: Tap the gesture icon in the top-right corner of any page
2. **Listen for Instructions**: Each page will announce available gestures when loaded
3. **Navigate Efficiently**: Use gestures for hands-free navigation

### **Navigation Flow:**
1. **Home Page**: Swipe left/right to browse features, swipe up to enter selected page
2. **Feature Pages**: Swipe up/down to access specific functions, swipe left to return
3. **Profile Access**: Draw downward line from any main page to access user profile

### **Audio Guidance:**
- **Home Page**: Continuous page announcements every 5 seconds
- **Feature Pages**: Feature descriptions every 8 seconds
- **Gesture Help**: Available gestures announced on page entry

## Accessibility Design Principles

This gesture system is specifically designed for blind users by providing:

### **Non-visual Navigation**: 
- No need to locate specific buttons or UI elements
- Gesture-based interaction works from anywhere on screen

### **Consistent Feedback**: 
- Audio confirmation for every action
- Haptic vibration patterns for tactile feedback

### **Simple Gesture Patterns**: 
- Easy-to-remember directional movements
- Logical gesture-to-function mapping

### **Context-Aware Announcements**: 
- Smart announcement system prevents audio overlap
- Page-specific content helps maintain orientation

### **Reliable Recognition**:
- Configurable sensitivity parameters
- Robust gesture detection algorithms
- Fallback to traditional button navigation

## Technical Architecture

### **Gesture Recognition Service:**
- Singleton pattern for consistent state management
- Real-time gesture analysis with configurable parameters
- Callback-based architecture for responsive UI updates

### **Announcement Management:**
- Independent timer systems for each page
- Proper lifecycle management to prevent memory leaks
- Smart pausing/resuming during page transitions

### **Integration Pattern:**
- Consistent implementation across all pages
- Shared gesture service with page-specific configurations
- Unified error handling and fallback mechanisms

This comprehensive gesture recognition system transforms the app into a truly accessible platform where blind users can navigate efficiently and confidently through all features using simple, intuitive gestures.
