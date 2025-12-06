#!/usr/bin/python

import asyncio
import argparse

from meshcore import MeshCore
from meshcore.events import EventType

async def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Get status from a repeater via serial connection')
    parser.add_argument('-p', '--port', required=True, help='Serial port')
    parser.add_argument('-b', '--baudrate', type=int, default=115200, help='Baud rate')
    parser.add_argument('-r', '--repeater', required=True, help='Repeater name')
    parser.add_argument('-pw', '--password', required=True, help='Password for login')
    parser.add_argument('-t', '--timeout', type=float, default=10.0, help='Timeout for responses in seconds')
    args = parser.parse_args()

    # Connect to the device
    mc = await MeshCore.create_serial(args.port, args.baudrate, debug=True)
    
    try:
        # Get contacts
        await mc.ensure_contacts()
        repeater = mc.get_contact_by_name(args.repeater)
        
        if repeater is None:
            print(f"Repeater '{args.repeater}' not found in contacts.")
            return
        
        # Send login request
        print(f"Logging in to repeater '{args.repeater}'...")
        login_event = await mc.commands.send_login(repeater, args.password)
        
        if login_event.type != EventType.ERROR:
            print("Login successful")
            
            # Send status request
            print("Sending status request...")
            await mc.commands.send_statusreq(repeater)
            
            # Wait for status response
            status_event = await mc.wait_for_event(EventType.STATUS_RESPONSE, timeout=args.timeout)
            
            if status_event:
                # Format status information nicely
                status = status_event.payload
                print("\nRepeater Status:")
                print(f"  Battery: {status.get('bat', 'N/A')}%")
                print(f"  Uptime: {status.get('uptime', 'N/A')} seconds")
                print(f"  Last RSSI: {status.get('last_rssi', 'N/A')}")
                print(f"  Last SNR: {status.get('last_snr', 'N/A')} dB")
                print(f"  Messages received: {status.get('nb_recv', 'N/A')}")
                print(f"  Messages sent: {status.get('nb_sent', 'N/A')}")
                print(f"  Direct messages sent: {status.get('sent_direct', 'N/A')}")
                print(f"  Flood messages sent: {status.get('sent_flood', 'N/A')}")
                print(f"  Direct messages received: {status.get('recv_direct', 'N/A')}")
                print(f"  Flood messages received: {status.get('recv_flood', 'N/A')}")
                print(f"  Direct duplicates: {status.get('direct_dups', 'N/A')}")
                print(f"  Flood duplicates: {status.get('flood_dups', 'N/A')}")
                print(f"  TX queue length: {status.get('tx_queue_len', 'N/A')}")
                print(f"  Free queue length: {status.get('free_queue_len', 'N/A')}")
                print(f"  Full events: {status.get('full_evts', 'N/A')}")
                print(f"  Airtime: {status.get('airtime', 'N/A')}")
            else:
                print("Timed out waiting for status response")
        else:
            print("Login failed or timed out")
    
    finally:
        # Always disconnect properly
        await mc.disconnect()
        print("Disconnected from device")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
    except Exception as e:
        print(f"Error: {e}")