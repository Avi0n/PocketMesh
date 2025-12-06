#!/usr/bin/python

import asyncio
from meshcore import MeshCore
from meshcore import BLEConnection

ADDRESS = "T1000_S" # node ble adress or name

async def main () :
    con  = BLEConnection(ADDRESS)
    await con.connect()
    mc = MeshCore(con)
    await mc.connect()

    print(await mc.commands.get_custom_vars())

asyncio.run(main())
