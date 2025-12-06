import logging
import random
from typing import Optional, Union
from hashlib import sha256

from ..events import Event, EventType
from ..packets import PacketType
from .base import CommandHandlerBase, DestinationType, _validate_destination

logger = logging.getLogger("meshcore")


class MessagingCommands(CommandHandlerBase):
    async def get_msg(self, timeout: Optional[float] = None) -> Event:
        logger.debug("Requesting pending messages")
        return await self.send(
            b"\x0a",
            [
                EventType.CONTACT_MSG_RECV,
                EventType.CHANNEL_MSG_RECV,
                EventType.ERROR,
                EventType.NO_MORE_MSGS,
            ],
            timeout,
        )

    async def send_login(self, dst: DestinationType, pwd: str) -> Event:
        dst_bytes = _validate_destination(dst, prefix_length=32)
        logger.debug(f"Sending login request to: {dst_bytes.hex()}")
        data = b"\x1a" + dst_bytes + pwd.encode("utf-8")
        return await self.send(data, [EventType.MSG_SENT, EventType.ERROR])

    async def send_logout(self, dst: DestinationType) -> Event:
        dst_bytes = _validate_destination(dst, prefix_length=32)
        data = b"\x1d" + dst_bytes
        return await self.send(data, [EventType.OK, EventType.ERROR])

    async def send_statusreq(self, dst: DestinationType) -> Event:
        dst_bytes = _validate_destination(dst, prefix_length=32)
        logger.debug(f"Sending status request to: {dst_bytes.hex()}")
        data = b"\x1b" + dst_bytes
        return await self.send(data, [EventType.MSG_SENT, EventType.ERROR])

    async def send_cmd(
        self, dst: DestinationType, cmd: str, timestamp: Optional[int] = None
    ) -> Event:
        dst_bytes = _validate_destination(dst)
        logger.debug(f"Sending command to {dst_bytes.hex()}: {cmd}")

        if timestamp is None:
            import time

            timestamp = int(time.time())

        data = (
            b"\x02\x01\x00"
            + timestamp.to_bytes(4, "little")
            + dst_bytes
            + cmd.encode("utf-8")
        )
        return await self.send(data, [EventType.MSG_SENT, EventType.ERROR])

    async def send_msg(
        self, dst: DestinationType, msg: str, timestamp: Optional[int] = None,
        attempt=0
    ) -> Event:
        dst_bytes = _validate_destination(dst)
        logger.debug(f"Sending message to {dst_bytes.hex()}: {msg}")

        if timestamp is None:
            import time

            timestamp = int(time.time())

        data = (
            b"\x02\x00"
            + attempt.to_bytes(1, "little")
            + timestamp.to_bytes(4, "little")
            + dst_bytes
            + msg.encode("utf-8")
        )
        return await self.send(data, [EventType.MSG_SENT, EventType.ERROR])

    async def send_msg_with_retry (
        self, dst: DestinationType, msg: str, timestamp: Optional[int] = None,
        max_attempts=3, max_flood_attempts=2, flood_after=2, timeout=0, min_timeout=0
    ) -> Event:
        
        dst_bytes = _validate_destination(dst)
        contact = self._get_contact_by_prefix(dst_bytes.hex())

        attempts = 0
        flood_attempts = 0
        if not contact is None :
            flood = contact["out_path_len"] == -1
        else:
            flood = False 
        res = None
        while attempts < max_attempts and res is None \
                    and (not flood or flood_attempts < max_flood_attempts):
            if attempts == flood_after : # change path to flood
                logger.info("Resetting path")
                rp_res = await self.reset_path(dst)
                if rp_res.type == EventType.ERROR:
                    logger.error(f"Couldn't reset path {rp_res} continuing ...")
                else:
                    flood = True
                    if not contact is None:
                        contact["out_path"] = ""
                        contact["out_path_len"] = -1

            if attempts > 0:
                logger.info(f"Retry sending msg: {attempts + 1}")
                
            result = await self.send_msg(dst, msg, timestamp, attempt=attempts)
            if result.type == EventType.ERROR:
                logger.error(f"⚠️ Failed to send message: {result.payload}")

            exp_ack = result.payload["expected_ack"].hex()
            timeout = result.payload["suggested_timeout"] / 1000 * 1.2 if timeout==0 else timeout
            timeout = timeout if timeout > min_timeout else min_timeout
            res = await self.dispatcher.wait_for_event(EventType.ACK, 
                        attribute_filters={"code": exp_ack}, 
                        timeout=timeout)

            attempts = attempts + 1
            if flood :
                flood_attempts = flood_attempts + 1
    
        return None if res is None else result

    async def send_chan_msg(self, chan, msg, timestamp=None) -> Event:
        logger.debug(f"Sending channel message to channel {chan}: {msg}")

        # Default to current time if timestamp not provided
        if timestamp is None:
            import time

            timestamp = int(time.time()).to_bytes(4, "little")

        data = (
            b"\x03\x00" + chan.to_bytes(1, "little") + timestamp + msg.encode("utf-8")
        )
        return await self.send(data, [EventType.OK, EventType.ERROR])

    async def send_telemetry_req(self, dst: DestinationType) -> Event:
        dst_bytes = _validate_destination(dst, prefix_length=32)
        logger.debug(f"Asking telemetry to {dst_bytes.hex()}")
        data = b"\x27\x00\x00\x00" + dst_bytes
        return await self.send(data, [EventType.MSG_SENT, EventType.ERROR])

    async def send_path_discovery(self, dst: DestinationType) -> Event:
        dst_bytes = _validate_destination(dst, prefix_length=32)
        logger.debug(f"Path discovery request for {dst_bytes.hex()}")
        data = b"\x34\x00" + dst_bytes
        return await self.send(data, [EventType.MSG_SENT, EventType.ERROR])

    async def send_trace(
        self,
        auth_code: int = 0,
        tag: Optional[int] = None,
        flags: int = 0,
        path: Optional[Union[str, bytes, bytearray]] = None,
    ) -> Event:
        """
        Send a trace packet to test routing through specific repeaters

        Args:
            auth_code: 32-bit authentication code (default: 0)
            tag: 32-bit integer to identify this trace (default: random)
            flags: 8-bit flags field (default: 0)
            path: Optional string with comma-separated hex values representing repeater pubkeys (e.g. "23,5f,3a")
                 or a bytes/bytearray object with the raw path data

        Returns:
            Event object with sent status, tag, and estimated timeout in milliseconds
        """
        # Generate random tag if not provided
        if tag is None:
            tag = random.randint(1, 0xFFFFFFFF)
        if auth_code is None:
            auth_code = random.randint(1, 0xFFFFFFFF)

        logger.debug(
            f"Sending trace: tag={tag}, auth={auth_code}, flags={flags}, path={path}"
        )

        # Prepare the command packet: CMD(1) + tag(4) + auth_code(4) + flags(1) + [path]
        cmd_data = bytearray([36])  # CMD_SEND_TRACE_PATH
        cmd_data.extend(tag.to_bytes(4, "little"))
        cmd_data.extend(auth_code.to_bytes(4, "little"))
        cmd_data.append(flags)

        # Process path if provided
        if path:
            if isinstance(path, str):
                # Convert comma-separated hex values to bytes
                try:
                    path_bytes = bytearray()
                    for hex_val in path.split(","):
                        hex_val = hex_val.strip()
                        path_bytes.append(int(hex_val, 16))
                    cmd_data.extend(path_bytes)
                except ValueError as e:
                    logger.error(f"Invalid path format: {e}")
                    return Event(EventType.ERROR, {"reason": "invalid_path_format"})
            elif isinstance(path, (bytes, bytearray)):
                cmd_data.extend(path)
            else:
                logger.error(f"Unsupported path type: {type(path)}")
                return Event(EventType.ERROR, {"reason": "unsupported_path_type"})

        return await self.send(cmd_data, [EventType.MSG_SENT, EventType.ERROR])

    async def set_flood_scope(self, scope):
        if scope.startswith("#"): # an hash
            logger.debug(f"Setting scope from hash {scope}")
            scope_key = sha256(scope.encode("utf-8")).digest()[0:16]
        elif scope == "0" or scope == "None" or scope == "*" or scope == "": # disable
            scope_key = b"\0"*16
        else: # assume the key has been sent directly
            scope_key = scope.encode("utf-8")

        logger.debug(f"Setting scope to {scope_key.hex()}")

        cmd_data = bytearray([PacketType.SET_FLOOD_SCOPE.value])
        cmd_data.extend(b"\0")
        cmd_data.extend(scope_key)

        return await self.send(cmd_data, [EventType.OK, EventType.ERROR])
