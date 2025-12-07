# Message Context Menu and Bubble Cleanup Implementation Plan

## Overview

Add a context menu to chat messages with Reply, Copy, Details, and Delete options. Also remove the message bubble tail entirely for a cleaner look.

## Current State Analysis

### Message Bubble UI
- `MessageBubbleView` displays messages with an iMessage-style bubble
- `BubbleShape` (lines 116-158) draws a custom shape with a tail
- The tail has a visual bug where it points upward instead of horizontally

### Message Data
- `MessageDTO` contains: `id`, `timestamp` (UInt32 device time), `createdAt` (Date), `snr` (Int8 scaled by 4), `text`
- `ContactDTO` contains: `displayName` for the contact name
- `DataStore.deleteMessage(id:)` exists for local deletion

### Protocol Limitations
- MeshCore protocol has no `deleteMessage` command - messages are stored locally only
- Delete will only remove from the app, not from any device

## Desired End State

1. Long-pressing a message shows a context menu with:
   - **Reply**: Prepends `"> [name]: [first 3 words]..."` to the composer
   - **Copy**: Copies message text to clipboard
   - **Details**: Nested submenu showing time sent, time received (incoming only), SNR (incoming only)
   - **Delete**: Removes message from local storage

2. Message bubbles are simple rounded rectangles without tails

### Verification
- Build succeeds with no warnings
- Context menu appears on long-press
- Reply prefills the composer correctly
- Copy works via clipboard
- Details shows correct information
- Delete removes message from conversation
- Bubbles are clean rounded rectangles

## What We're NOT Doing

- Device-level message deletion (no protocol support)
- Message editing
- Forwarding messages
- Multi-select for bulk operations
- Read receipts toggle

## Implementation Approach

We'll modify `MessageBubbleView` to add the context menu and pass the necessary callbacks. Replace `BubbleShape` with a simple rounded rectangle.

## Phase 1: Remove Bubble Tail

### Overview
Remove the custom `BubbleShape` and use a simple rounded rectangle for message bubbles.

### Changes Required:

#### 1. Replace BubbleShape with RoundedRectangle
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Replace `.clipShape(BubbleShape(isOutgoing: message.isOutgoing))` with `.clipShape(.rect(cornerRadius: 16))`

```swift
// In MessageBubbleView body, change:
Text(message.text)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(bubbleColor)
    .foregroundStyle(textColor)
    .clipShape(.rect(cornerRadius: 16))
```

#### 2. Delete BubbleShape struct
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Remove the entire `BubbleShape` struct (lines 116-159)

#### 3. Update TypingIndicator
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Update TypingIndicator to use rounded rectangle instead of BubbleShape

```swift
struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(animationPhase == index ? 1.0 : 0.4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(.rect(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -scheme PocketMesh -destination "platform=iOS Simulator,name=iPhone 17" build`

#### Manual Verification:
- [ ] Message bubbles are clean rounded rectangles
- [ ] No tail or protrusion visible on either incoming or outgoing messages

---

## Phase 2: Add Context Menu to Message Bubbles

### Overview
Add a context menu with Reply, Copy, Details (nested), and Delete options.

### Changes Required:

#### 1. Update MessageBubbleView Interface
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Add contact name and callbacks for reply/delete actions

```swift
struct MessageBubbleView: View {
    let message: MessageDTO
    let contactName: String
    let showTimestamp: Bool
    let onRetry: (() -> Void)?
    let onReply: ((String) -> Void)?
    let onDelete: (() -> Void)?

    init(
        message: MessageDTO,
        contactName: String,
        showTimestamp: Bool = false,
        onRetry: (() -> Void)? = nil,
        onReply: ((String) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.message = message
        self.contactName = contactName
        self.showTimestamp = showTimestamp
        self.onRetry = onRetry
        self.onReply = onReply
        self.onDelete = onDelete
    }

    // ... existing body code ...
}
```

#### 2. Add Context Menu to Bubble
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Wrap the message text in a context menu

```swift
// Inside the VStack for message bubble content, wrap the Text:
Text(message.text)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(bubbleColor)
    .foregroundStyle(textColor)
    .clipShape(BubbleShape(isOutgoing: message.isOutgoing))
    .contextMenu {
        // Reply button
        Button {
            let replyText = buildReplyText()
            onReply?(replyText)
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        // Copy button
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        // Details submenu
        Menu {
            // Time sent (always shown)
            Text("Sent: \(message.date.formatted(date: .abbreviated, time: .shortened))")

            // Time received (incoming only) - use createdAt as receive time
            if !message.isOutgoing {
                Text("Received: \(message.createdAt.formatted(date: .abbreviated, time: .shortened))")
            }

            // SNR (incoming only)
            if !message.isOutgoing, let snrValue = message.snrValue {
                Text("SNR: \(snrFormatted(snrValue))")
            }
        } label: {
            Label("Details", systemImage: "info.circle")
        }

        Divider()

        // Delete button
        Button(role: .destructive) {
            onDelete?()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
```

#### 3. Add Helper Methods to MessageBubbleView
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Add methods for building reply text and formatting SNR

```swift
// MARK: - Context Menu Helpers

private func buildReplyText() -> String {
    // Get sender name - contact name for incoming, device name for outgoing
    let senderName = message.isOutgoing ? deviceName : contactName

    // Get first three words
    let words = message.text.split(separator: " ").prefix(3)
    let preview = words.joined(separator: " ")
    let suffix = message.text.split(separator: " ").count > 3 ? "..." : ""

    return "> \(senderName): \(preview)\(suffix)"
}

private var deviceName: String {
    // Use the contact's device name or a default
    // This will be passed in from the parent view
    contactName  // For now, we'll need to update this
}

private func snrFormatted(_ snr: Float) -> String {
    let quality: String
    switch snr {
    case 10...:
        quality = "Excellent"
    case 5..<10:
        quality = "Good"
    case 0..<5:
        quality = "Fair"
    case -10..<0:
        quality = "Poor"
    default:
        quality = "Very Poor"
    }
    return String(format: "%.1f dB (%@)", snr, quality)
}
```

#### 4. Update ChatView to Pass Required Data
**File**: `PocketMesh/Views/Chats/ChatView.swift`
**Changes**: Pass contact name, device name, and callbacks to MessageBubbleView

```swift
private var messagesContent: some View {
    ForEach(viewModel.messages.enumeratedElements(), id: \.element.id) { index, message in
        MessageBubbleView(
            message: message,
            contactName: contact.displayName,
            showTimestamp: shouldShowTimestamp(at: index),
            onRetry: message.hasFailed ? { retryMessage(message) } : nil,
            onReply: { replyText in
                setReplyText(replyText)
            },
            onDelete: {
                deleteMessage(message)
            }
        )
        .id(message.id)
    }
}

private func setReplyText(_ text: String) {
    viewModel.composingText = text + "\n"
    isInputFocused = true
}

private func deleteMessage(_ message: MessageDTO) {
    Task {
        await viewModel.deleteMessage(message)
    }
}
```

#### 5. Add deleteMessage to ChatViewModel
**File**: `PocketMesh/Views/Chats/ChatViewModel.swift`
**Changes**: Add method to delete a single message

```swift
/// Delete a single message
func deleteMessage(_ message: MessageDTO) async {
    guard let dataStore else { return }

    do {
        try await dataStore.deleteMessage(id: message.id)

        // Remove from local array
        messages.removeAll { $0.id == message.id }

        // Update last message date if needed
        if let currentContact {
            if let lastMessage = messages.last {
                try await dataStore.updateContactLastMessage(
                    contactID: currentContact.id,
                    date: lastMessage.date
                )
            } else {
                try await dataStore.updateContactLastMessage(
                    contactID: currentContact.id,
                    date: Date.distantPast
                )
            }
        }
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

#### 6. Pass Device Name for Outgoing Reply Text
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Add device name parameter

Update the struct to include `deviceName`:

```swift
struct MessageBubbleView: View {
    let message: MessageDTO
    let contactName: String
    let deviceName: String
    let showTimestamp: Bool
    let onRetry: (() -> Void)?
    let onReply: ((String) -> Void)?
    let onDelete: (() -> Void)?

    init(
        message: MessageDTO,
        contactName: String,
        deviceName: String = "Me",
        showTimestamp: Bool = false,
        onRetry: (() -> Void)? = nil,
        onReply: ((String) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.message = message
        self.contactName = contactName
        self.deviceName = deviceName
        self.showTimestamp = showTimestamp
        self.onRetry = onRetry
        self.onReply = onReply
        self.onDelete = onDelete
    }

    private func buildReplyText() -> String {
        let senderName = message.isOutgoing ? deviceName : contactName
        let words = message.text.split(separator: " ").prefix(3)
        let preview = words.joined(separator: " ")
        let suffix = message.text.split(separator: " ").count > 3 ? "..." : ""
        return "> \(senderName): \(preview)\(suffix)"
    }
}
```

**File**: `PocketMesh/Views/Chats/ChatView.swift`
**Changes**: Pass device name from AppState

```swift
private var messagesContent: some View {
    ForEach(viewModel.messages.enumeratedElements(), id: \.element.id) { index, message in
        MessageBubbleView(
            message: message,
            contactName: contact.displayName,
            deviceName: appState.connectedDevice?.nodeName ?? "Me",
            showTimestamp: shouldShowTimestamp(at: index),
            onRetry: message.hasFailed ? { retryMessage(message) } : nil,
            onReply: { replyText in
                setReplyText(replyText)
            },
            onDelete: {
                deleteMessage(message)
            }
        )
        .id(message.id)
    }
}
```

#### 7. Update Preview Providers
**File**: `PocketMesh/Views/Chats/MessageBubbleView.swift`
**Changes**: Update previews to include new parameters

```swift
#Preview("Outgoing - Sent") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Hello! How are you doing today?",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.sent.rawValue
    )
    return MessageBubbleView(
        message: MessageDTO(from: message),
        contactName: "Alice",
        deviceName: "My Device"
    )
}

// ... update other previews similarly
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -scheme PocketMesh -destination "platform=iOS Simulator,name=iPhone 17" build`

#### Manual Verification:
- [ ] Long-pressing a message shows context menu
- [ ] "Reply" adds formatted reply text to composer and focuses input
- [ ] "Copy" copies message text to clipboard
- [ ] "Details" submenu shows time sent
- [ ] "Details" shows time received for incoming messages only
- [ ] "Details" shows SNR with quality description for incoming messages only
- [ ] "Delete" removes the message from the conversation
- [ ] Reply text format is correct: `> Name: first three words...`

---

## Testing Strategy

### Unit Tests:
- Test `buildReplyText()` with various message lengths (0-2 words, 3 words, 4+ words)
- Test `snrFormatted()` for all quality thresholds
- Test `deleteMessage()` updates the messages array correctly

### Manual Testing Steps:
1. Open a conversation with existing messages
2. Long-press an outgoing message - verify context menu appears
3. Tap Reply - verify composer shows `> [DeviceName]: first three...`
4. Long-press an incoming message
5. Tap Reply - verify composer shows `> [ContactName]: first three...`
6. Long-press and tap Copy - paste elsewhere to verify
7. Long-press and open Details submenu on outgoing message - verify only time sent shown
8. Long-press and open Details submenu on incoming message - verify time sent, received, and SNR shown
9. Long-press and tap Delete - verify message is removed
10. Close and reopen conversation - verify deleted message stays deleted
11. Verify message bubbles are clean rounded rectangles without tails

## References

- Message model: `PocketMeshKit/Models/Message.swift`
- Bubble view: `PocketMesh/Views/Chats/MessageBubbleView.swift`
- Chat view: `PocketMesh/Views/Chats/ChatView.swift`
- Chat view model: `PocketMesh/Views/Chats/ChatViewModel.swift`
- DataStore deletion: `PocketMeshKit/Services/DataStore.swift:555`
