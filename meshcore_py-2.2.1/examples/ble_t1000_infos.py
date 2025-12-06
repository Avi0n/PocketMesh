#!/usr/bin/python

import asyncio

from meshcore import MeshCore

ADDRESS = "t1000"

async def main():
    mc = await MeshCore.create_ble(ADDRESS)
    
    print(mc.self_info)
    
    await mc.disconnect()

asyncio.run(main())
