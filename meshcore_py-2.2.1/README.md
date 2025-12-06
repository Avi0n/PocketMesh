# Python MeshCore

Python library for interacting with [MeshCore](https://meshcore.co.uk) companion radio nodes.

## Installation

```bash
pip install meshcore
```

## Quick Start

Connect to your device and send a message:

```python
import asyncio
from meshcore import MeshCore, EventType

async def main():
    # Connect to your device
    meshcore = await MeshCore.create_serial("/dev/ttyUSB0")
    
    # Get your contacts
    result = await meshcore.commands.get_contacts()
    if result.type == EventType.ERROR:
        print(f"Error getting contacts: {result.payload}")
        return
        
    contacts = result.payload
    print(f"Found {len(contacts)} contacts")
    
    # Send a message to the first contact
    if contacts:
        # Get the first contact
        contact = next(iter(contacts.items()))[1]
        
        # Pass the contact object directly to send_msg
        result = await meshcore.commands.send_msg(contact, "Hello from Python!")
        
        if result.type == EventType.ERROR:
            print(f"Error sending message: {result.payload}")
        else:
            print("Message sent successfully!")
    
    await meshcore.disconnect()

asyncio.run(main())
```

## Development Setup

To set up for development:

```bash
# Create and activate virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install in development mode
pip install -e .

# Run examples
python examples/pubsub_example.py -p /dev/ttyUSB0
```

## Usage Guide

### Command Return Values

All command methods in MeshCore return an `Event` object that contains both the event type and its payload. This allows for consistent error handling and type checking:

```python
# Command result structure
result = await meshcore.commands.some_command()

# Check if the command was successful or resulted in an error
if result.type == EventType.ERROR:
    # Handle error case
    print(f"Command failed: {result.payload}")
else:
    # Handle success case - the event type will be specific to the command
    # (e.g., EventType.DEVICE_INFO, EventType.CONTACTS, EventType.MSG_SENT)
    print(f"Command succeeded with event type: {result.type}")
    # Access the payload data
    data = result.payload
```

Common error handling pattern:

```python
result = await meshcore.commands.send_msg(contact, "Hello!")
if result.type == EventType.ERROR:
    print(f"Error sending message: {result.payload}")
else:
    # For send_msg, a successful result will have type EventType.MSG_SENT
    print(f"Message sent with expected ack: {result.payload['expected_ack'].hex()}")
```

### Connecting to Your Device

Connect via Serial, BLE, or TCP:

```python
# Serial connection
meshcore = await MeshCore.create_serial("/dev/ttyUSB0", 115200, debug=True)

# BLE connection (scans for devices if address not provided)
meshcore = await MeshCore.create_ble("12:34:56:78:90:AB")

# BLE connection with PIN pairing for enhanced security
meshcore = await MeshCore.create_ble("12:34:56:78:90:AB", pin="123456")

# TCP connection
meshcore = await MeshCore.create_tcp("192.168.1.100", 4000)
```

#### BLE PIN Pairing

For enhanced security, MeshCore supports BLE PIN pairing. This requires the device to be configured with a PIN and the client to provide the matching PIN during connection:

```python
# First configure the device PIN (if not already set)
meshcore = await MeshCore.create_ble("12:34:56:78:90:AB")
await meshcore.commands.set_devicepin(123456)

# Then connect with PIN pairing
meshcore = await MeshCore.create_ble("12:34:56:78:90:AB", pin="123456")
```

**PIN Pairing Features:**
- Automatic pairing initiation when PIN is provided
- Graceful fallback if pairing fails (connection continues if device is already paired)
- Compatible with all BLE connection methods (address, scanning, pre-configured client)
- Logging of pairing success/failure for debugging

**Note:** BLE pairing behavior may vary by platform:
- **Linux/Windows**: PIN pairing is fully supported
- **macOS**: Pairing may be handled automatically by the system UI

#### Auto-Reconnect and Connection Events

Enable automatic reconnection when connections are lost:

```python
# Enable auto-reconnect with custom retry limits
meshcore = await MeshCore.create_tcp(
    "192.168.1.100", 4000,
    auto_reconnect=True,
    max_reconnect_attempts=5
)

# Subscribe to connection events
async def on_connected(event):
    print(f"Connected: {event.payload}")
    if event.payload.get('reconnected'):
        print("Successfully reconnected!")

async def on_disconnected(event):
    print(f"Disconnected: {event.payload['reason']}")
    if event.payload.get('max_attempts_exceeded'):
        print("Max reconnection attempts exceeded")

meshcore.subscribe(EventType.CONNECTED, on_connected)
meshcore.subscribe(EventType.DISCONNECTED, on_disconnected)

# Check connection status
if meshcore.is_connected:
    print("Device is currently connected")
```

**Auto-reconnect features:**
- Exponential backoff (1s, 2s, 4s, 8s max delay)
- Configurable retry limits (default: 3 attempts)
- Automatic disconnect detection (especially useful for TCP connections)
- Connection events with detailed information

### Using Commands (Synchronous Style)

Send commands and wait for responses:

```python
# Get device information
result = await meshcore.commands.send_device_query()
if result.type == EventType.ERROR:
    print(f"Error getting device info: {result.payload}")
else:
    print(f"Device model: {result.payload['model']}")

# Get list of contacts
result = await meshcore.commands.get_contacts()
if result.type == EventType.ERROR:
    print(f"Error getting contacts: {result.payload}")
else:
    contacts = result.payload
    for contact_id, contact in contacts.items():
        print(f"Contact: {contact['adv_name']} ({contact_id})")

# Send a message (destination key in bytes)
result = await meshcore.commands.send_msg(dst_key, "Hello!")
if result.type == EventType.ERROR:
    print(f"Error sending message: {result.payload}")

# Setting device parameters
result = await meshcore.commands.set_name("My Device")
if result.type == EventType.ERROR:
    print(f"Error setting name: {result.payload}")
    
result = await meshcore.commands.set_tx_power(20)  # Set transmit power
if result.type == EventType.ERROR:
    print(f"Error setting TX power: {result.payload}")
```

### Finding Contacts

Easily find contacts by name or key:

```python
# Find a contact by name
contact = meshcore.get_contact_by_name("Bob's Radio")
if contact:
    print(f"Found Bob at: {contact['adv_lat']}, {contact['adv_lon']}")
    
# Find by partial key prefix
contact = meshcore.get_contact_by_key_prefix("a1b2c3")
```

### Event-Based Programming (Asynchronous Style)

Subscribe to events to handle them asynchronously:

```python
# Subscribe to incoming messages
async def handle_message(event):
    data = event.payload
    print(f"Message from {data['pubkey_prefix']}: {data['text']}")
    
subscription = meshcore.subscribe(EventType.CONTACT_MSG_RECV, handle_message)

# Subscribe to advertisements
async def handle_advert(event):
    print("Advertisement detected!")
    
meshcore.subscribe(EventType.ADVERTISEMENT, handle_advert)

# When done, unsubscribe
meshcore.unsubscribe(subscription)
```

#### Filtering Events by Attributes

Filter events based on their attributes to handle only specific ones:

```python
# Subscribe only to messages from a specific contact
async def handle_specific_contact_messages(event):
    print(f"Message from Alice: {event.payload['text']}")
    
contact = meshcore.get_contact_by_name("Alice")
if contact:
    alice_subscription = meshcore.subscribe(
        EventType.CONTACT_MSG_RECV,
        handle_specific_contact_messages,
        attribute_filters={"pubkey_prefix": contact["public_key"][:12]}
    )

# Send a message and wait for its specific acknowledgment
async def send_and_confirm_message(meshcore, dst_key, message):
    # Send the message and get information about the sent message
    sent_result = await meshcore.commands.send_msg(dst_key, message)
    
    # Extract the expected acknowledgment code from the message sent event
    if sent_result.type == EventType.ERROR:
        print(f"Error sending message: {sent_result.payload}")
        return False
        
    expected_ack = sent_result.payload["expected_ack"].hex()
    print(f"Message sent, waiting for ack with code: {expected_ack}")
    
    # Wait specifically for this acknowledgment
    result = await meshcore.wait_for_event(
        EventType.ACK,
        attribute_filters={"code": expected_ack},
        timeout=10.0
    )
    
    if result:
        print("Message confirmed delivered!")
        return True
    else:
        print("Message delivery confirmation timed out")
        return False
```

### Hybrid Approach (Commands + Events)

Combine command-based and event-based styles:

```python
import asyncio

async def main():
    # Connect to device
    meshcore = await MeshCore.create_serial("/dev/ttyUSB0")
    
    # Set up event handlers
    async def handle_ack(event):
        print("Message acknowledged!")
    
    async def handle_battery(event):
        print(f"Battery level: {event.payload}%")
    
    # Subscribe to events
    meshcore.subscribe(EventType.ACK, handle_ack)
    meshcore.subscribe(EventType.BATTERY, handle_battery)
    
    # Create background task for battery checking
    async def check_battery_periodically():
        while True:
            # Send command (returns battery level)
            result = await meshcore.commands.get_bat()
            if result.type == EventType.ERROR:
                print(f"Error checking battery: {result.payload}")
            else:
                print(f"Battery level: {result.payload.get('level', 'unknown')}%")
            await asyncio.sleep(60)  # Wait 60 seconds between checks
    
    # Start the background task
    battery_task = asyncio.create_task(check_battery_periodically())
    
    # Send manual command and wait for response
    await meshcore.commands.send_advert(flood=True)
    
    try:
        # Keep the main program running
        await asyncio.sleep(float('inf'))
    except asyncio.CancelledError:
        # Clean up when program ends
        battery_task.cancel()
        await meshcore.disconnect()

# Run the program
asyncio.run(main())
```

### Auto-Fetching Messages

Let the library automatically fetch incoming messages:

```python
# Start auto-fetching messages
await meshcore.start_auto_message_fetching()

# Just subscribe to message events - the library handles fetching
async def on_message(event):
    print(f"New message: {event.payload['text']}")
    
meshcore.subscribe(EventType.CONTACT_MSG_RECV, on_message)

# When done
await meshcore.stop_auto_message_fetching()
```

### Debug Mode

Enable debug logging for troubleshooting:

```python
# Enable debug mode when creating the connection
meshcore = await MeshCore.create_serial("/dev/ttyUSB0", debug=True)
```

This logs detailed information about commands sent and events received.

## Common Examples

### Sending Messages to Contacts

Commands that require a destination (`send_msg`, `send_login`, `send_statusreq`, etc.) now accept either:
- A string with the hex representation of a public key
- A contact object with a "public_key" field
- Bytes object (for backward compatibility)

```python
# Get contacts and send to a specific one
result = await meshcore.commands.get_contacts()
if result.type == EventType.ERROR:
    print(f"Error getting contacts: {result.payload}")
else:
    contacts = result.payload
    for key, contact in contacts.items():
        if contact["adv_name"] == "Alice":
            # Option 1: Pass the contact object directly
            result = await meshcore.commands.send_msg(contact, "Hello Alice!")
            if result.type == EventType.ERROR:
                print(f"Error sending message: {result.payload}")
            
            # Option 2: Use the public key string
            result = await meshcore.commands.send_msg(contact["public_key"], "Hello again Alice!")
            if result.type == EventType.ERROR:
                print(f"Error sending message: {result.payload}")
            
            # Option 3 (backward compatible): Convert the hex key to bytes
            dst_key = bytes.fromhex(contact["public_key"])
            result = await meshcore.commands.send_msg(dst_key, "Hello once more Alice!")
            if result.type == EventType.ERROR:
                print(f"Error sending message: {result.payload}")
            break

# You can also directly use a contact found by name
contact = meshcore.get_contact_by_name("Bob")
if contact:
    result = await meshcore.commands.send_msg(contact, "Hello Bob!")
    if result.type == EventType.ERROR:
        print(f"Error sending message: {result.payload}")
```

### Monitoring Channel Messages

```python
# Subscribe to channel messages
async def channel_handler(event):
    msg = event.payload
    print(f"Channel {msg['channel_idx']}: {msg['text']}")
    
meshcore.subscribe(EventType.CHANNEL_MSG_RECV, channel_handler)
```

## API Reference

### Event Types

All events in MeshCore are represented by the `EventType` enum. These events are dispatched by the library and can be subscribed to:

| Event Type | String Value | Description | Typical Payload |
|------------|-------------|-------------|-----------------|
| **Device & Status Events** |||
| `SELF_INFO` | `"self_info"` | Device's own information after appstart | Device configuration, public key, coordinates |
| `DEVICE_INFO` | `"device_info"` | Device capabilities and firmware info | Firmware version, model, max contacts/channels |
| `BATTERY` | `"battery_info"` | Battery level and storage info | Battery level, used/total storage |
| `CURRENT_TIME` | `"time_update"` | Device time response | Current timestamp |
| `STATUS_RESPONSE` | `"status_response"` | Device status statistics | Battery, TX queue, noise floor, packet counts |
| `CUSTOM_VARS` | `"custom_vars"` | Custom variable responses | Key-value pairs of custom variables |
| **Contact Events** |||
| `CONTACTS` | `"contacts"` | Contact list response | Dictionary of contacts by public key |
| `NEW_CONTACT` | `"new_contact"` | New contact discovered | Contact information |
| `CONTACT_URI` | `"contact_uri"` | Contact export URI | Shareable contact URI |
| **Messaging Events** |||
| `CONTACT_MSG_RECV` | `"contact_message"` | Direct message received | Message text, sender prefix, timestamp |
| `CHANNEL_MSG_RECV` | `"channel_message"` | Channel message received | Message text, channel index, timestamp |
| `MSG_SENT` | `"message_sent"` | Message send confirmation | Expected ACK code, suggested timeout |
| `NO_MORE_MSGS` | `"no_more_messages"` | No pending messages | Empty payload |
| `MESSAGES_WAITING` | `"messages_waiting"` | Messages available notification | Empty payload |
| **Network Events** |||
| `ADVERTISEMENT` | `"advertisement"` | Node advertisement detected | Public key of advertising node |
| `PATH_UPDATE` | `"path_update"` | Routing path update | Public key and path information |
| `ACK` | `"acknowledgement"` | Message acknowledgment | ACK code |
| `PATH_RESPONSE` | `"path_response"` | Path discovery response | Inbound/outbound path data |
| `TRACE_DATA` | `"trace_data"` | Route trace information | Path with SNR data for each hop |
| **Telemetry Events** |||
| `TELEMETRY_RESPONSE` | `"telemetry_response"` | Telemetry data response | LPP-formatted sensor data |
| `MMA_RESPONSE` | `"mma_response"` | Memory Management Area data | Min/max/avg telemetry over time range |
| `ACL_RESPONSE` | `"acl_response"` | Access Control List data | List of keys and permissions |
| **Channel Events** |||
| `CHANNEL_INFO` | `"channel_info"` | Channel configuration | Channel name, secret, index |
| **Raw Data Events** |||
| `RAW_DATA` | `"raw_data"` | Raw radio data | SNR, RSSI, payload hex |
| `RX_LOG_DATA` | `"rx_log_data"` | RF log data | SNR, RSSI, raw payload |
| `LOG_DATA` | `"log_data"` | Generic log data | Various log information |
| **Binary Protocol Events** |||
| `BINARY_RESPONSE` | `"binary_response"` | Generic binary response | Tag and hex data |
| **Authentication Events** |||
| `LOGIN_SUCCESS` | `"login_success"` | Successful login | Permissions, admin status, pubkey prefix |
| `LOGIN_FAILED` | `"login_failed"` | Failed login attempt | Pubkey prefix |
| **Command Response Events** |||
| `OK` | `"command_ok"` | Command successful | Success confirmation, optional value |
| `ERROR` | `"command_error"` | Command failed | Error reason or code |
| **Connection Events** |||
| `CONNECTED` | `"connected"` | Connection established | Connection details, reconnection status |
| `DISCONNECTED` | `"disconnected"` | Connection lost | Disconnection reason |

### Available Commands

All commands are async methods that return `Event` objects. Commands are organized into functional groups:

#### Device Commands (`meshcore.commands.*`)

| Command | Parameters | Returns | Description |
|---------|------------|---------|-------------|
| **Device Information** ||||
| `send_appstart()` | None | `SELF_INFO` | Get device self-information and configuration |
| `send_device_query()` | None | `DEVICE_INFO` | Query device capabilities and firmware info |
| `get_bat()` | None | `BATTERY` | Get battery level and storage information |
| `get_time()` | None | `CURRENT_TIME` | Get current device time |
| `get_self_telemetry()` | None | `TELEMETRY_RESPONSE` | Get device's own telemetry data |
| `get_custom_vars()` | None | `CUSTOM_VARS` | Retrieve all custom variables |
| **Device Configuration** ||||
| `set_name(name)` | `name: str` | `OK` | Set device name/identifier |
| `set_coords(lat, lon)` | `lat: float, lon: float` | `OK` | Set device GPS coordinates |
| `set_time(val)` | `val: int` | `OK` | Set device time (Unix timestamp) |
| `set_tx_power(val)` | `val: int` | `OK` | Set radio transmission power level |
| `set_devicepin(pin)` | `pin: int` | `OK` | Set device PIN for security |
| `set_custom_var(key, value)` | `key: str, value: str` | `OK` | Set custom variable |
| **Radio Configuration** ||||
| `set_radio(freq, bw, sf, cr)` | `freq: float, bw: float, sf: int, cr: int` | `OK` | Configure radio (freq MHz, bandwidth kHz, spreading factor, coding rate 5-8) |
| `set_tuning(rx_dly, af)` | `rx_dly: int, af: int` | `OK` | Set radio tuning parameters |
| **Telemetry Configuration** ||||
| `set_telemetry_mode_base(mode)` | `mode: int` | `OK` | Set base telemetry mode |
| `set_telemetry_mode_loc(mode)` | `mode: int` | `OK` | Set location telemetry mode |
| `set_telemetry_mode_env(mode)` | `mode: int` | `OK` | Set environmental telemetry mode |
| `set_manual_add_contacts(enabled)` | `enabled: bool` | `OK` | Enable/disable manual contact addition |
| `set_advert_loc_policy(policy)` | `policy: int` | `OK` | Set location advertisement policy |
| **Channel Management** ||||
| `get_channel(channel_idx)` | `channel_idx: int` | `CHANNEL_INFO` | Get channel configuration |
| `set_channel(channel_idx, name, secret)` | `channel_idx: int, name: str, secret: bytes` | `OK` | Configure channel (secret must be 16 bytes) |
| **Device Actions** ||||
| `send_advert(flood=False)` | `flood: bool` | `OK` | Send advertisement (optionally flood network) |
| `reboot()` | None | None | Reboot device (no response expected) |
| **Security** ||||
| `export_private_key()` | None | `PRIVATE_KEY/DISABLED` | Export device private key (requires PIN auth & enabled firmware) |

#### Contact Commands (`meshcore.commands.*`)

| Command | Parameters | Returns | Description |
|---------|------------|---------|-------------|
| **Contact Management** ||||
| `get_contacts(lastmod=0)` | `lastmod: int` | `CONTACTS` | Get contact list (filter by last modification time) |
| `add_contact(contact)` | `contact: dict` | `OK` | Add new contact to device |
| `update_contact(contact, path, flags)` | `contact: dict, path: bytes, flags: int` | `OK` | Update existing contact |
| `remove_contact(key)` | `key: str/bytes` | `OK` | Remove contact by public key |
| **Contact Operations** ||||
| `reset_path(key)` | `key: str/bytes` | `OK` | Reset routing path for contact |
| `share_contact(key)` | `key: str/bytes` | `OK` | Share contact with network |
| `export_contact(key=None)` | `key: str/bytes/None` | `CONTACT_URI` | Export contact as URI (None exports node) |
| `import_contact(card_data)` | `card_data: bytes` | `OK` | Import contact from card data |
| **Contact Modification** ||||
| `change_contact_path(contact, path)` | `contact: dict, path: bytes` | `OK` | Change routing path for contact |
| `change_contact_flags(contact, flags)` | `contact: dict, flags: int` | `OK` | Change contact flags/settings |

#### Messaging Commands (`meshcore.commands.*`)

| Command | Parameters | Returns | Description |
|---------|------------|---------|-------------|
| **Message Handling** ||||
| `get_msg(timeout=None)` | `timeout: float` | `CONTACT_MSG_RECV/CHANNEL_MSG_RECV/NO_MORE_MSGS` | Get next pending message |
| `send_msg(dst, msg, timestamp=None)` | `dst: contact/str/bytes, msg: str, timestamp: int` | `MSG_SENT` | Send direct message |
| `send_cmd(dst, cmd, timestamp=None)` | `dst: contact/str/bytes, cmd: str, timestamp: int` | `MSG_SENT` | Send command message |
| `send_chan_msg(chan, msg, timestamp=None)` | `chan: int, msg: str, timestamp: int` | `MSG_SENT` | Send channel message |
| **Authentication** ||||
| `send_login(dst, pwd)` | `dst: contact/str/bytes, pwd: str` | `MSG_SENT` | Send login request |
| `send_logout(dst)` | `dst: contact/str/bytes` | `MSG_SENT` | Send logout request |
| **Information Requests** ||||
| `send_statusreq(dst)` | `dst: contact/str/bytes` | `MSG_SENT` | Request status from contact |
| `send_telemetry_req(dst)` | `dst: contact/str/bytes` | `MSG_SENT` | Request telemetry from contact |
| **Advanced Messaging** ||||
| `send_binary_req(dst, bin_data)` | `dst: contact/str/bytes, bin_data: bytes` | `MSG_SENT` | Send binary data request |
| `send_path_discovery(dst)` | `dst: contact/str/bytes` | `MSG_SENT` | Initiate path discovery |
| `send_trace(auth_code, tag, flags, path=None)` | `auth_code: int, tag: int, flags: int, path: list` | `MSG_SENT` | Send route trace packet |

#### Binary Protocol Commands (`meshcore.commands.*`)

| Command | Parameters | Returns | Description |
|---------|------------|---------|-------------|
| `req_status(contact, timeout=0)` | `contact: dict, timeout: float` | `STATUS_RESPONSE` | Get detailed status via binary protocol |
| `req_telemetry(contact, timeout=0)` | `contact: dict, timeout: float` | `TELEMETRY_RESPONSE` | Get telemetry via binary protocol |
| `req_mma(contact, start, end, timeout=0)` | `contact: dict, start: int, end: int, timeout: float` | `MMA_RESPONSE` | Get historical telemetry data |
| `req_acl(contact, timeout=0)` | `contact: dict, timeout: float` | `ACL_RESPONSE` | Get access control list |

### Helper Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `get_contact_by_name(name)` | `dict/None` | Find contact by advertisement name |
| `get_contact_by_key_prefix(prefix)` | `dict/None` | Find contact by partial public key |
| `is_connected` | `bool` | Check if device is currently connected |
| `subscribe(event_type, callback, filters=None)` | `Subscription` | Subscribe to events with optional filtering |
| `unsubscribe(subscription)` | None | Remove event subscription |
| `wait_for_event(event_type, filters=None, timeout=None)` | `Event/None` | Wait for specific event |

### Event Filtering

Events can be filtered by their attributes when subscribing:

```python
# Filter by public key prefix
meshcore.subscribe(
    EventType.CONTACT_MSG_RECV,
    handler,
    attribute_filters={"pubkey_prefix": "a1b2c3d4e5f6"}
)

# Filter by channel index
meshcore.subscribe(
    EventType.CHANNEL_MSG_RECV,
    handler,
    attribute_filters={"channel_idx": 0}
)

# Filter acknowledgments by code
meshcore.subscribe(
    EventType.ACK,
    handler,
    attribute_filters={"code": "12345678"}
)
```

## Examples in the Repo

Check the `examples/` directory for more:

- `pubsub_example.py`: Event subscription system with auto-fetching
- `serial_infos.py`: Quick device info retrieval
- `serial_msg.py`: Message sending and receiving
- `ble_pin_pairing_example.py`: BLE connection with PIN pairing
- `ble_private_key_export.py`: BLE private key export with PIN authentication
- `ble_t1000_infos.py`: BLE connections

