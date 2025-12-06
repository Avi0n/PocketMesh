#!/usr/bin/python

import asyncio
import json
from meshcore import MeshCore
from meshcore import TCPConnection
from meshcore import EventType

HOSTNAME = "mchome"
PORT = 5000
DEST = "t114_fdl"
MSG = "Hello World"

async def main () :
    con  = TCPConnection(HOSTNAME, PORT)
    await con.connect()
    mc = MeshCore(con)
    await mc.connect()

    await mc.ensure_contacts()
    contact = mc.get_contact_by_name(DEST)
    if contact is None:
        print(f"Contact '{DEST}' not found in contacts.")
        return
    result = await mc.commands.send_msg(contact, MSG)
    print(result)
    
    if result.type == EventType.ERROR:
        print(f"⚠️ Failed to send message: {result.payload}")
        return
        
    exp_ack = result.payload["expected_ack"].hex()
    print(await mc.wait_for_event(EventType.ACK, attribute_filters={"code": exp_ack}, timeout=5))

asyncio.run(main())
