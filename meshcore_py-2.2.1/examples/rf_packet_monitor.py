#!/usr/bin/env python3
import asyncio
import argparse
from meshcore import MeshCore
from meshcore.events import EventType

async def main():
    parser = argparse.ArgumentParser(description='MeshCore RF Packet Monitor')
    parser.add_argument('-p', '--port', required=True, help='Serial port path')
    args = parser.parse_args()
    
    try:
        # Connect to device
        print(f"Connecting to {args.port}...")
        mc = await MeshCore.create_serial(args.port, 115200)
        
        def handle_rf_packet(event):
            packet = event.payload
            if isinstance(packet, dict):
                print(f"Raw RF packet received:")
                if 'snr' in packet:
                    print(f"  SNR: {packet['snr']:.1f} dB")
                if 'rssi' in packet:
                    print(f"  RSSI: {packet['rssi']} dBm")
                if 'payload_length' in packet:
                    print(f"  Payload length: {packet['payload_length']} bytes")
                if 'payload' in packet:
                    print(f"  Payload (hex): {packet['payload']}")
            else:
                print(f"RF packet received: {packet}")
        
        # Subscribe to RF log data
        subscription = mc.subscribe(EventType.RX_LOG_DATA, handle_rf_packet)
        
        print("Waiting for log data (press Ctrl+C to exit)...")
        try:
            # Keep the script running to receive logs
            while True:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            print("\nExiting...")
        
        # Clean up
        mc.unsubscribe(subscription)
        await mc.disconnect()
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    asyncio.run(main())