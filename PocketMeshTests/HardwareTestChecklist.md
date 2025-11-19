# PocketMesh Hardware Testing Checklist

**Version**: 1.0
**Last Updated**: 2025-11-18
**Purpose**: Comprehensive validation of PocketMesh functionality with physical MeshCore devices before TestFlight beta release.

## Prerequisites

### Equipment Required:
- [ ] 2-3 MeshCore devices (firmware v1.0+)
- [ ] 2-3 iOS devices (iPhone running iOS 17+)
- [ ] Power cables/batteries for all devices
- [ ] Test environment with varying distances (0-1000m)

### App Setup:
- [ ] Latest PocketMesh build installed via Xcode
- [ ] All devices cleared from previous tests (fresh install)
- [ ] iOS devices have Bluetooth, Location, and Notifications enabled

---

## Test Suite 1: Device Connection & Pairing

### 1.1 Device Discovery
- [ ] **Test**: Launch app → start BLE scan → verify MeshCore device appears in list
- [ ] **Expected**: Device name shows correctly (e.g., "MeshCore-ABCD")
- [ ] **Expected**: RSSI value displays and updates
- [ ] **Pass/Fail**: _______

### 1.2 Device Pairing - Default PIN
- [ ] **Test**: Select device → enter PIN "123456" → connect
- [ ] **Expected**: Connection succeeds within 5 seconds
- [ ] **Expected**: Device info screen shows firmware version
- [ ] **Expected**: Settings shows connected device
- [ ] **Pass/Fail**: _______

### 1.3 Device Pairing - Custom PIN
- [ ] **Setup**: Set custom PIN on MeshCore device
- [ ] **Test**: Connect using custom PIN
- [ ] **Expected**: Connection succeeds
- [ ] **Pass/Fail**: _______

### 1.4 Incorrect PIN Handling
- [ ] **Test**: Enter incorrect PIN
- [ ] **Expected**: Connection fails with error message
- [ ] **Expected**: Can retry with correct PIN
- [ ] **Pass/Fail**: _______

### 1.5 Background Connection Persistence
- [ ] **Test**: Connect device → background app for 1 minute → foreground
- [ ] **Expected**: Device remains connected
- [ ] **Expected**: No reconnection delay
- [ ] **Pass/Fail**: _______

### 1.6 State Restoration After Termination
- [ ] **Test**: Connect device → force quit app → relaunch
- [ ] **Expected**: App automatically reconnects to device
- [ ] **Expected**: Connection completes within 5 seconds
- [ ] **Expected**: Can send messages immediately after restoration
- [ ] **Pass/Fail**: _______

---

## Test Suite 2: Direct Messaging

### 2.1 Send Direct Message - Close Range
- [ ] **Setup**: Two devices within 10m, both paired
- [ ] **Test**: Send "Hello" from Device A to Device B
- [ ] **Expected**: Message shows "queued" → "sending" → "sent" → "acknowledged"
- [ ] **Expected**: Device B receives message within 2 seconds
- [ ] **Expected**: Message appears in chat list on both devices
- [ ] **Pass/Fail**: _______

### 2.2 Receive Direct Message
- [ ] **Test**: Device B sends reply "Hi back"
- [ ] **Expected**: Device A receives message
- [ ] **Expected**: Notification appears on Device A
- [ ] **Expected**: Message shows in conversation view
- [ ] **Pass/Fail**: _______

### 2.3 Long Message (160 bytes)
- [ ] **Test**: Send maximum length message (160 characters)
- [ ] **Expected**: Message sends successfully
- [ ] **Expected**: Full text received on other device
- [ ] **Pass/Fail**: _______

### 2.4 Message Too Long
- [ ] **Test**: Attempt to send 200 character message
- [ ] **Expected**: Error message: "Message exceeds 160 byte limit"
- [ ] **Expected**: Message not sent
- [ ] **Pass/Fail**: _______

### 2.5 Delivery Status Updates
- [ ] **Test**: Send message and observe status changes
- [ ] **Expected**: Status progresses: queued → sending → sent
- [ ] **Expected**: ACK confirmation shows green checkmark
- [ ] **Expected**: Delivery status visible in chat bubble
- [ ] **Pass/Fail**: _______

### 2.6 Failed Message Retry
- [ ] **Setup**: Disconnect receiving device
- [ ] **Test**: Send message from connected device
- [ ] **Expected**: Message shows retry attempts (up to 3)
- [ ] **Expected**: Falls back to flood mode after direct attempts fail
- [ ] **Expected**: Status shows "failed" if flood also fails
- [ ] **Pass/Fail**: _______

### 2.7 Message Deletion
- [ ] **Test**: Long-press queued message → delete
- [ ] **Expected**: Message removed from list
- [ ] **Expected**: Message not sent to network
- [ ] **Pass/Fail**: _______

### 2.8 Offline Message Queuing
- [ ] **Setup**: Disconnect BLE
- [ ] **Test**: Type and "send" message while disconnected
- [ ] **Expected**: Message stays in "queued" state
- [ ] **Test**: Reconnect BLE
- [ ] **Expected**: Queued message sends automatically
- [ ] **Pass/Fail**: _______

---

## Test Suite 3: Contact Discovery & Management

### 3.1 Advertisement - Zero Hop
- [ ] **Setup**: Two devices within range, both paired
- [ ] **Test**: Device A sends zero-hop advertisement
- [ ] **Expected**: Device B receives advertisement
- [ ] **Expected**: Contact appears in Device B's contact list
- [ ] **Expected**: Contact name matches sender's device name
- [ ] **Pass/Fail**: _______

### 3.2 Advertisement - Flood Mode
- [ ] **Setup**: Three devices: A, B (in range of A), C (in range of B, not A)
- [ ] **Test**: Device A sends flood advertisement
- [ ] **Expected**: Device B receives and forwards
- [ ] **Expected**: Device C receives advertisement via B (multi-hop)
- [ ] **Expected**: Contact appears on Device C
- [ ] **Pass/Fail**: _______

### 3.3 Contact List Display
- [ ] **Test**: View contacts list after advertisement
- [ ] **Expected**: All discovered contacts appear
- [ ] **Expected**: "Last seen" timestamp shows relative time
- [ ] **Expected**: Location icon appears if contact shared location
- [ ] **Pass/Fail**: _______

### 3.4 Contact Search
- [ ] **Setup**: 5+ contacts in list
- [ ] **Test**: Type contact name in search bar
- [ ] **Expected**: List filters in real-time
- [ ] **Expected**: Search is case-insensitive
- [ ] **Pass/Fail**: _______

### 3.5 Contact Detail View
- [ ] **Test**: Tap contact → view details
- [ ] **Expected**: Shows contact name, type, public key
- [ ] **Expected**: Shows map if location available
- [ ] **Expected**: "Last Advertisement" timestamp visible
- [ ] **Pass/Fail**: _______

### 3.6 Contact Deletion
- [ ] **Test**: Swipe contact → delete
- [ ] **Expected**: Contact removed from list
- [ ] **Expected**: Associated messages remain (or are deleted - verify expected behavior)
- [ ] **Pass/Fail**: _______

### 3.7 Location Sharing
- [ ] **Setup**: Enable location on Device A
- [ ] **Test**: Send advertisement with location
- [ ] **Expected**: Device B sees contact with location on map
- [ ] **Expected**: Map pin shows correct coordinates
- [ ] **Pass/Fail**: _______

---

## Test Suite 4: Channel Messaging

### 4.1 Create Channel
- [ ] **Test**: Device A creates channel "#testchannel"
- [ ] **Expected**: Channel appears in channels list
- [ ] **Expected**: Can enter channel conversation
- [ ] **Pass/Fail**: _______

### 4.2 Join Same Channel
- [ ] **Test**: Device B creates channel "#testchannel" (same name)
- [ ] **Expected**: Channel appears on Device B
- [ ] **Expected**: Both devices now on same channel
- [ ] **Pass/Fail**: _______

### 4.3 Send Channel Message
- [ ] **Test**: Device A sends "Hello channel" to #testchannel
- [ ] **Expected**: Message broadcasts to all channel members
- [ ] **Expected**: Device B receives message in #testchannel
- [ ] **Expected**: Message shows sender info
- [ ] **Pass/Fail**: _______

### 4.4 Channel Message Delivery
- [ ] **Test**: Device B sends reply in channel
- [ ] **Expected**: Device A receives message
- [ ] **Expected**: Notification shows on Device A
- [ ] **Pass/Fail**: _______

### 4.5 Multiple Channels
- [ ] **Test**: Create channels "#channel1" and "#channel2"
- [ ] **Expected**: Both channels appear in list
- [ ] **Expected**: Messages stay in correct channel
- [ ] **Expected**: Can switch between channels
- [ ] **Pass/Fail**: _______

### 4.6 Case-Sensitive Channel Names
- [ ] **Test**: Create "#TestChannel" and "#testchannel"
- [ ] **Expected**: Treated as different channels (or same - verify expected behavior)
- [ ] **Pass/Fail**: _______

### 4.7 Maximum Channels
- [ ] **Test**: Attempt to create 9th channel (max is 8)
- [ ] **Expected**: Error message or oldest channel replaced
- [ ] **Pass/Fail**: _______

---

## Test Suite 5: Radio Configuration

### 5.1 View Current Configuration
- [ ] **Test**: Navigate to Radio Configuration screen
- [ ] **Expected**: Shows frequency, bandwidth, SF, CR, TX power
- [ ] **Expected**: All values display correctly
- [ ] **Pass/Fail**: _______

### 5.2 Modify Frequency
- [ ] **Test**: Change frequency from 915 MHz to 920 MHz
- [ ] **Expected**: Slider updates value
- [ ] **Expected**: "Save" button enables
- [ ] **Pass/Fail**: _______

### 5.3 Save Configuration
- [ ] **Test**: Modify parameter → tap "Save"
- [ ] **Expected**: Shows saving progress indicator
- [ ] **Expected**: Device responds with OK
- [ ] **Expected**: New value persists after app restart
- [ ] **Pass/Fail**: _______

### 5.4 Bandwidth Selection
- [ ] **Test**: Cycle through 125/250/500 kHz options
- [ ] **Expected**: Segmented control updates
- [ ] **Expected**: Save succeeds for each value
- [ ] **Pass/Fail**: _______

### 5.5 Spreading Factor Adjustment
- [ ] **Test**: Change SF from 7 to 12
- [ ] **Expected**: Higher SF = slower speed, longer range
- [ ] **Expected**: Configuration saves successfully
- [ ] **Pass/Fail**: _______

### 5.6 TX Power Adjustment
- [ ] **Test**: Set TX power to 20 dBm (max)
- [ ] **Expected**: Save succeeds
- [ ] **Expected**: Range improves (test with distance)
- [ ] **Pass/Fail**: _______

### 5.7 Invalid Configuration Handling
- [ ] **Test**: Attempt invalid frequency (outside 902-928 MHz)
- [ ] **Expected**: UI prevents invalid input OR shows error
- [ ] **Pass/Fail**: _______

### 5.8 Configuration Persistence
- [ ] **Test**: Change config → force quit app → relaunch → check device
- [ ] **Expected**: Configuration persists on device
- [ ] **Expected**: UI shows saved values
- [ ] **Pass/Fail**: _______

---

## Test Suite 6: Notifications

### 6.1 Message Notification - Foreground
- [ ] **Setup**: App in foreground
- [ ] **Test**: Receive message from another device
- [ ] **Expected**: Banner notification appears at top
- [ ] **Expected**: Notification sound plays
- [ ] **Expected**: Badge count increments
- [ ] **Pass/Fail**: _______

### 6.2 Message Notification - Background
- [ ] **Setup**: App in background
- [ ] **Test**: Receive message
- [ ] **Expected**: Notification appears on lock screen
- [ ] **Expected**: Shows sender name and message text
- [ ] **Expected**: Notification sound plays
- [ ] **Pass/Fail**: _______

### 6.3 Reply from Notification - Lock Screen
- [ ] **Setup**: Device locked
- [ ] **Test**: Receive notification → swipe → tap "Reply" → type message → send
- [ ] **Expected**: Reply message sends successfully
- [ ] **Expected**: Reply appears in conversation on both devices
- [ ] **Expected**: Notification dismisses after reply
- [ ] **Pass/Fail**: _______

### 6.4 Reply from Notification - App Terminated
- [ ] **Setup**: Force quit app
- [ ] **Test**: Receive notification → reply
- [ ] **Expected**: App launches in background
- [ ] **Expected**: Reply message sends
- [ ] **Expected**: No UI errors or crashes
- [ ] **Pass/Fail**: _______

### 6.5 Notification Tap - Opens Conversation
- [ ] **Test**: Tap notification (not reply)
- [ ] **Expected**: App opens to conversation with sender
- [ ] **Expected**: Conversation scrolls to latest message
- [ ] **Pass/Fail**: _______

### 6.6 Low Battery Warning
- [ ] **Setup**: MeshCore device battery below threshold
- [ ] **Test**: Trigger battery warning (if possible)
- [ ] **Expected**: Notification shows battery voltage
- [ ] **Expected**: Notification appears immediately
- [ ] **Pass/Fail**: _______

### 6.7 Notification Permissions Denied
- [ ] **Setup**: Disable notifications in iOS Settings
- [ ] **Test**: Receive message
- [ ] **Expected**: No notification appears (as expected)
- [ ] **Expected**: Message still appears in app when opened
- [ ] **Pass/Fail**: _______

---

## Test Suite 7: App Lifecycle & State Management

### 7.1 Onboarding - First Launch
- [ ] **Test**: Fresh install → launch app
- [ ] **Expected**: Shows welcome screen
- [ ] **Expected**: Permissions screen requests BLE, Notifications, Location
- [ ] **Expected**: Device scanning works after permissions granted
- [ ] **Pass/Fail**: _______

### 7.2 Onboarding - Skip
- [ ] **Test**: Complete onboarding flow
- [ ] **Test**: Relaunch app
- [ ] **Expected**: Skips onboarding, goes directly to main app
- [ ] **Expected**: Remains connected to device
- [ ] **Pass/Fail**: _______

### 7.3 App Suspension (Home Button)
- [ ] **Test**: Use app → press home button → wait 30s → resume
- [ ] **Expected**: BLE connection maintained
- [ ] **Expected**: Can send messages immediately
- [ ] **Expected**: Receives queued messages
- [ ] **Pass/Fail**: _______

### 7.4 App Termination & Relaunch
- [ ] **Test**: Force quit app → relaunch
- [ ] **Expected**: BLE state restored automatically
- [ ] **Expected**: Reconnects to last device
- [ ] **Expected**: Message history loads correctly
- [ ] **Pass/Fail**: _______

### 7.5 Low Memory Conditions
- [ ] **Test**: Use app with many messages (1000+) and contacts (50+)
- [ ] **Expected**: No crashes or memory warnings
- [ ] **Expected**: UI remains responsive
- [ ] **Expected**: Scrolling is smooth
- [ ] **Pass/Fail**: _______

### 7.6 Airplane Mode Toggle
- [ ] **Test**: Enable airplane mode while connected
- [ ] **Expected**: BLE disconnects gracefully
- [ ] **Test**: Disable airplane mode
- [ ] **Expected**: App reconnects automatically
- [ ] **Pass/Fail**: _______

### 7.7 Bluetooth Toggle
- [ ] **Test**: Disable Bluetooth in Control Center
- [ ] **Expected**: App shows "unauthorized" or "disconnected" state
- [ ] **Test**: Re-enable Bluetooth
- [ ] **Expected**: Can reconnect to device
- [ ] **Pass/Fail**: _______

---

## Test Suite 8: Edge Cases & Error Handling

### 8.1 Concurrent Message Sending
- [ ] **Test**: Send 5 messages rapidly in succession
- [ ] **Expected**: All messages queue and send in order
- [ ] **Expected**: No messages lost
- [ ] **Expected**: Delivery status correct for each
- [ ] **Pass/Fail**: _______

### 8.2 Device Disconnection During Send
- [ ] **Test**: Start sending message → disconnect device mid-send
- [ ] **Expected**: Message shows "failed" status
- [ ] **Expected**: Can retry when reconnected
- [ ] **Pass/Fail**: _______

### 8.3 Device Out of Range
- [ ] **Test**: Move device beyond BLE range (~100m)
- [ ] **Expected**: App shows disconnected
- [ ] **Expected**: Messages queue locally
- [ ] **Test**: Return to range
- [ ] **Expected**: Reconnects automatically
- [ ] **Expected**: Queued messages send
- [ ] **Pass/Fail**: _______

### 8.4 Empty Message Handling
- [ ] **Test**: Attempt to send empty message (just spaces)
- [ ] **Expected**: Send button disabled OR error message
- [ ] **Expected**: No empty message sent
- [ ] **Pass/Fail**: _______

### 8.5 Special Characters in Messages
- [ ] **Test**: Send message with emoji: "Hello 👋 World 🌍"
- [ ] **Expected**: Message sends correctly
- [ ] **Expected**: Emoji display correctly on receiver
- [ ] **Pass/Fail**: _______

### 8.6 Multiple Devices Connection Attempt
- [ ] **Test**: Attempt to connect to second device while first connected
- [ ] **Expected**: Disconnects from first OR shows error
- [ ] **Expected**: No simultaneous connections
- [ ] **Pass/Fail**: _______

### 8.7 Rapid Connect/Disconnect
- [ ] **Test**: Connect → disconnect → connect → disconnect (5 times rapidly)
- [ ] **Expected**: No crashes or hangs
- [ ] **Expected**: App state remains consistent
- [ ] **Expected**: Final connection works correctly
- [ ] **Pass/Fail**: _______

### 8.8 Settings Changes During Active Connection
- [ ] **Test**: Change radio config while messages are being sent
- [ ] **Expected**: Settings change succeeds
- [ ] **Expected**: Ongoing messages complete or fail gracefully
- [ ] **Expected**: New messages use new settings
- [ ] **Pass/Fail**: _______

---

## Test Suite 9: Performance & Battery

### 9.1 Message List Scrolling
- [ ] **Setup**: Generate 500+ messages in conversation
- [ ] **Test**: Scroll through message list
- [ ] **Expected**: Smooth 60fps scrolling
- [ ] **Expected**: No lag or frame drops
- [ ] **Pass/Fail**: _______

### 9.2 Contact List Performance
- [ ] **Setup**: 100+ contacts in list
- [ ] **Test**: Scroll and search contacts
- [ ] **Expected**: Instantaneous search filtering
- [ ] **Expected**: Smooth scrolling
- [ ] **Pass/Fail**: _______

### 9.3 BLE Connection Time
- [ ] **Test**: Measure time from "Connect" tap to "Connected" state
- [ ] **Expected**: < 5 seconds average
- [ ] **Expected**: Consistent across multiple attempts
- [ ] **Pass/Fail**: _______

### 9.4 Message Send Latency
- [ ] **Test**: Measure time from send button tap to "sent" status
- [ ] **Expected**: < 2 seconds in good conditions
- [ ] **Pass/Fail**: _______

### 9.5 Battery Drain - Active Use
- [ ] **Setup**: Full battery charge
- [ ] **Test**: Use app actively for 1 hour (send messages, browse contacts)
- [ ] **Expected**: < 10% battery drain on iPhone
- [ ] **Expected**: No abnormal heat generation
- [ ] **Pass/Fail**: _______

### 9.6 Battery Drain - Background
- [ ] **Setup**: Full battery charge
- [ ] **Test**: App in background for 8 hours (overnight)
- [ ] **Expected**: < 5% battery drain with BLE connection maintained
- [ ] **Pass/Fail**: _______

### 9.7 Memory Usage
- [ ] **Test**: Monitor memory usage in Xcode Instruments
- [ ] **Expected**: < 100MB typical usage
- [ ] **Expected**: No memory leaks during 30 min session
- [ ] **Pass/Fail**: _______

---

## Test Suite 10: UI/UX Verification

### 10.1 Dark Mode Support
- [ ] **Test**: Switch to Dark Mode in iOS settings
- [ ] **Expected**: App UI adapts correctly
- [ ] **Expected**: All text remains readable
- [ ] **Expected**: No white flash on screen transitions
- [ ] **Pass/Fail**: _______

### 10.2 Landscape Orientation (iPhone)
- [ ] **Test**: Rotate device to landscape
- [ ] **Expected**: UI adapts appropriately
- [ ] **Expected**: No layout issues or cropped content
- [ ] **Pass/Fail**: _______

### 10.3 Dynamic Type (Accessibility)
- [ ] **Test**: Increase text size to largest accessibility setting
- [ ] **Expected**: All text scales appropriately
- [ ] **Expected**: No truncated labels
- [ ] **Expected**: Layout remains usable
- [ ] **Pass/Fail**: _______

### 10.4 VoiceOver Support
- [ ] **Test**: Enable VoiceOver → navigate app
- [ ] **Expected**: All interactive elements have labels
- [ ] **Expected**: Navigation is logical
- [ ] **Expected**: Can send message using VoiceOver
- [ ] **Pass/Fail**: _______

### 10.5 Keyboard Handling
- [ ] **Test**: Open message compose → keyboard appears
- [ ] **Expected**: Message input visible above keyboard
- [ ] **Expected**: Keyboard dismisses when tapping outside
- [ ] **Expected**: Return key sends message (or verify expected behavior)
- [ ] **Pass/Fail**: _______

### 10.6 Pull to Refresh (if implemented)
- [ ] **Test**: Pull down on message list
- [ ] **Expected**: Refresh indicator appears
- [ ] **Expected**: Messages reload/update
- [ ] **Pass/Fail**: _______

### 10.7 Empty States
- [ ] **Test**: New install → view Chats tab with no conversations
- [ ] **Expected**: Shows helpful empty state message
- [ ] **Expected**: Provides guidance on next steps
- [ ] **Pass/Fail**: _______

---

## Post-Testing Summary

### Overall Results:
- **Total Tests**: ______
- **Passed**: ______
- **Failed**: ______
- **Pass Rate**: ______%

### Critical Issues Found:
1. ___________________________________
2. ___________________________________
3. ___________________________________

### Non-Critical Issues Found:
1. ___________________________________
2. ___________________________________
3. ___________________________________

### Recommendations:
- [ ] Ready for TestFlight beta: YES / NO
- [ ] Additional testing needed in areas: ___________________________________
- [ ] Blockers that must be fixed: ___________________________________

### Tested By:
- **Name**: ___________________________________
- **Date**: ___________________________________
- **Test Environment**: ___________________________________
- **Devices Used**: ___________________________________

### Notes:
___________________________________
___________________________________
___________________________________