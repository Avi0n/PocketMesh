#!/usr/bin/python

import asyncio
import json
from meshcore import TCPConnection
from meshcore import MeshCore
from meshcore import EventType

HOSTNAME = "mchome"
PORT = 5000

async def main () :
    con  = TCPConnection(HOSTNAME, PORT)
    await con.connect()
    mc = MeshCore(con)
    await mc.connect()

    result = await mc.commands.get_contacts()
    if result.type == EventType.ERROR:
        print(f"Error getting contacts: {result.payload}")
    else:
        print(json.dumps(result.payload, indent=4))
asyncio.run(main())
