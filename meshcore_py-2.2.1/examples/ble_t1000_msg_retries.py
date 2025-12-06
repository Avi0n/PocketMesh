#!/usr/bin/python

import asyncio
from meshcore import MeshCore
from meshcore import BLEConnection

ADDRESS = "T1000" # node ble adress or name
DEST = "993acd42fc779962c68c627829b32b111fa27a67d86b75c17460ff48c3102db4"
MSG = "Hello World"

async def main () :
    mc = await MeshCore.create_ble(ADDRESS, debug=True)
    await mc.commands.send_msg_with_retry(DEST,MSG)

asyncio.run(main())
