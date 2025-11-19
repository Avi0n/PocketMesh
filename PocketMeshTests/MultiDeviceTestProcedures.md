# Multi-Device Testing Procedures

**Purpose**: Detailed step-by-step procedures for testing PocketMesh with multiple physical devices to validate mesh networking, message routing, and contact discovery.

## Overview

Multi-device testing validates:
- **Bidirectional messaging**: Two-way communication works correctly
- **Multi-hop routing**: Messages relay through intermediate devices
- **Contact discovery**: Advertisement propagation across mesh network
- **Network resilience**: Graceful handling of node failures
- **Concurrent operations**: Multiple devices operating simultaneously

---

## Test Procedure 1: Bidirectional Messaging (2 Devices)

### Objective
Verify messages can be sent and received in both directions between two devices.

### Equipment
- 2 MeshCore devices (Device A, Device B)
- 2 iPhones with PocketMesh installed (Phone A, Phone B)

### Setup Steps
1. Pair Phone A with Device A
2. Pair Phone B with Device B
3. Place devices within direct radio range (< 50m)
4. Complete onboarding on both phones

### Test Steps

#### Step 1: Initial Connection Verification
```
Phone A → Settings → Verify Device A shows as "Connected"
Phone B → Settings → Verify Device B shows as "Connected"
```
**Expected**: Both show green connected status

#### Step 2: Send Advertisement (A → B)
```
Phone A → Contacts Tab → Tap antenna icon → Select "Nearby (Zero Hop)"
Wait 5 seconds
Phone B → Check Contacts Tab
```
**Expected**: Phone B shows contact for Phone A's device
**Expected**: "Last seen: just now" timestamp

#### Step 3: Send Advertisement (B → A)
```
Phone B → Contacts Tab → Tap antenna icon → Select "Nearby (Zero Hop)"
Wait 5 seconds
Phone A → Check Contacts Tab
```
**Expected**: Phone A shows contact for Phone B's device

#### Step 4: Send Message (A → B)
```
Phone A → Contacts Tab → Tap contact for Device B → Type "Test message from A" → Send
Watch delivery status change: queued → sending → sent → acknowledged
```
**Expected**: Status reaches "acknowledged" within 5 seconds
**Expected**: Green checkmark appears

#### Step 5: Verify Receipt (B)
```
Phone B → Check Chats Tab
```
**Expected**: New conversation appears with Device A
**Expected**: Message "Test message from A" visible
**Expected**: Notification appeared on Phone B
**Expected**: Correct timestamp

#### Step 6: Send Reply (B → A)
```
Phone B → Open conversation → Type "Reply from B" → Send
Watch delivery status
```
**Expected**: Status reaches "acknowledged" within 5 seconds

#### Step 7: Verify Reply Receipt (A)
```
Phone A → Open conversation
```
**Expected**: Reply message appears
**Expected**: Conversation shows both messages in correct order

#### Step 8: Rapid Bidirectional Exchange
```
Phone A: Send "Message 1"
Phone B: Send "Message 2"
Phone A: Send "Message 3"
Phone B: Send "Message 4"
(Send messages as quickly as possible)
```
**Expected**: All messages delivered in order
**Expected**: No messages lost
**Expected**: Delivery status correct for each

### Pass Criteria
- ✅ Advertisements received in both directions
- ✅ Messages delivered A→B and B→A successfully
- ✅ Delivery status updates correctly
- ✅ Notifications appear on both devices
- ✅ Rapid bidirectional messaging works without losses

---

## Test Procedure 2: Multi-Hop Messaging (3 Devices)

### Objective
Verify messages route through intermediate devices when direct connection unavailable.

### Equipment
- 3 MeshCore devices (Device A, Device B, Device C)
- 3 iPhones with PocketMesh installed (Phone A, Phone B, Phone C)

### Topology
```
Device A <--50m--> Device B <--50m--> Device C
(A and C are >100m apart, out of direct range)
```

### Setup Steps
1. Pair Phone A with Device A
2. Pair Phone B with Device B
3. Pair Phone C with Device C
4. Position devices:
   - Device A and B within 50m
   - Device B and C within 50m
   - Device A and C >100m apart (beyond direct radio range)

### Test Steps

#### Step 1: Verify Topology
```
Phone A → Contacts → Send "Nearby (Zero Hop)" advertisement
Wait 10 seconds
Phone B → Check Contacts Tab
```
**Expected**: Phone B sees Device A
**Expected**: Phone C does NOT see Device A (out of range)

```
Phone C → Contacts → Send "Nearby (Zero Hop)" advertisement
Wait 10 seconds
Phone B → Check Contacts Tab
```
**Expected**: Phone B sees Device C
**Expected**: Phone A does NOT see Device C (out of range)

#### Step 2: Flood Advertisement (A → C via B)
```
Phone A → Contacts → Send "Network-wide (Flood)" advertisement
Wait 15 seconds
Phone C → Check Contacts Tab
```
**Expected**: Phone C receives advertisement via Device B (multi-hop)
**Expected**: Contact for Device A appears on Phone C
**Expected**: Path length indicator shows 1 or 2 hops

#### Step 3: Flood Advertisement (C → A via B)
```
Phone C → Contacts → Send "Network-wide (Flood)" advertisement
Wait 15 seconds
Phone A → Check Contacts Tab
```
**Expected**: Phone A receives advertisement via Device B
**Expected**: Contact for Device C appears on Phone A

#### Step 4: Send Message A → C (Multi-Hop)
```
Phone A → Contacts → Tap Device C contact → Type "Multi-hop test from A" → Send
```
**Expected**: Message routes through Device B
**Expected**: Delivery status reaches "sent" (may not ACK due to multi-hop)
**Expected**: Message arrives at Phone C within 10 seconds

#### Step 5: Verify Receipt on C
```
Phone C → Check Chats Tab → Open conversation with Device A
```
**Expected**: Message "Multi-hop test from A" received
**Expected**: Path length shows 1-2 hops
**Expected**: Notification appeared

#### Step 6: Send Reply C → A (Multi-Hop)
```
Phone C → Type "Reply from C via multi-hop" → Send
Wait 10 seconds
Phone A → Check conversation
```
**Expected**: Reply routes back through Device B
**Expected**: Message appears on Phone A

#### Step 7: Intermediate Node Visibility
```
Phone B → Chats Tab
```
**Expected**: Phone B may see relayed messages (check if protocol design shows relayed messages)
**Verify**: Messages are not duplicated

#### Step 8: Break the Relay (Remove Device B)
```
Power off Device B or move it out of range
Phone A → Send message "Testing with B down"
Wait 30 seconds
```
**Expected**: Message times out or shows "failed"
**Expected**: No delivery to Phone C

#### Step 9: Restore the Relay
```
Power on Device B or move back in range
Wait for reconnection
Phone A → Retry sending message
```
**Expected**: Message delivery resumes
**Expected**: Phone C receives message

### Pass Criteria
- ✅ Flood advertisements propagate through intermediate device
- ✅ Multi-hop messages route correctly (A→B→C and C→B→A)
- ✅ Path length indicators show hop count
- ✅ Messages fail gracefully when relay is unavailable
- ✅ Network recovers when relay returns

---

## Test Procedure 3: Contact Discovery Validation (4+ Devices)

### Objective
Verify contact discovery works correctly with multiple devices advertising simultaneously.

### Equipment
- 4+ MeshCore devices
- 4+ iPhones with PocketMesh installed

### Topology
```
    Device B
   /         \
Device A --- Device C
   \         /
    Device D
```
(All devices within range of each other - star topology)

### Setup Steps
1. Pair each phone with corresponding device
2. Place all devices within 50m of each other (direct range)
3. Complete onboarding on all phones

### Test Steps

#### Step 1: Sequential Advertisement
```
Phone A → Send advertisement
Wait 5 seconds
Phone B → Send advertisement
Wait 5 seconds
Phone C → Send advertisement
Wait 5 seconds
Phone D → Send advertisement
Wait 5 seconds
```

#### Step 2: Verify All Contacts Discovered
```
For each phone (A, B, C, D):
  → Contacts Tab → Count contacts
```
**Expected**: Each phone shows 3 contacts (all others)
**Expected**: All contact names correct
**Expected**: "Last seen" timestamps reasonable

#### Step 3: Simultaneous Advertisement
```
All phones simultaneously: Send "Nearby (Zero Hop)" advertisement
Wait 10 seconds
```
**Expected**: No conflicts or errors
**Expected**: All advertisements received by all devices

#### Step 4: Contact Metadata Validation
```
For each contact on each phone:
  → Tap contact → View details
```
**Expected**: Public key displayed correctly
**Expected**: Last advertisement timestamp reasonable
**Expected**: Contact type shows correctly (CHAT, REPEATER, etc.)

#### Step 5: Location Sharing Discovery
```
Phone A → Enable location → Send advertisement
Wait 5 seconds
Phones B, C, D → Tap Phone A contact → View details
```
**Expected**: Map shows Phone A's location
**Expected**: Location coordinates are reasonable
**Expected**: Location icon appears in contact list

#### Step 6: Repeated Advertisement Updates
```
Phone A → Send advertisement
Wait 60 seconds
Phone A → Send advertisement again
Other phones → Check Phone A contact
```
**Expected**: "Last seen" timestamp updates
**Expected**: No duplicate contacts created
**Expected**: Previous metadata preserved

#### Step 7: Contact Re-Discovery After Deletion
```
Phone B → Delete contact for Phone A
Phone A → Send advertisement
Phone B → Check contacts
```
**Expected**: Contact for Phone A reappears
**Expected**: Contact metadata restored

#### Step 8: Network-Wide Discovery (Flood)
```
Phone A → Send "Network-wide (Flood)" advertisement
Wait for advertisements to propagate through mesh
All phones → Check contacts
```
**Expected**: Advertisement reaches all devices (direct and multi-hop)
**Expected**: Proper hop count for multi-hop discoveries

### Pass Criteria
- ✅ All devices discover each other via advertisements
- ✅ No duplicate contacts created
- ✅ Timestamps update correctly
- ✅ Location sharing works when enabled
- ✅ Re-discovery works after deletion
- ✅ Flood mode reaches all network nodes

---

## Test Procedure 4: Channel Communication (3 Devices)

### Objective
Verify channel messaging works correctly with multiple participants.

### Equipment
- 3 MeshCore devices (Device A, Device B, Device C)
- 3 iPhones with PocketMesh installed

### Setup Steps
1. Pair each phone with corresponding device
2. Ensure all devices within direct range
3. Complete contact discovery (all devices know each other)

### Test Steps

#### Step 1: Create Channel on Device A
```
Phone A → Chats Tab → Create channel "#testchannel"
```
**Expected**: Channel appears in channel list
**Expected**: Can enter channel

#### Step 2: Join Channel on Device B
```
Phone B → Chats Tab → Create channel "#testchannel" (same name)
```
**Expected**: Channel appears on Phone B
**Expected**: Both devices now on same channel

#### Step 3: Join Channel on Device C
```
Phone C → Chats Tab → Create channel "#testchannel"
```
**Expected**: Channel appears on Phone C
**Expected**: All three devices on same channel

#### Step 4: Broadcast from Device A
```
Phone A → Enter #testchannel → Type "Hello from A" → Send
Wait 5 seconds
Phones B and C → Check #testchannel
```
**Expected**: Message appears on Phone B
**Expected**: Message appears on Phone C
**Expected**: Sender identified as Device A

#### Step 5: Multi-Participant Conversation
```
Phone A: "Message 1 from A"
Phone B: "Message 2 from B"
Phone C: "Message 3 from C"
Phone A: "Message 4 from A"
```
**Expected**: All messages appear on all devices
**Expected**: Messages in correct order
**Expected**: Sender attribution correct

#### Step 6: Multiple Channel Isolation
```
Create second channel "#channel2" on all devices
Phone A → Send "Channel 2 message" to #channel2
Phones B and C → Check both channels
```
**Expected**: Message only in #channel2
**Expected**: #testchannel unchanged
**Expected**: Messages stay in correct channel

#### Step 7: Leave and Rejoin Channel
```
Phone B → Delete #testchannel
Phone A → Send message to #testchannel
```
**Expected**: Phone B doesn't receive message (no longer in channel)

```
Phone B → Recreate #testchannel
Phone A → Send message
```
**Expected**: Phone B now receives messages again

### Pass Criteria
- ✅ Multiple devices can join same channel
- ✅ Channel broadcasts reach all participants
- ✅ Messages stay in correct channel (isolation)
- ✅ Sender attribution works correctly
- ✅ Leave/rejoin functions properly

---

## Test Procedure 5: Network Stress Test (5+ Devices)

### Objective
Verify network performs well under high load with many simultaneous operations.

### Equipment
- 5+ MeshCore devices
- 5+ iPhones with PocketMesh installed

### Setup Steps
1. Pair all phones with devices
2. Position in mesh topology (mix of direct and multi-hop connections)
3. Complete contact discovery on all devices

### Test Steps

#### Step 1: Simultaneous Message Storm
```
All devices simultaneously:
  → Send direct message to another random device
  → Send channel message to #general
  → Send advertisement
```
**Expected**: No crashes or hangs
**Expected**: All messages eventually delivered
**Expected**: Delivery status updates correctly

#### Step 2: Rapid Sequential Messaging
```
For i = 1 to 100:
  Each device sends "Message {i}" to next device in sequence
```
**Expected**: All 100 messages per device delivered
**Expected**: Messages in correct order
**Expected**: No significant delays

#### Step 3: Concurrent Operations
```
Device A: Send 10 messages
Device B: Change radio configuration
Device C: Send advertisement
Device D: Delete and recreate contact
Device E: Join/leave channel repeatedly
```
**Expected**: All operations complete successfully
**Expected**: No race conditions or conflicts

#### Step 4: Network Partition and Recovery
```
Split devices into two groups (Group 1: A,B  Group 2: C,D,E)
Move groups out of range (>200m apart)
Each group: Send messages internally
Wait 5 minutes
Move groups back into range
```
**Expected**: Intra-group messages work during partition
**Expected**: No messages delivered across partition
**Expected**: Network recovers when groups reunited
**Expected**: Queued inter-group messages deliver after recovery

#### Step 5: Device Churn (Rapid Join/Leave)
```
For 10 iterations:
  - Randomly power off 1-2 devices
  - Wait 30 seconds
  - Power devices back on
  - Send messages from random devices
```
**Expected**: Network remains stable
**Expected**: Messages delivered despite churn
**Expected**: Contact lists eventually consistent

### Pass Criteria
- ✅ Network handles message storm without crashes
- ✅ Rapid sequential messaging succeeds
- ✅ Concurrent operations don't interfere
- ✅ Network recovers from partitions
- ✅ Handles device churn gracefully

---

## Debugging Tips

### Common Issues and Resolutions

**Issue**: Device won't connect
**Check**: Bluetooth enabled, device powered on, correct PIN
**Try**: Forget device and re-pair

**Issue**: Messages not delivering
**Check**: Both devices connected, in range, radio config compatible
**Try**: Send advertisement first to establish contact

**Issue**: Multi-hop not working
**Check**: Flood mode enabled, intermediate device connected and forwarding
**Try**: Verify topology with zero-hop advertisements first

**Issue**: Notifications not appearing
**Check**: Notification permissions granted, app not in DND/Focus mode
**Try**: Re-request permissions, check iOS Settings

**Issue**: State restoration not working
**Check**: Background mode enabled in Info.plist, BLE was connected when backgrounded
**Try**: Check Xcode console for "BLE state restoration triggered" log

### Logging

Enable verbose logging to debug issues:
```
Settings → Developer → Enable Debug Logging
```

Check Xcode Console for detailed logs:
```
Filter: "com.pocketmesh"
```

### Test Data Cleanup

To reset app for fresh testing:
```
Settings → General → iPhone Storage → PocketMesh → Delete App
(This removes all data including contacts, messages, and pairing info)
```

---

## Test Summary Template

```
Test Date: ___________________
Test Duration: ___________________
Tester Name: ___________________

Devices Used:
- MeshCore Serial Numbers: ___________________
- iPhone Models: ___________________

Tests Completed:
- [ ] Bidirectional Messaging (2 Devices)
- [ ] Multi-Hop Messaging (3 Devices)
- [ ] Contact Discovery Validation (4+ Devices)
- [ ] Channel Communication (3 Devices)
- [ ] Network Stress Test (5+ Devices)

Results Summary:
- Tests Passed: _____ / _____
- Critical Issues: ___________________
- Minor Issues: ___________________

Environment Notes:
- Location: ___________________ (indoor/outdoor, terrain)
- Weather: ___________________ (affects radio propagation)
- Interference: ___________________ (WiFi, other devices)

Recommendations:
___________________
___________________
```