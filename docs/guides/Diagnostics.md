# Diagnostics Guide

This guide explains PocketMesh's network diagnostic tools for optimizing mesh network performance and troubleshooting connectivity issues.

## Overview

PocketMesh includes three powerful diagnostic tools:

1. **Line of Sight (LoS)** - Analyze radio propagation and terrain clearance between two points
2. **Trace Path** - Discover and save optimal routing paths through your mesh network
3. **RX Log** - Monitor live RF traffic and packet capture

---

## Line of Sight Analysis

Line of Sight analysis helps determine if a reliable RF link is possible between two points by analyzing terrain elevation and calculating Fresnel zone clearance.

### Accessing Line of Sight Tool

1. Go to **Contacts** tab
2. Find a contact or repeater you want to analyze
3. Tap to open detail view
4. Tap **Line of Sight** button in toolbar

### Understanding the Analysis

The Line of Sight tool provides:

#### Terrain Profile

A visual representation of the terrain elevation between you and the target:

- **X-Axis**: Distance from starting point (in meters)
- **Y-Axis**: Elevation (in meters)
- **Your Location**: Shown as blue dot at left edge
- **Target Location**: Shown as blue dot at right edge
- **Terrain Line**: Black line showing actual ground elevation
- **Line of Sight**: Green line indicating direct line-of-sight path

#### Fresnel Zones

The Fresnel zone is the area around the direct line-of-sight path where radio signals propagate. A clear Fresnel zone is critical for reliable communication:

- **First Fresnel Zone**: Most critical zone (60% of signal power)
- **Secondary Zones**: Less critical zones shown as dashed lines
- **Zone Calculation**: Depends on frequency and distance

**Fresnel Zone Formula**:
```
r = 17.32 × sqrt((d1 × d2) / (f × D))

Where:
- r = Fresnel zone radius (meters)
- d1 = Distance from point A to obstacle (meters)
- d2 = Distance from obstacle to point B (meters)
- f = Frequency (GHz)
- D = Total distance between A and B (meters)
```

#### Clearance Status

Color-coded indicators show link quality:

- **🟢 Green**: Clear line of sight, >60% Fresnel zone clearance expected
  - Signal quality: Excellent
  - Expected connectivity: 95-100%
  - Recommendations: No action needed

- **🟡 Yellow**: Partial obstruction, 20-60% Fresnel zone clearance
  - Signal quality: Fair to good
  - Expected connectivity: 60-95%
  - Recommendations: Increase height, use repeaters, try alternative path

- **🔴 Red**: Obstructed path, <20% Fresnel zone clearance
  - Signal quality: Poor
  - Expected connectivity: 0-60%
  - Recommendations: Significantly increase height, use multiple repeaters, relocate equipment

#### RF Parameters

Calculated signal metrics for the proposed link:

**Path Loss**:
- Expected signal attenuation in decibels (dB)
- Depends on frequency, distance, and terrain
- Lower values indicate better expected signal

**Signal Strength**:
- Estimated received signal power at target (in dBm)
- Calculated from transmit power minus path loss
- Typical values:
  - Excellent: -50 to -60 dBm
  - Good: -60 to -70 dBm
  - Fair: -70 to -80 dBm
  - Poor: -80 to -90 dBm
  - Unusable: < -90 dBm

**First Fresnel Zone Clearance**:
- Percentage of Fresnel zone that is clear of obstructions
- Critical metric for link quality
- >60%: Clear, 20-60%: Partial, <20%: Obstructed

**Maximum Range**:
- Theoretical maximum communication distance
- Based on free-space path loss formula
- Assumes ideal conditions; real-world range will be less

### Tips for Better Line of Sight

**Physical Improvements**:
- **Elevation**: Move to higher ground (hills, buildings)
- **Antenna Height**: Increase antenna height at both ends
- **Antenna Gain**: Use directional or high-gain antennas
- **Avoid Obstacles**: Clear trees, buildings, or move equipment around obstacles

**Network Improvements**:
- **Use Repeaters**: Add repeaters to bypass major obstructions
- **Optimal Pathing**: Try multiple paths to find best route
- **Frequency Selection**: Lower frequencies have better diffraction (go around obstacles)

**Analysis Best Practices**:
- **Check Weather**: Rain and humidity can affect RF propagation
- **Test Real-World**: Analysis provides estimates; actual testing is essential
- **Document Results**: Save analysis for future reference and comparison

### Elevation Data

- **Source**: Open-Meteo API (open-source terrain data)
- **Resolution**: ~90m grid
- **Accuracy**: Within ±10m for most areas
- **Offline Use**: After initial fetch, cached elevation data is used for analysis
- **API Limitations**: May not have data for some remote areas

### Technical Implementation

**Line of Sight Algorithm**:
1. Generate elevation samples along path (every 10m)
2. Calculate direct line-of-sight line between endpoints
3. For each sample point, check if terrain elevation exceeds line-of-sight elevation
4. Calculate Fresnel zone radius at each sample point
5. Determine percentage of path with clear Fresnel zone
6. Apply Earth curvature correction for long distances (>5km)

**Fresnel Zone Calculation**:
- Frequency-dependent (higher frequency = smaller Fresnel zone)
- Ellipsoid-shaped zone, widest at midpoint
- First Fresnel zone is most critical (contains 60% of signal energy)

---

## Trace Path

Trace Path discovers optimal routing paths through your mesh network by analyzing available repeaters and signal quality.

### Accessing Trace Path

1. Go to **Contacts** tab
2. Tap **Trace Path** button in toolbar
3. Select target contact or enter coordinates
4. Review discovered paths and signal quality

### Understanding Trace Path Results

#### Path Information

Each discovered path shows:

**Total Hops**:
- Number of repeaters between you and target
- Fewer hops = lower latency
- More hops = higher reliability but potential delays

**Signal Quality**:
- Average signal-to-noise ratio (SNR) across all hops
- Color-coded:
  - 🟢 Green: SNR > 15 dB (excellent)
  - 🟡 Yellow: SNR 10-15 dB (good)
  - 🔴 Red: SNR < 10 dB (poor)

**Total Distance**:
- Sum of distances for all hops
- Longer distances have higher path loss

#### Per-Hop Details

Expand each hop to see:

**Repeater Information**:
- Name and public key prefix
- Node type (Repeater, Chat, Room)
- Last seen time

**Signal Metrics**:
- **RSSI**: Received signal strength (negative dBm, closer to 0 is better)
- **SNR**: Signal-to-noise ratio (higher is better)
- **Distance**: Distance from previous hop

### Saving Paths

Save useful paths for future use:

1. Review discovered path results
2. Tap **Save Path** button
3. Enter path name (e.g., "Home to Office - Route A")
4. Path is saved for quick access later

### Managing Saved Paths

1. Go to **Contacts** tab
2. Tap **Trace Path** > **Saved Paths**
3. View all saved paths with statistics:
   - Path name
   - Total hops and distance
   - Last used date
   - Signal quality summary

4. Tap a saved path to:
   - View detailed route on map
   - See per-hop signal metrics
   - Edit path (change repeaters)
   - Delete path

5. Tap **Edit** to modify path:
   - Change repeaters in the route
   - Add or remove hops
   - Update path name

### Path Discovery Algorithm

Trace Path uses a breadth-first search to discover routes:

1. Query all known repeaters
2. Build graph of connections (edges represent known links)
3. Find all paths from source to destination
4. Rank paths by:
   - Fewest hops (latency optimization)
   - Highest average SNR (quality optimization)
   - Shortest distance (power optimization)
5. Present top 3 paths to user

### Tips for Better Paths

**Optimizing for Speed**:
- Choose paths with fewer hops
- Higher SNR per hop = faster retransmissions
- Avoid congested repeaters

**Optimizing for Reliability**:
- Higher average SNR = better reliability
- Shorter hops = lower per-hop failure rate
- Use multiple redundant paths

**Network Planning**:
- Save multiple paths for common destinations
- Test paths in different weather conditions
- Document which paths work best for different times of day

---

## RX Log Viewer

RX Log viewer captures and displays live RF traffic for network debugging and analysis.

### Accessing RX Log Viewer

1. Go to **Tools** tab
2. Tap **RX Log**
3. Viewer starts capturing packets automatically

### Understanding RX Log

Each packet entry shows:

**Timestamp**:
- When packet was received
- Format: HH:MM:SS.mmm
- Sorted chronologically

**Source**:
- Node ID that sent the packet
- Format: First 8 characters of public key
- Tap to view contact details if known

**Destination**:
- Target node ID for the packet
- May be broadcast (all nodes) or specific node

**Packet Type**:
- Category of packet:
  - **Message**: User message data
  - **Control**: Network control commands
  - **Telemetry**: Sensor data
  - **Status**: Device status updates
  - **ACK**: Acknowledgment packets
  - **NACK**: Negative acknowledgment

**Signal Metrics**:
- **RSSI**: Received signal strength indicator (dBm, closer to 0 is better)
- **SNR**: Signal-to-noise ratio (dB, higher is better)
- Color-coded:
  - 🟢 Green: Good signal (RSSI > -70 dBm, SNR > 10 dB)
  - 🟡 Yellow: Fair signal (RSSI -70 to -85 dBm, SNR 5-10 dB)
  - 🔴 Red: Poor signal (RSSI < -85 dBm, SNR < 5 dB)

**Payload**:
- Packet content (if readable)
- Truncated for large packets
- May show:
  - Message text (for message packets)
  - Telemetry values (for telemetry packets)
  - Error codes (for control packets)

### RX Log Features

#### Live Capture

- **Auto-Scroll**: Automatically scrolls to newest packets
- **Capture Toggle**: Pause/resume packet capture
- **Clear Logs**: Clear all captured packets
- **Packet Counter**: Shows total packets captured

#### Filtering

Filter logs to find specific events:

- **Filter by Packet Type**: Show only messages, telemetry, or control packets
- **Filter by Source**: Show only packets from specific node
- **Filter by Destination**: Show only packets to specific destination
- **Signal Threshold**: Show only packets above/below signal threshold

#### Export

Save logs for offline analysis:

1. Tap **Export** button
2. Select time range (1-24 hours)
3. Logs are exported as structured JSON
4. Share via email, Files app, or other sharing options

**Export Format**:
```json
{
  "timestamp": "2026-01-12T14:30:15.123Z",
  "source": "A1B2C3D4",
  "destination": "E5F6G7H8",
  "packet_type": "message",
  "rssi": -72,
  "snr": 14,
  "payload": "Hello world"
}
```

### Using RX Log for Troubleshooting

**Detecting Network Issues**:

**Packet Loss**:
- Look for gaps in sequence numbers
- Check for missing ACKs after sends
- High NACK rate indicates reliability issues

**Interference**:
- Fluctuating RSSI/SNR values
- High noise floor (low SNR even when RSSI is good)
- Pattern of failures at specific times

**Congestion**:
- High packet rate from specific nodes
- Collision indicators (packets with high retry counts)
- Latency spikes during high-traffic periods

**Routing Issues**:
- Packets taking unexpected routes
- Suboptimal hop counts to common destinations
- Nodes not advertising routes they should have

### RX Log Implementation

**Packet Capture**:
- Listens to transport layer packet stream
- Captures all received packets (including failed decodes)
- Stores in memory buffer with configurable max size

**Performance Considerations**:
- **Memory**: Log entries are lightweight (~200 bytes each)
- **CPU**: Minimal impact (packet parsing is shared with normal operation)
- **Battery**: Negligible impact (capture is passive)
- **Storage**: Limited to recent logs to prevent disk bloat

---

## Debug Logging

PocketMesh includes a comprehensive debug logging system that captures detailed operational information for troubleshooting.

### Accessing Debug Logs

Debug logs are not directly visible in the UI but can be:

- **Exported**: Via Settings > Diagnostics > Export Debug Logs
- **Shared**: Via email to development team for bug reports
- **Analyzed**: Offline using log analysis tools

### Log Categories

Logs are organized by category for easy filtering:

**Connection**:
- BLE/WiFi connection lifecycle events
- Pairing and authentication attempts
- Reconnection attempts and failures
- Transport state changes

**Messaging**:
- Message send/receive events
- Delivery status updates
- Retry attempts and failures
- ACK/NACK tracking

**Sync**:
- Contact synchronization events
- Channel synchronization events
- Data updates from device
- Version tracking and conflicts

**Transport**:
- Protocol events (connect, disconnect, data received)
- Packet parsing errors
- Transport errors and timeouts

**UI**:
- Navigation events
- User actions
- View model state changes

**Diagnostics**:
- Line of Sight calculations
- Trace Path discoveries
- RX Log captures

### Log Levels

Logs use standard severity levels:

- **Info**: Normal operational events
- **Warning**: Recoverable issues or suboptimal conditions
- **Error**: Failures or unexpected conditions

### Log Privacy

All sensitive data is automatically redacted:

- **Public Keys**: Truncated to first 8 characters
- **Passwords**: Never logged
- **Message Content**: Sanitized for privacy
- **Personal Data**: Masked or removed

### Exporting Logs

1. Go to **Settings** tab
2. Scroll to **Diagnostics** section
3. Tap **Export Debug Logs**
4. Select time range (1-24 hours)
5. Export is saved and can be shared

**Export Includes**:
- App version and device info
- Selected time range of logs
- All log entries with metadata
- Structured format for analysis

---

## Best Practices

### When to Use Diagnostic Tools

**Line of Sight**:
- Planning new node placements
- Troubleshooting poor signal to specific location
- Designing optimal network topology
- Before installing permanent equipment

**Trace Path**:
- Finding optimal routes for critical communications
- Understanding network topology
- Planning redundant paths for reliability
- Documenting network configuration

**RX Log**:
- Debugging intermittent connectivity issues
- Analyzing network traffic patterns
- Investigating packet loss or interference
- Verifying message delivery

### Documentation

Always document your diagnostic findings:

- **Date and Time**: When analysis was performed
- **Conditions**: Weather, time of day, other factors
- **Results**: All metrics and observations
- **Photos**: Screenshots or photos of equipment placement
- **Actions Taken**: Changes made based on analysis

### Limitations

**Terrain Data**:
- Elevation data may not be current (construction, vegetation changes)
- Resolution may miss small obstacles
- Underground or indoor obstacles not detected

**RF Calculations**:
- Provide theoretical estimates, not guarantees
- Assume ideal propagation conditions
- Don't account for multipath interference
- Don't account for weather effects (rain, humidity)

**Path Discovery**:
- Depends on known network topology
- Can't discover paths through unknown nodes
- Static analysis; real-world conditions may differ

---

## Further Reading

- [Architecture Overview](../Architecture.md)
- [Development Guide](../Development.md)
- [User Guide](../User_Guide.md)
