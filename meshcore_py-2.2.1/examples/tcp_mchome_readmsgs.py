#!/usr/bin/python

import asyncio
import json
from meshcore import TCPConnection
from meshcore import MeshCore
from meshcore import EventType

HOSTNAME = "mchome"
PORT = 5000
DEST = "t1000"
MSG = "Hello World"

async def main () :
    con  = TCPConnection(HOSTNAME, PORT)
    await con.connect()
    mc = MeshCore(con)
    await mc.connect()

    res = True
    while res:
        result = await mc.commands.get_msg()
        if result.type == EventType.NO_MORE_MSGS:
            res = False
            print("No more messages")
        elif result.type == EventType.ERROR:
            res = False
            print(f"Error retrieving messages: {result.payload}")
        print(result)

asyncio.run(main())
