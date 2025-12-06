#!/usr/bin/python

import asyncio

from meshcore import MeshCore

HOSTNAME = "mchome"
PORT = 5000

async def main():
    mc = await MeshCore.create_tcp(HOSTNAME, PORT)
    
    print(mc.self_info)
    
    await mc.disconnect()

asyncio.run(main())
