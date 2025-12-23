# PocketMesh User Guide

PocketMesh is a messaging app designed for off-grid communication using MeshCore-compatible mesh networking radios.

## 1. Getting Started

### Prerequisites

- A **MeshCore-compatible BLE radio** (e.g., a companion radio or repeater).
- An iPhone running **iOS 18.0 or later**.

### Onboarding

1. **Welcome**: Launch the app and tap "Get Started".
2. **Permissions**: Grant permissions for **Bluetooth**, **Notifications**, and **Location**. These are essential for connecting to your radio and sharing your position with others.
3. **Discovery**: The app will automatically scan for nearby MeshCore devices. Select your device from the list.
4. **Pairing**: Follow the on-screen instructions to pair your device. You may need to enter a PIN (default is usually `123456`).

---

## 2. Messaging

### Direct Messages

- Go to the **Chats** tab.
- Tap the **New Chat** button or select an existing contact.
- Type your message and tap **Send**.
- **Delivery Status**:
  - **Queued**: Message is waiting to be sent to your radio.
  - **Sending**: Your radio is attempting to transmit the message.
  - **Sent**: The message has been successfully transmitted by your radio.
  - **Acknowledged**: The recipient's radio has confirmed receipt of the message.
  - **Failed**: The message could not be delivered after multiple attempts.

### Retrying Failed Messages

If a message fails to deliver:

1. Long-press the failed message.
2. Tap **Retry**.
3. The app will attempt to resend using flood routing (broadcast to all nearby nodes).
4. You'll see retry progress: "Retrying 1/4...", "Retrying 2/4...", etc.

### Group Channels

- PocketMesh supports up to 8 channel slots.
- **Slot 0 (Public)**: A default public channel for open communication.
- **Private Channels**: Configure a channel with a name and a passphrase to create a private group. Others must use the same name and passphrase to join.

---

## 3. Room Conversations

Rooms are group conversations hosted on a Room Server node.

### Joining a Room

1. Go to **Contacts** tab.
2. Find a contact with the **Room** type (purple marker on map).
3. Tap to open the room conversation.

### Room Features

- Messages are relayed through the room server.
- All participants can see messages from other members.
- Room servers can be public or require authentication.
- **Read-only** guests can view but not send messages.
- **Read/Write** guests can participate fully.

---

## 4. Contact Management

### Discovering Contacts

- Contacts are discovered when they "advertise" their presence on the mesh network.
- You can manually send an advertisement from the **Contacts** tab to let others find you.

### QR Code Sharing

Share your contact info or a channel via QR code:

#### Sharing Your Contact

1. Go to **Settings** > **My Profile**.
2. Tap **Share QR Code**.
3. Show the QR code to another PocketMesh user.
4. They scan it to add you as a contact.

#### Sharing a Channel

1. Go to **Settings** > **Channels**.
2. Select the channel you want to share.
3. Tap **Share QR Code**.
4. The QR code contains the channel name and passphrase.
5. Others scan it to join the same channel.

#### Scanning a QR Code

1. Go to **Contacts** tab.
2. Tap the **Scan QR** button.
3. Point your camera at a PocketMesh QR code.
4. The contact or channel is automatically added.

### Map View

- The **Map** tab shows the real-time location of your contacts (if they have chosen to share it).
- Markers are color-coded:
  - **Blue**: Users/Chat nodes.
  - **Green**: Repeaters.
  - **Purple**: Room Servers.

---

## 5. Repeater Status

Repeaters extend the range of your mesh network. You can view status information for nearby repeaters.

### Viewing Repeater Status

1. Go to **Contacts** tab.
2. Find a contact with the **Repeater** type (green marker on map).
3. Tap to open the repeater detail view.
4. Tap **Request Status** to query the repeater.

### Status Information

- **Battery**: Current battery level and voltage.
- **Uptime**: How long the repeater has been running.
- **SNR**: Signal-to-noise ratio of the last communication.
- **Neighbors**: Number of nodes the repeater can see.

### Viewing Neighbors

1. From the repeater detail view, tap **View Neighbors**.
2. See a list of all nodes the repeater can communicate with.
3. Each entry shows the node name, type, and signal quality.

---

## 6. Settings

### Radio Configuration

- Configure your LoRa radio parameters:
  - **Frequency**: The channel you are communicating on.
  - **Transmit Power**: Increase for better range, decrease to save battery.
  - **Spreading Factor & Bandwidth**: Adjust for a balance between speed and range.

### Device Info

- View battery level, firmware version, and manufacturer details for your connected radio.

### My Profile

- Set your display name (shown to other mesh users).
- Set your location (shared in advertisements).
- Share your contact via QR code.

---

## 7. Troubleshooting

### Connection Issues

- Ensure your radio is powered on and within Bluetooth range of your iPhone.
- If the app loses connection, it will attempt to reconnect automatically.
- If you cannot pair, try "forgetting" the device in the app and in the iOS Bluetooth settings.

### Message Delivery Failures

- Mesh networking depends on line-of-sight and signal strength.
- If a message fails, try moving to a higher location or closer to a repeater.
- You can long-press a failed message to **Retry** using flood mode.

### Sync Issues

- If contacts or channels seem out of date, pull down on the list to refresh.
- The app shows a "Syncing..." indicator when synchronizing with your radio.

### Battery Drain

- Reduce transmit power if you don't need maximum range.
- Disable location sharing if you don't need others to see your position.
- The app uses Bluetooth Low Energy, which is designed for efficiency.
