# PocketMesh User Guide

PocketMesh is a messaging app designed for off-grid communication using MeshCore-compatible mesh networking radios.

## 1. Getting Started

### Prerequisites

- A **MeshCore-compatible BLE radio** (e.g., a companion radio or repeater).
- An iPhone running **iOS 18.0 or later**.

### Onboarding

1. **Welcome**: Launch the app and tap "Get Started".
2. **Permissions**: Grant permissions for **Notifications** and **Location**. Location is needed for sharing your position with other mesh users.
3. **Discovery**: The app will scan for nearby MeshCore devices using AccessorySetupKit. Select your device from the list.
4. **Pairing**: Follow the on-screen instructions to pair your device. Bluetooth permission is requested automatically by AccessorySetupKit during device discovery. You may be prompted to enter a device PIN (device-specific).

---

## 2. Messaging

### Direct Messages

- Go to **Chats** tab.
- Tap to **square.and.pencil** menu button and select **New Chat**, or select an existing contact.
- Type your message and tap **Send**.
- **Delivery Status** (shown as text labels below outgoing messages):
  - **"Sending..."**: Message is pending or being transmitted to your radio.
  - **"Sent"**: The message has been successfully transmitted by your radio.
  - **"Delivered"**: The recipient's radio has confirmed receipt of message.
  - **"Retrying..."**: The app is attempting to resend using flood routing (with spinner indicator).
  - **"Failed"**: The message could not be delivered after multiple attempts (red bubble background with exclamation icon).

### @Mentions

Mention other contacts in group chats to get their attention:

1. Type **@** in the message input field while composing.
2. A dropdown will appear with matching contacts from your contacts list.
3. Select a contact to insert their name as a mention.
4. The mentioned contact will be notified of the message.
5. Mentions are highlighted in the message for easy identification.

**Tips**:
- Mentions work in all message types: direct messages, channels, and rooms.
- The dropdown shows contact names and node names.
- Filter suggestions by typing after **@**.

### Link Previews

PocketMesh automatically generates rich previews for URLs shared in messages:

1. Paste a URL into the message input (e.g., `https://example.com`).
2. The app will fetch metadata (title, description, image) when the message is sent.
3. Recipients see a preview card instead of just the raw URL.
4. Tap the preview card to open the link in Safari.
5. Toggle link previews on/off in **Settings** > **Link Preview Settings**.

**Link Preview Settings**:
- **Enable Link Previews**: Turn automatic preview generation on/off.
- **Always Fetch Previews**: Fetch previews even when using WiFi or cellular data (for testing).
- Preview cards are fetched on-demand when messages are loaded.

### Muting Conversations

Mute notifications for individual conversations to reduce distractions:

1. In the **Chats** list, swipe left on the conversation you want to mute.
2. Tap **Mute**.
3. The conversation will show a **muted bell icon** to indicate it's muted.
4. You'll still receive messages, but no notifications will appear.
5. Swipe left again and tap **Unmute** to re-enable notifications.

**Note**: Muted conversations still display unread message badges in the app, just not push notifications.

### Blocking Contacts

Block unwanted contacts to prevent receiving messages from them:

1. In the **Contacts** list, swipe left on the contact you want to block.
2. Tap **Block**.
3. The contact will be moved to **Blocked Contacts** section.
4. Blocked contacts cannot send you messages.
5. You can view and manage blocked contacts from the **Contacts** tab.
6. Swipe left on a blocked contact and tap **Unblock** to allow messages again.

**Note**: Repeaters and room servers cannot be blocked (block option is hidden for these contact types).

### Retrying Failed Messages

If a message fails to deliver:

1. Tap the **Retry** button that appears below the failed message.
2. The app will attempt to resend using flood routing (broadcast to all nearby nodes).
3. You'll see retry progress: "Retrying 1/4...", "Retrying 2/4...", etc.

### Group Channels

- PocketMesh supports up to 8 channel slots (0-7).
- **Slot 0 (Public)**: A default public channel for open communication.
- **Private Channels**: Configure a channel with a name and a passphrase to create a private group. Others must use the same name and passphrase to join.

---

## 3. Room Conversations

Rooms are group conversations hosted on a Room Server node.

### Joining a Room

1. Go to **Contacts** tab.
2. Find a contact with the **Room** type (purple marker on map).
3. Tap to open the room conversation.
4. If the room requires authentication, you'll be prompted to enter credentials.

### Room Authentication

When connecting to a room that requires authentication:

1. An authentication sheet will appear automatically.
2. Enter the required credentials (username/password or authentication code).
3. If the room is already in your chat list but disconnected, tap it to show the authentication sheet and reconnect.
4. Once authenticated, you can send and receive messages.

### Room Features

- Messages are relayed through the room server.
- All participants can see messages from other members.
- Room servers can be public or require authentication.
- **Read-only** guests can view but not send messages.
- **Read/Write** guests can participate fully.
- To leave a room, swipe left on the room conversation in the Chats list and select **Delete**. This will remove the room, delete all messages, and remove the associated contact.

---

## 4. Contact Management

### Discovering Contacts

- Contacts are discovered when they "advertise" their presence on the mesh network.
- You can manually send an advertisement from the **Contacts** tab by going to the **ellipsis menu** (top right) > **Discovery**.

### QR Code Sharing

Share your contact info or a channel via QR code:

#### Sharing Your Contact

1. Go to **Contacts** tab.
2. Tap the **ellipsis menu** (top right).
3. Select **Share My Contact**.
4. Show the QR code to another PocketMesh user.
5. They scan it to add you as a contact.

#### Sharing a Channel

1. Go to **Chats** tab.
2. Open the channel conversation you want to share.
3. Tap the **info button** (top right).
4. The QR code is displayed automatically in the channel info sheet.
5. The QR code contains the channel name and passphrase.
6. Others scan it to join the same channel.

#### Scanning a QR Code

1. Go to **Contacts** tab.
2. Tap the **ellipsis menu** (top right).
3. Select **Add Contact**.
4. Tap **Scan QR Code**.
5. Point your camera at a PocketMesh QR code.
6. The contact or channel is automatically added.

### Map View

- The **Map** tab shows the real-time location of your contacts (if they have chosen to share it).
- Markers are color-coded:
  - **Blue**: Users/Chat nodes.
  - **Orange**: Favorite contacts.
  - **Green**: Repeaters.
  - **Purple**: Room Servers.

### Contact Actions

You can perform quick actions on contacts using swipe gestures:

- **Swipe right**: Mark as **Favorite** (or remove from favorites).
- **Swipe left**: **Block** or **Delete** the contact.

### Discovery View

The Discovery view shows contacts that have been discovered on the mesh but not yet added to your device (when auto-add contacts is disabled).

1. Go to **Contacts** tab.
2. Tap the **ellipsis menu** (top right).
3. Select **Discovery**.
4. You'll see a list of discovered contacts with an **Add** button next to each.
5. Tap **Add** to add a contact to your device.

From the Discovery view, you can also send an advertisement to let other mesh users discover you.

---

## 5. Repeater Status

Repeaters extend the range of your mesh network. You can view status information for nearby repeaters.

### Viewing Repeater Status

1. Go to **Contacts** tab.
2. Find a contact with the **Repeater** type (green marker on map).
3. Tap to open the repeater detail view.
4. Status is automatically requested when the view loads. You can refresh by pulling down or tapping the **refresh button** in the toolbar.

### Status Information

The status section displays:

- **Battery**: Current battery level and voltage.
- **Uptime**: How long the repeater has been running.
- **Clock**: Repeater's current time.
- **Last RSSI**: Received Signal Strength Indicator.
- **Last SNR**: Signal-to-noise ratio of the last communication.
- **Noise Floor**: Background radio noise level.
- **Packets Sent**: Total packets transmitted.
- **Packets Received**: Total packets received.

### Viewing Neighbors

1. From the repeater status view, find the **Neighbors** disclosure group.
2. Tap to expand and see all nodes the repeater can communicate with.
3. Neighbors are loaded on-demand when you first expand the section.
4. Each entry shows the public key prefix, last seen time, and SNR (color-coded: green for good, yellow for fair, red for poor signal).

### Viewing Telemetry

1. From the repeater status view, find the **Telemetry** disclosure group.
2. Tap to expand and see sensor data from the repeater.
3. Telemetry data is loaded on-demand when you first expand the section.
4. Available sensors may include temperature, voltage, and other environmental data depending on the repeater's configuration.

---

## 6. Settings

Access Settings from the **Settings** tab.

### Radio Configuration

- Configure your LoRa radio parameters using presets or custom values:
  - **Presets**: Quick configuration options for common use cases.
  - **Frequency**: The channel you are communicating on.
  - **Transmit Power**: Increase for better range, decrease to save battery.
  - **Spreading Factor & Bandwidth**: Adjust for a balance between speed and range.

### Device Info

- View battery level, firmware version, and manufacturer details for your connected radio.
- The Device Info section is collapsible - tap to expand or collapse.

### Node Settings

- Set your **Node Name** (shown to other mesh users on the mesh network).
- Configure how your device behaves on the mesh.

### Advanced Settings

Advanced settings are available for power users:

1. Go to **Settings** tab.
2. Scroll to the bottom and tap **Advanced Settings**.

Advanced settings include:

- **Manual Radio Configuration**: Fine-tune radio parameters beyond standard presets.
- **Contacts Settings**: Configure auto-add contacts behavior and other contact management options.
- **Telemetry Settings**: Configure sensor data reporting.
- **Danger Zone**: Reset device, clear data, and other destructive operations.

---

## 7. Network Diagnostics Tools

PocketMesh includes powerful diagnostic tools for optimizing your mesh network performance and troubleshooting connectivity issues.

### Line of Sight Analysis

The Line of Sight (LoS) tool analyzes radio propagation between two points to help you determine if a reliable link is possible.

#### Accessing Line of Sight

1. Go to **Contacts** tab.
2. Find the contact or repeater you want to analyze.
3. Tap to open detail view.
4. Tap **Line of Sight** button in the toolbar.

#### Understanding the Analysis

The tool provides:

- **Terrain Profile**: Visual representation of terrain elevation between you and target
- **Fresnel Zone**: Visualization of the RF signal's optimal path (shown as curved lines)
- **Clearance Status**: Color-coded indicators:
  - **Green**: Clear line of sight, good signal expected
  - **Yellow**: Partial obstruction, signal may be degraded
  - **Red**: Obstructed path, poor signal or no connection likely
- **RF Parameters**: Calculated signal metrics:
  - **Path Loss**: Expected signal attenuation (in dB)
  - **Signal Strength**: Estimated received signal at target
  - **First Fresnel Zone**: Percentage of clear Fresnel zone
  - **Maximum Range**: Theoretical maximum communication distance

#### Tips for Better Results

- Elevation data is fetched from Open-Meteo API (may require internet for first use)
- Move to higher ground if analysis shows obstruction
- Consider using repeaters to bypass obstacles
- Analysis assumes ideal conditions - real-world performance may vary

### Trace Path

Discover optimal routing paths through your mesh network with the Trace Path tool.

#### Using Trace Path

1. Go to **Contacts** tab.
2. Tap **Trace Path** in the toolbar.
3. The app will discover available routes through repeaters to your target.
4. Review the suggested path with signal quality indicators.
5. Tap **Save Path** to store the route for future use.

#### Path Information

Each path shows:

- **Total Hops**: Number of repeaters in the path
- **Signal Quality**: Average SNR across the path (green/yellow/red)
- **Distance**: Total path length
- **Repeater Details**: For each hop:
  - Repeater name and public key prefix
  - SNR (signal quality)
  - Distance from previous hop

#### Saved Paths

1. Go to **Contacts** tab.
2. Tap **Trace Path** > **Saved Paths**.
3. View all saved routing paths with statistics.
4. Tap a saved path to see details:
  - Path visualization on map
  - Signal quality per hop
  - Total distance and hops
5. Edit paths by selecting different repeaters or deleting entries.

### RX Log Viewer

Monitor live RF traffic and packet capture with the RX Log viewer.

#### Accessing RX Log

1. Go to **Tools** tab.
2. Tap **RX Log**.
3. The viewer starts capturing packets automatically.

#### Understanding RX Log

The log shows:

- **Timestamp**: When packet was received
- **Source**: Node ID that sent the packet
- **Destination**: Target node ID
- **Packet Type**: Message, control, telemetry, etc.
- **RSSI**: Signal strength
- **SNR**: Signal-to-noise ratio
- **Payload**: Packet content (if readable)

#### Features

- **Live Capture**: Real-time packet stream
- **Auto-Scroll**: Automatically scrolls to newest packets
- **Filter**: Filter by packet type, source, or destination
- **Export**: Save logs for analysis

#### Tips

- Useful for debugging connectivity issues
- Identify which repeaters are active on your network
- Detect interference or packet loss patterns
- Close viewer when done to save battery

---

## 8. iPad Experience

PocketMesh provides an optimized experience on iPad with split-view navigation and enhanced layouts.

### Split-View Navigation

On iPad, the app uses a split-view layout:

- **Left Panel**: List view (chats, contacts, etc.)
- **Right Panel**: Detail view (conversation, contact details, map, etc.)
- **Independent Navigation**: Each panel has its own navigation stack
- **Responsive**: Automatically adjusts when rotating device or resizing window

#### Navigation Behavior

- Tapping an item in left panel opens it in right panel
- Right panel navigation doesn't affect left panel state
- Close right panel by tapping back button or swiping
- Both panels update independently when data changes

#### Tab Navigation

- All tabs (Chats, Contacts, Map, Tools, Settings) support split-view
- Map shows full map in right panel when location is selected
- Chat conversation opens in right panel while chat list remains visible
- Settings open as full-screen modals on iPad (not split-view)

### iPad-Specific Features

- **Enhanced Map**: Larger map view with more visible markers
- **Side-by-Side Chat**: View conversation list and chat simultaneously
- **Expanded Settings**: More space for configuration options
- **Keyboard Support**: Full keyboard shortcuts for common actions

### Orientation Support

- **Portrait**: Stacked panels (list on top, detail below)
- **Landscape**: Side-by-side panels (list on left, detail on right)
- **Resize**: Drag divider to adjust panel sizes (when supported by iOS)

---

## 9. Troubleshooting

### Connection Issues

- Ensure your radio is powered on and within Bluetooth range of your iPhone.
- If the app loses connection, it will attempt to reconnect automatically.
- If you cannot pair, try "forgetting" the device in the app and in the iOS Bluetooth settings.

### Message Delivery Failures

- Mesh networking depends on line-of-sight and signal strength.
- If a message fails, try moving to a higher location or closer to a repeater.
- You can tap the **Retry** button on a failed message to resend using flood mode.

### Sync Issues

- If contacts or channels seem out of date, pull down on the list to refresh.
- The app shows a "Syncing..." indicator when synchronizing with your radio.

### Battery Drain

- Reduce transmit power if you don't need maximum range.
- Disable location sharing if you don't need others to see your position.
- The app uses Bluetooth Low Energy, which is designed for efficiency.
