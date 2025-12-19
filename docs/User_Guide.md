# PocketMesh User Guide

PocketMesh is a messaging app designed for off-grid communication using MeshCore-compatible mesh networking radios.

## 1. Getting Started

### Prerequisites
- A **MeshCore-compatible BLE radio** (e.g., a companion radio or repeater).
- An iPhone running **iOS 18.0 or later**.

### Onboarding
1.  **Welcome**: Launch the app and tap "Get Started".
2.  **Permissions**: Grant permissions for **Bluetooth**, **Notifications**, and **Location**. These are essential for connecting to your radio and sharing your position with others.
3.  **Discovery**: The app will automatically scan for nearby MeshCore devices. Select your device from the list.
4.  **Pairing**: Follow the on-screen instructions to pair your device. You may need to enter a PIN (default is usually `123456`).

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

### Group Channels
- PocketMesh supports up to 8 channel slots.
- **Slot 0 (Public)**: A default public channel for open communication.
- **Private Channels**: Configure a channel with a name and a passphrase to create a private group. Others must use the same name and passphrase to join.

---

## 3. Contact Management

### Discovering Contacts
- Contacts are discovered when they "advertise" their presence on the mesh network.
- You can manually send an advertisement from the **Contacts** tab to let others find you.

### Map View
- The **Map** tab shows the real-time location of your contacts (if they have chosen to share it).
- Markers are color-coded:
    - **Blue**: Users/Chat nodes.
    - **Green**: Repeaters.
    - **Purple**: Room Servers.

---

## 4. Settings

### Radio Configuration
- Configure your LoRa radio parameters:
    - **Frequency**: The channel you are communicating on.
    - **Transmit Power**: Increase for better range, decrease to save battery.
    - **Spreading Factor & Bandwidth**: Adjust for a balance between speed and range.

### Device Info
- View battery level, firmware version, and manufacturer details for your connected radio.

---

## 5. Troubleshooting

### Connection Issues
- Ensure your radio is powered on and within Bluetooth range of your iPhone.
- If the app loses connection, it will attempt to reconnect automatically.
- If you cannot pair, try "forgetting" the device in the app and in the iOS Bluetooth settings.

### Message Delivery Failures
- Mesh networking depends on line-of-sight and signal strength.
- If a message fails, try moving to a higher location or closer to a repeater.
- You can long-press a failed message to **Retry** using flood mode.
