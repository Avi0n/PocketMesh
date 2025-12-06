#!/usr/bin/python

import asyncio
import json

from meshcore import MeshCore
from meshcore import SerialConnection
from meshcore import EventType

PORT = "/dev/ttyUSB0"
BAUDRATE = 115200

async def main () :
    con  = SerialConnection(PORT, BAUDRATE)
    await con.connect()
    await asyncio.sleep(0.1)
    mc = MeshCore(con)
    await mc.connect()

    result = await mc.commands.get_contacts()
    if result.type == EventType.ERROR:
        print(f"Error getting contacts: {result.payload}")
    else:
        print(json.dumps(result.payload, indent=4))

asyncio.run(main())
