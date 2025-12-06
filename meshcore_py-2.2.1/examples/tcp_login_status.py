#!/usr/bin/python

import asyncio
import argparse
import logging
from math import log

from meshcore import MeshCore
from meshcore.events import EventType

# Set up logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

async def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Get status from a repeater via TCP connection')
    parser.add_argument('-host', '--hostname', required=True, help='TCP hostname or IP address')
    parser.add_argument('-port', '--port', type=int, required=True, help='TCP port number')
    parser.add_argument('-r', '--repeater', required=True, help='Repeater name')
    parser.add_argument('-pw', '--password', required=True, help='Password for login')
    args = parser.parse_args()

    # Connect to the device
    print(f"Connecting to TCP {args.hostname}:{args.port}...")
    mc = await MeshCore.create_tcp(args.hostname, args.port, debug=True)
    
    try:
        # Set up a simple event handler to log all events
        async def log_event(event):
            print(f"EVENT: {event.type.name} - Payload: {event.payload}")
        
        # Subscribe to login events
        mc.subscribe(EventType.LOGIN_SUCCESS, log_event)
        mc.subscribe(EventType.LOGIN_FAILED, log_event)
        mc.subscribe(EventType.STATUS_RESPONSE, log_event)
        
        # Get contacts
        await mc.ensure_contacts()
        
        repeater = mc.get_contact_by_name(args.repeater)
        
        if repeater is None:
            print(f"Repeater '{args.repeater}' not found in contacts.")
            print(f"Available contacts: {mc.contacts}")
            return
        
        print(f"Found repeater: {repeater}")
        
        # Send login request
        print(f"Sending login request to '{args.repeater}'...")
        login_cmd = await mc.commands.send_login(repeater, args.password)
        if login_cmd.type == EventType.ERROR:
            print(f"Login failed: {login_cmd.payload}")
            return
    
        filter = {"pubkey_prefix": repeater["public_key"][0:12]}
        login_result = await mc.wait_for_event(EventType.LOGIN_SUCCESS, filter, timeout=10)
        print(f"Login result: {login_result}")
            
        send_ver = await mc.commands.send_cmd(repeater, "ver")
        if send_ver.type == EventType.ERROR:
            print(f"Error sending version command: {send_ver.payload}")
            return
        await mc.wait_for_event(EventType.MESSAGES_WAITING)
        ver_msg = await mc.commands.get_msg()
        print(f"Version message: {ver_msg.payload}")
        
        # Send status request
        print("Sending status request...")
        await mc.commands.send_statusreq(repeater)
        
        # Wait for status response
        print("Waiting for status response event...")
        status_event = await mc.wait_for_event(EventType.STATUS_RESPONSE, timeout=5.0)
        
        if status_event:
            print(f"Status response received: {status_event.payload}")
        else:
            print("No status response received within timeout")
    
    finally:
        # Always disconnect properly
        print("Disconnecting...")
        await mc.disconnect()
        print("Disconnected from device")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
    except Exception as e:
        print(f"Error: {e}")