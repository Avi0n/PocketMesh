#!/usr/bin/python
"""
Example of sending a message and waiting for its specific acknowledgment
using event attribute filtering.
"""

import asyncio
import argparse
from meshcore import MeshCore, EventType

async def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Send a message and wait for ACK")
    parser.add_argument("-p", "--port", required=True, help="Serial port")
    parser.add_argument("-b", "--baudrate", type=int, default=115200, help="Baud rate")
    parser.add_argument("-d", "--dest", default="🦄", help="Destination contact name")
    parser.add_argument("-m", "--message", default="hello from serial", help="Message to send")
    parser.add_argument("--timeout", type=float, default=30.0, help="ACK timeout in seconds")
    args = parser.parse_args()

    # Connect to the device
    mc = await MeshCore.create_serial(args.port, args.baudrate, debug=True)

    try:
        # Make sure we have contacts loaded
        await mc.ensure_contacts()
        
        # Find the contact by name
        contact = mc.get_contact_by_name(args.dest)
        if not contact:
            print(f"Contact '{args.dest}' not found. Available contacts:")
            for name, c in mc.contacts.items():
                print(f"- {c.get('adv_name', 'Unknown')}")
            return
        
        print(f"Found contact: {contact.get('adv_name')} ({contact['public_key'][:12]}...)")
        
        # Send the message and get the MSG_SENT event
        print(f"Sending message: '{args.message}'")
        result = await mc.commands.send_msg(
            contact, 
            args.message
        )
        
        if result.type == EventType.ERROR:
            print(f"⚠️ Failed to send message: {result.payload}")
            return
            
        # Extract the expected ACK code
        expected_ack = result.payload["expected_ack"].hex()
        print(f"Message sent, waiting for ACK with code: {expected_ack}")
        
        # Wait for the specific ACK that matches our message
        ack_event = await mc.wait_for_event(
            EventType.ACK,
            attribute_filters={"code": expected_ack},
            timeout=args.timeout
        )
        
        if ack_event:
            print(f"✅ Message confirmed delivered! (ACK received)")
        else:
            print(f"⚠️ Timed out waiting for ACK after {args.timeout} seconds")
    
    finally:
        # Always disconnect
        await mc.disconnect()

if __name__ == "__main__":
    asyncio.run(main())

