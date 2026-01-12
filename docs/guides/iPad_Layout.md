# iPad Layout Guide

This guide explains PocketMesh's iPad-specific layout and TabView-based navigation implementation.

## Overview

## Overview

PocketMesh on iPad uses a **TabView-based architecture** where each tab maintains its own navigation. On iPad, each tab implements **split-view conditionally** based on horizontal size class.

## Split-View Architecture

### Two-Panel Layout

The iPad interface is divided into two panels when horizontal size class is `.regular`:

- **Left Panel (List)**: Shows master lists (chats, contacts, map annotations, settings sections)
- **Right Panel (Detail)**: Shows selected item details (conversation, contact info, map location, setting details)

**Visual Layout**:
```
┌─────────────────┬─────────────────┐
│                 │                 │
│  List Panel    │  Detail Panel   │
│                 │                 │
│  - Chats        │  - Conversation  │
│  - Contacts     │  - Contact Info  │
│  - Map List     │  - Map Detail   │
│  - Tools List   │  - Tool Detail  │
│  - Settings     │  - Setting Panel │
│                 │                 │
└─────────────────┴─────────────────┘
```

### Panel Independence

Each panel maintains **independent navigation stacks**:

- **List Panel**: Can navigate deep (e.g., Chats > Saved Paths > Path Details)
- **Detail Panel**: Can navigate deep (e.g., Contact > Settings > Device Info)
- **No Coupling**: Changes in one panel don't affect the other panel's navigation state

### Navigation Pattern

**Selection Flow**:
1. User taps an item in the left panel
2. Right panel updates to show selected item
3. Left panel remains unchanged

**Tab Navigation**:
Each tab maintains its own navigation state:
- **Chats Tab**: Manages conversation selection and chat list navigation
- **Contacts Tab**: Manages contact selection and contacts list navigation
- **Map Tab**: Manages map selection and annotations list navigation
- **Tools Tab**: Manages tool selection and tools list navigation
- **Settings Tab**: Navigates to settings screens

**Example - Opening a Chat**:
1. User taps "Alice" in Chats list (left panel)
2. Right panel shows Alice's conversation
3. User navigates to "Channel Info" in right panel
4. Right panel shows Channel Info
5. Left panel still shows Chats list

**Example - Opening Contact Details**:
1. User taps "Bob Repeater" in Contacts list (left panel)
2. Right panel shows Bob's details
3. User navigates to "Telemetry" in right panel
4. Right panel shows Telemetry
5. Left panel still shows Contacts list

---

## Responsive Behavior

### Portrait Orientation

In portrait, the layout adjusts for better use of vertical space:

- **Stacked Layout**: List panel on top, detail panel below
- **Proportional Height**: Split view adjusts proportions based on content
- **Scrollable Independently**: Both panels can scroll independently

```
Portrait Layout:
┌─────────────────┐
│  List Panel    │  (40-50% height)
│                 │
├─────────────────┤
│  Detail Panel   │  (50-60% height)
│                 │
└─────────────────┘
```

### Landscape Orientation

In landscape, the layout maximizes horizontal space:

- **Side-by-Side Layout**: List panel on left, detail panel on right
- **Equal Width**: Each panel gets 50% of screen width
- **Resizable Divider**: User can drag divider to adjust panel widths

```
Landscape Layout:
┌─────────────────┬─────────────────┐
│  List Panel    │  Detail Panel   │  (each 50% width)
│                 │                 │
└─────────────────┴─────────────────┘
```

### Size Class Adaptation

The interface adapts to **size class** changes:

**Regular Size Class** (iPad in most orientations):
- Always shows both panels
- Split-view is the default layout
- Full-screen views are modals only

**Compact Size Class** (iPhone or split iPad):
- Shows single panel with full-screen navigation
- Uses standard iOS navigation patterns
- Tapping item pushes detail view onto navigation stack

---

## Tab-Specific Behavior

### Chats Tab

**Left Panel - Chat List**:
- Shows all conversations (direct messages, channels, rooms)
- Search bar for filtering conversations
- Pull-to-refresh functionality
- Swipe actions (archive, mute, delete)

**Right Panel - Conversation**:
- Shows message history for selected conversation
- Input bar with @mention autocomplete
- Message bubbles with delivery status
- Link previews and heard repeats

**Interactions**:
- Tapping conversation in left panel opens in right panel
- Tapping "New Chat" in left panel opens compose sheet
- Sending message in right panel updates conversation preview in left panel

### Contacts Tab

**Left Panel - Contacts List**:
- Shows all contacts (segmented by type: All, Favorites, Repeaters, Rooms)
- Search and filter options
- Node segment picker (All, Chat, Repeater, Room)
- Pull-to-refresh for sync
- Swipe actions (favorite, block, delete)

**Right Panel - Contact Details**:
- Shows contact information (name, public key, type, location)
- Quick action buttons (call, message, share QR)
- Tabs for details: Info, Settings, Line of Sight
- Repeater-specific: Status, Neighbors, Telemetry sections
- Room-specific: Messages, Participants sections

**Interactions**:
- Tapping contact in left panel opens details in right panel
- Tapping "Trace Path" in right panel shows path discovery overlay
- Tapping "Line of Sight" in right panel shows analysis overlay

### Map Tab

**Left Panel - Map Annotations**:
- Shows list of contacts with locations
- Filter options by contact type
- Search for specific contacts
- Shows last seen times and distances

**Right Panel - Map View**:
- Full interactive map with all contact markers
- Marker detail callouts
- Map layers and style selection
- Location controls (my location, zoom)

**Interactions**:
- Tapping contact in left panel centers map on contact in right panel
- Tapping marker on map in right panel shows contact callout
- Tapping "Map" in right panel toggles full-screen map overlay

### Tools Tab

**Left Panel - Tools List**:
- Shows available diagnostic tools:
  - RX Log
  - Saved Paths
  - Trace Path
- Quick access to recent results
- Tool status indicators

**Right Panel - Tool Detail**:
- Shows selected tool interface:
  - RX Log viewer with live capture
  - Saved Paths management
  - Trace Path discovery
- Tool-specific controls and settings

**Interactions**:
- Tapping tool in left panel opens tool in right panel
- Tool operates independently of left panel
- Results can be exported from right panel

### Settings Tab

**Settings tab is **full-screen** on iPad (no split-view):

- Shows all settings sections as expandable groups
- Uses full screen width for better readability
- Settings sections scroll independently
- Full-screen modals for detailed settings (Device Info, WiFi Connection)

**Full-Screen Settings Include**:
- Device Info
- WiFi Connection
- Advanced Settings
- Danger Zone (destructive operations)

---

## Navigation State Management

### AppState Integration

`AppState` manages split-view state:

```swift
@Observable class AppState {
    // Left panel selection
    var selectedTab: AppTab = .chats

    // Right panel selection
    var selectedConversation: Conversation? = nil
    var selectedContact: Contact? = nil
    var selectedTool: Tool? = nil

    // Navigation methods
    func selectConversation(_ conversation: Conversation) {
        selectedConversation = conversation
    }

    func clearSelection() {
        selectedConversation = nil
        selectedContact = nil
        selectedTool = nil
    }
}
```

### Pending Navigation

For cross-tab navigation:

```swift
// User taps notification while in Settings tab
func navigateToConversation(_ conversation: Conversation) {
    // 1. Switch to Chats tab
    selectedTab = .chats

    // 2. Select conversation in right panel
    selectedConversation = conversation

    // 3. Optionally show haptic feedback
    // ...
}
```

---

## Implementation Details

### SwiftUI Split-View

The split-view is implemented using modern SwiftUI APIs:

```swift
struct ContentView: View {
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitColumnVisibility) {
            // Left panel
            SidebarView(selectedTab: $appState.selectedTab)

            // Right panel
            DetailView(
                selectedTab: appState.selectedTab,
                selectedConversation: appState.selectedConversation,
                selectedContact: appState.selectedContact,
                selectedTool: appState.selectedTool
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
}
```

### Panel Content

**Left Panel (Sidebar)**:
```swift
struct SidebarView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            // Chats list
            ChatListView()
                .tag(AppTab.chats)

            // Contacts list
            ContactListView()
                .tag(AppTab.contacts)

            // Map annotations list
            MapAnnotationListView()
                .tag(AppTab.map)

            // Tools list
            ToolsListView()
                .tag(AppTab.tools)

            // Settings
            SettingsView()
                .tag(AppTab.settings)
        }
    }
}
```

**Right Panel (Detail)**:
```swift
struct DetailView: View {
    let selectedTab: AppTab
    @Binding var selectedConversation: Conversation?
    @Binding var selectedContact: Contact?
    @Binding var selectedTool: Tool?

    var body: some View {
        Group {
            if let conversation = selectedConversation {
                ConversationView(conversation: conversation)
            } else if let contact = selectedContact {
                ContactDetailView(contact: contact)
            } else if let tool = selectedTool {
                ToolDetailView(tool: tool)
            }
        }
    }
}
```

---

## iPad-Specific Features

### Enhanced Map

On iPad, the map view is optimized:

- **Larger Canvas**: Full right panel width for map
- **More Visible Markers**: Better marker density display
- **Pinch-to-Zoom**: Enhanced pinch gestures on larger screen
- **Map Layers**: Full-width layer selection menu

### Side-by-Side Chat

The chat interface takes advantage of split-view:

- **Persistent List**: Chat list always visible in left panel
- **Conversation Panel**: Full height for message history
- **No List Dismissal**: Don't need to dismiss list to read messages
- **Quick Switching**: Tap different conversation to switch instantly

### Expanded Settings

Settings use the full screen for better readability:

- **Full Width**: Settings sections use full screen width
- **Better Typography**: Larger text for easier reading
- **More Space**: More room for configuration options
- **Grouped Sections**: Clear visual hierarchy

### Keyboard Support

iPad supports external keyboards with shortcuts:

- **Tab**: Navigate between panels
- **Arrow Keys**: Navigate within lists
- **Return**: Select item or open detail
- **Escape**: Dismiss modals or go back
- **⌘ + N**: New chat
- **⌘ + F**: Search
- **⌘ + R**: Refresh

---

## Testing on iPad

### Simulator Testing

Test iPad layout with iPad Simulator:

```bash
# iPad Pro 12.9"
xcodebuild test \
  -destination "platform=iOS Simulator,name=iPad Pro (12.9-inch)"

# iPad Air
xcodebuild test \
  -destination "platform=iOS Simulator,name=iPad Air (6th generation)"

# iPad Mini
xcodebuild test \
  -destination "platform=iOS Simulator,name=iPad mini (6th generation)"
```

### Physical Device Testing

Test on actual iPad devices for:

- **Touch Accuracy**: Verify touch targets are appropriately sized
- **Split-View Performance**: Test with both panels loading data
- **Orientation Changes**: Test rotation between portrait/landscape
- **Multi-Window**: Test with Stage Manager (iOS 16+)
- **External Display**: Test with iPad connected to external display

### SwiftUI Previews

Test iPad layouts with SwiftUI previews:

```swift
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // iPad Pro 12.9" - Portrait
        ContentView()
            .previewInterfaceOrientation(.portrait)
            .previewDevice(.iPadPro12_9)

        // iPad Pro 12.9" - Landscape
        ContentView()
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDevice(.iPadPro12_9)

        // iPad Air - Portrait
        ContentView()
            .previewInterfaceOrientation(.portrait)
            .previewDevice(.iPadAir6)

        // iPad Mini - Landscape
        ContentView()
            .previewInterfaceOrientation(.landscapeLeft)
            .previewDevice(.iPadMini6)
    }
}
```

---

## Best Practices

### Design Considerations

**Panel Independence**:
- Never couple panel states
- Each panel should work independently
- Changes in right panel shouldn't affect left panel

**Adaptive Layout**:
- Test all size classes (compact, regular)
- Test all orientations (portrait, landscape)
- Use adaptive layouts that respond to size changes

**Responsive Content**:
- Use flexible layouts that expand/contract
- Use containerRelativeFrame for size-aware layouts
- Test with Dynamic Type for font size changes

### Performance

**Efficient Rendering**:
- Lazy-load detail views
- Use lazy stacks for long lists
- Cache expensive computations

**Memory Management**:
- Release right panel content when selection is cleared
- Avoid holding references to old detail views
- Use weak references where appropriate

---

## Common Issues

### Split-View Not Showing

**Symptom**: Only one panel visible on iPad

**Causes**:
- App running in iPhone size class (compact)
- Split-View visibility set to `automatic` instead of `all`

**Solutions**:
- Ensure testing on iPad (not iPhone simulator)
- Check `NavigationSplitView` column visibility
- Verify size class is `regular`

### Panel Navigation Confusion

**Symptom**: Changes in one panel affect the other

**Causes**:
- Coupled state between panels
- Shared navigation stacks

**Solutions**:
- Use independent `@State` for each panel
- Use separate navigation stacks
- Verify changes only affect intended panel

### Orientation Issues

**Symptom**: Layout doesn't adjust correctly on rotation

**Causes**:
- Hardcoded sizes or frames
- Not using adaptive layouts

**Solutions**:
- Use flexible layouts (`HStack`, `VStack`, `GeometryReader`)
- Use `containerRelativeFrame` for size-aware layouts
- Test with `previewInterfaceOrientation` for both orientations

---

## Further Reading

- [Architecture Overview](../Architecture.md)
- [Development Guide](../Development.md)
- [User Guide](../User_Guide.md)
- [Apple iPad Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/ipad)
