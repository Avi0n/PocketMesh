#!/usr/bin/python

import asyncio
from meshcore import MeshCore
from meshcore import BLEConnection

ADDRESS = "t1000" # node ble adress or name
DEST = "mchome"
MSG = "Hello World"

async def main () :
    con  = BLEConnection(ADDRESS)
    await con.connect()
    mc = MeshCore(con)
    await mc.connect()

    await mc.ensure_contacts()
    contact = mc.get_contact_by_name(DEST)
    if contact is None:
        print(f"Contact '{DEST}' not found in contacts.")
        return
    await mc.commands.send_msg(contact,MSG)

asyncio.run(main())
