#!/usr/bin/python

import asyncio
from meshcore import MeshCore
from meshcore import BLEConnection

ADDRESS = "T1000_S" # node ble adress or name
VAR = "gps"
VALUE = "1"

async def main () :
    con  = BLEConnection(ADDRESS)
    await con.connect()
    mc = MeshCore(con, debug=True)
    await mc.connect()

    print(await mc.commands.set_custom_var(VAR, VALUE))


asyncio.run(main())
