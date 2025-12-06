import logging
import random

from .base import CommandHandlerBase
from ..events import EventType, Event
from ..packets import ControlType, PacketType

logger = logging.getLogger("meshcore")

class ControlDataCommandHandler(CommandHandlerBase):
    """Helper functions to handle binary requests through binary commands"""

    async def send_control_data (self, control_type: int, payload: bytes) -> Event:
        data = bytearray([PacketType.SEND_CONTROL_DATA.value]) 
        data.extend(control_type.to_bytes(1, "little", signed = False)) 
        data.extend(payload)

        result = await self.send(data, [EventType.OK, EventType.ERROR])
        return result

    async def send_node_discover_req (
        self,
        filter: int,
        prefix_only: bool=True,
        tag: int=None,
        since: int=None
    ) -> Event:

        if tag is None:
            tag = random.randint(1, 0xFFFFFFFF)

        data = bytearray()
        data.extend(filter.to_bytes(1, "little", signed=False))
        data.extend(tag.to_bytes(4, "little"))
        if not since is None:
            data.extend(since.to_bytes(4, "little", signed=False))

        logger.debug(f"sending node discover req {data.hex()}")

        flags = 0
        flags = flags | 1 if prefix_only else flags

        res = await self.send_control_data(
            ControlType.NODE_DISCOVER_REQ.value|flags, data)

        if res is None:
            return None
        else:
            res.payload["tag"] = tag
            return res
