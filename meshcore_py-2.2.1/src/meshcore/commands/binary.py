import asyncio
import logging
import random

from .base import CommandHandlerBase
from ..events import EventType
from ..packets import BinaryReqType

logger = logging.getLogger("meshcore")


class BinaryCommandHandler(CommandHandlerBase):
    """Helper functions to handle binary requests through binary commands"""

    async def req_status(self, contact, timeout=0, min_timeout=0):
        logger.error("*** please consider using req_status_sync instead of req_status") 
        return await self.req_status_sync(contact, timeout, min_timeout)

    async def req_status_sync(self, contact, timeout=0, min_timeout=0):
        res = await self.send_binary_req(
            contact,
            BinaryReqType.STATUS,
            timeout=timeout,
            min_timeout=min_timeout
        )
        if res.type == EventType.ERROR:
            return None
            
        exp_tag = res.payload["expected_ack"].hex()
        timeout = res.payload["suggested_timeout"] / 800 if timeout == 0 else timeout
        timeout = timeout if min_timeout < timeout else min_timeout
        
        if self.dispatcher is None:
            return None
            
        status_event = await self.dispatcher.wait_for_event(
            EventType.STATUS_RESPONSE,
            attribute_filters={"tag": exp_tag},
            timeout=timeout,
        )
        
        return status_event.payload if status_event else None

    async def req_telemetry(self, contact, timeout=0, min_timeout=0):
        logger.error("*** please consider using req_telemetry_sync instead of req_telemetry") 
        return await self.req_telemetry_sync(contact, timeout, min_timeout)

    async def req_telemetry_sync(self, contact, timeout=0, min_timeout=0):
        res = await self.send_binary_req(
            contact,
            BinaryReqType.TELEMETRY,
            timeout=timeout,
            min_timeout=min_timeout
        )
        if res.type == EventType.ERROR:
            return None
            
        timeout = res.payload["suggested_timeout"] / 800 if timeout == 0 else timeout
        timeout = timeout if min_timeout < timeout else min_timeout

        if self.dispatcher is None:
            return None
            
        # Listen for TELEMETRY_RESPONSE event
        telem_event = await self.dispatcher.wait_for_event(
            EventType.TELEMETRY_RESPONSE,
            attribute_filters={"tag": res.payload["expected_ack"].hex()},
            timeout=timeout,
        )
        
        return telem_event.payload["lpp"] if telem_event else None

    async def req_mma(self, contact, timeout=0, min_timeout=0):
        logger.error("*** please consider using req_mma_sync instead of req_mma") 
        return await self.req_mma_sync(contact, start, end, timeout,min_timeout)

    async def req_mma_sync(self, contact, start, end, timeout=0,min_timeout=0):
        req = (
            start.to_bytes(4, "little", signed=False)
            + end.to_bytes(4, "little", signed=False)
            + b"\0\0"
        )
        res = await self.send_binary_req(
            contact,
            BinaryReqType.MMA,
            data=req,
            timeout=timeout
        )
        if res.type == EventType.ERROR:
            return None
            
        timeout = res.payload["suggested_timeout"] / 800 if timeout == 0 else timeout
        timeout = timeout if min_timeout < timeout else min_timeout
        
        if self.dispatcher is None:
            return None
            
        # Listen for MMA_RESPONSE
        mma_event = await self.dispatcher.wait_for_event(
            EventType.MMA_RESPONSE,
            attribute_filters={"tag": res.payload["expected_ack"].hex()},
            timeout=timeout,
        )
        
        return mma_event.payload["mma_data"] if mma_event else None

    async def req_acl(self, contact, timeout=0, min_timeout=0):
        logger.error("*** please consider using req_acl_sync instead of req_acl") 
        return await self.req_acl_sync(contact, timeout, min_timeout)

    async def req_acl_sync(self, contact, timeout=0, min_timeout=0):
        req = b"\0\0"
        res = await self.send_binary_req(
            contact,
            BinaryReqType.ACL,
            data=req,
            timeout=timeout
        )
        if res.type == EventType.ERROR:
            return None
            
        timeout = res.payload["suggested_timeout"] / 800 if timeout == 0 else timeout
        timeout = timeout if timeout > min_timeout else min_timeout
        
        if self.dispatcher is None:
            return None
            
        # Listen for ACL_RESPONSE event with matching tag
        acl_event = await self.dispatcher.wait_for_event(
            EventType.ACL_RESPONSE,
            attribute_filters={"tag": res.payload["expected_ack"].hex()},
            timeout=timeout,
        )
        
        return acl_event.payload["acl_data"] if acl_event else None

    async def req_neighbours_async(self,
        contact,
        count=255,
        offset=0,
        order_by=0,
        pubkey_prefix_length=4,
        timeout=0,
        min_timeout=0
    ):
        req = (b"\x00" # version : 0
            + count.to_bytes(1, "little", signed=False)
            + offset.to_bytes(2, "little", signed=False)
            + order_by.to_bytes(1, "little", signed=False)
            + pubkey_prefix_length.to_bytes(1, "little", signed=False)
            + random.randint(1, 0xFFFFFFFF).to_bytes(4, "little", signed=False)
        )

        logger.debug(f"Sending binary neighbours req, count: {count}, offset: {offset} {req.hex()}")

        return await self.send_binary_req (
            contact,
            BinaryReqType.NEIGHBOURS,
            data=req,
            timeout=timeout,
            context={"pubkey_prefix_length": pubkey_prefix_length}
        )

    async def req_neighbours_sync(self,
        contact,
        count=255,
        offset=0,
        order_by=0,
        pubkey_prefix_length=4,
        timeout=0,
        min_timeout=0
    ):

        res = await self.req_neighbours_async(contact,
                count=count,
                offset=offset,
                order_by=order_by,
                pubkey_prefix_length=pubkey_prefix_length,
                timeout=timeout,
                min_timeout=min_timeout)

        if res is None or res.type == EventType.ERROR:
            return None

        timeout = res.payload["suggested_timeout"] / 800 if timeout == 0 else timeout
        timeout = timeout if min_timeout < timeout else min_timeout

        if self.dispatcher is None:
            return None

        # Listen for NEIGHBOUR_RESPONSE
        neighbours_event = await self.dispatcher.wait_for_event(
            EventType.NEIGHBOURS_RESPONSE,
            attribute_filters={"tag": res.payload["expected_ack"].hex()},
            timeout=timeout,
        )

        return neighbours_event.payload if neighbours_event else None

    # do several queries if not all neighbours have been obtained
    async def fetch_all_neighbours(self,
        contact,
        order_by=0,
        pubkey_prefix_length=4,
        timeout=0,
        min_timeout=0
    ):

        # Initial request
        res = await self.req_neighbours_sync(contact,
            count=255,
            offset=0,
            order_by=order_by,
            pubkey_prefix_length=pubkey_prefix_length,
            timeout=timeout,
            min_timeout=min_timeout)

        if res is None:
            return None

        neighbours_count = res["neighbours_count"] # total neighbours 
        results_count = res["results_count"]       # obtained neighbours

        del res["tag"]

        while results_count < neighbours_count:
            #await asyncio.sleep(2) # wait 2s before next fetch
            next_res = await self.req_neighbours_sync(contact,
                count=255,
                offset=results_count,
                order_by=order_by,
                pubkey_prefix_length=pubkey_prefix_length,
                timeout=timeout,
                min_timeout=min_timeout+5) # requests are close, so let's have some more timeout

            if next_res is None :
                return res # caller should check it has everything

            results_count = results_count + next_res["results_count"]

            res["results_count"] = results_count
            res["neighbours"] += next_res["neighbours"]

        return res
