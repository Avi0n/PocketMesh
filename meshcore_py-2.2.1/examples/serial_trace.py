#!/usr/bin/env python3
import asyncio
import argparse
import random
from meshcore import MeshCore
from meshcore.events import EventType

async def get_repeater_name(mc, hash_prefix):
    """Find a contact by its 2-character hash prefix and return its name"""
    # Ensure contacts are available
    await mc.ensure_contacts()
    
    # Find contact with matching hash prefix
    contact = mc.get_contact_by_key_prefix(hash_prefix)
    if contact:
        return contact.get("adv_name", f"Unknown ({hash_prefix})")
    else:
        return f"Unknown ({hash_prefix})"

async def main():
    parser = argparse.ArgumentParser(description='MeshCore Serial Trace Example')
    parser.add_argument('-p', '--port', required=True, help='Serial port path')
    parser.add_argument('--path', type=str, help='Trace path (comma-separated hex values)')
    args = parser.parse_args()
    
    try:
        # Connect to device
        print(f"Connecting to {args.port}...")
        mc = await MeshCore.create_serial(args.port, 115200, debug=True)
        
        # Send trace packet
        print(f"Sending trace packet...")
        # Send trace with a path if provided
        tag = random.randint(1, 0xFFFFFFFF)
        result = await mc.commands.send_trace(path=args.path, tag=tag)
        
        # Check if the result is an error
        if result.type == EventType.ERROR:
            print(f"Failed to send trace packet: {result.payload.get('reason', 'unknown error')}")
        elif result.type == EventType.MSG_SENT:
            print(f"Trace packet sent successfully with tag={tag}")
            print("Waiting for trace response matching our tag...")
            
            # Wait for a trace response with our specific tag
            event = await mc.wait_for_event(
                EventType.TRACE_DATA,
                attribute_filters={"tag": tag},
                timeout=15
            )
            
            if event:
                trace = event.payload
                print(f"Trace data received:")
                print(f"  Tag: {trace['tag']}")
                print(f"  Flags: {trace.get('flags', 0)}")
                print(f"  Path Length: {trace.get('path_len', 0)}")
                
                if trace.get('path'):
                    print(f"  Path ({len(trace['path'])} nodes):")
                    
                    # Process nodes with hash (repeaters)
                    for i, node in enumerate(trace['path']):
                        if 'hash' in node:
                            # Look up repeater name
                            repeater_name = await get_repeater_name(mc, node['hash'])
                            print(f"    Node {i+1}: {repeater_name}, SNR={node['snr']:.1f} dB")
                        else:
                            print(f"    Node {i+1}: SNR={node['snr']:.1f} dB (final node)")
            else:
                print("No trace response received within timeout")
        else:
            print("Failed to send trace packet")
        
        await mc.disconnect()
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    asyncio.run(main())