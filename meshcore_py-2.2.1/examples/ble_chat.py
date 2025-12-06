#!/usr/bin/python

import asyncio
import sys
import argparse
import json
from meshcore import MeshCore
from meshcore import BLEConnection
from meshcore import EventType

ADDRESS = "t114_fdl"
DEST = "mchome"

# Subscribe to incoming messages
async def handle_message(event):
    data = event.payload

    contact = mc.get_contact_by_key_prefix(data['pubkey_prefix'])

    print(f"{contact['adv_name']}: {data['text']}")

async def main () :
    global mc
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Print incoming messages and send message to destination")
    parser.add_argument("-a", "--addr", default=ADDRESS, help="Address or name")
    parser.add_argument("-d", "--dest", default=DEST, help="default destination")
    parser.add_argument("--timeout", type=float, default=10.0, help="ACK timeout in seconds")
    args = parser.parse_args()

    mc = await MeshCore.create_ble(args.addr)
    await mc.ensure_contacts()

    # Subscribe to private messages
    private_subscription = mc.subscribe(EventType.CONTACT_MSG_RECV, handle_message)
    
    # Subscribe to channel messages
    channel_subscription = mc.subscribe(EventType.CHANNEL_MSG_RECV, handle_message)
    
    await mc.start_auto_message_fetching()

    contact = mc.get_contact_by_name(args.dest)
    if contact is None:
        print(f"Contact '{DEST}' not found in contacts.")
        return

    try:
        while True:
            line = (await asyncio.to_thread(sys.stdin.readline)).rstrip('\n')

            if line.startswith("to ") :
                dest = line[3:]
                nc = mc.get_contact_by_name(dest)
                if mc is None:
                    print(f"Contact '{DEST}' not found in contacts.")
                    return
                else :
                    contact = nc

            elif line == "quit" or line == "q" :
                break

            elif line == "contacts" :
                print (json.dumps(mc.contacts,indent=2))

            elif line == "" :
                pass

            else :
                if line.startswith("send") :
                    line = line[5:]
                result = await mc.commands.send_msg(contact, line)
                if result.type == EventType.ERROR:
                    print(f"⚠️ Failed to send message: {result.payload}")
                    continue
                    
                exp_ack = result.payload["expected_ack"].hex()
                print(" Sent ... ", end="", flush=True)
                res = await mc.wait_for_event(EventType.ACK, attribute_filters={"code": exp_ack}, timeout=5)
                if res is None :
                    print ("No ack !!!")
                else :
                    print ("Ack")
            
    except KeyboardInterrupt:
        mc.stop()
        print("\nExiting...")
    except asyncio.CancelledError:
        # Handle task cancellation from KeyboardInterrupt in asyncio.run()
        print("\nTask cancelled - cleaning up...")
    finally:
        # Clean up subscriptions
        mc.unsubscribe(private_subscription)
        mc.unsubscribe(channel_subscription)
    
        # Stop auto-message fetching
        await mc.stop_auto_message_fetching()
    
        # Disconnect
        await mc.disconnect()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        # This prevents the KeyboardInterrupt traceback from being shown
        print("\nExited cleanly")
    except Exception as e:
        print(f"Error: {e}")
