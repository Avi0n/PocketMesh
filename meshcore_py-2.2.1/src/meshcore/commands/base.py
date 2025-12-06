import asyncio
import logging
import random
from typing import Any, Callable, Coroutine, Dict, List, Optional, Union

from meshcore.packets import BinaryReqType

from ..events import Event, EventDispatcher, EventType
from ..reader import MessageReader

# Define types for destination parameters
DestinationType = Union[bytes, str, Dict[str, Any]]

logger = logging.getLogger("meshcore")


def _validate_destination(dst: DestinationType, prefix_length: int = 6) -> bytes:
    """
    Validates and converts a destination to a bytes object.

    Args:
        dst: The destination, which can be:
            - str: Hex string representation of a public key
            - dict: Contact object with a "public_key" field
        prefix_length: The length of the prefix to use (default: 6 bytes)

    Returns:
        bytes: The destination public key as a bytes object

    Raises:
        ValueError: If dst is invalid or doesn't contain required fields
    """
    if isinstance(dst, bytes):
        # Already bytes, use directly
        return dst[:prefix_length]
    elif isinstance(dst, str):
        # Hex string, convert to bytes
        try:
            return bytes.fromhex(dst)[:prefix_length]
        except ValueError:
            raise ValueError(f"Invalid public key hex string: {dst}")
    elif isinstance(dst, dict):
        # Contact object, extract public_key
        if "public_key" not in dst:
            raise ValueError("Contact object must have a 'public_key' field")
        try:
            return bytes.fromhex(dst["public_key"])[:prefix_length]
        except ValueError:
            raise ValueError(f"Invalid public_key in contact: {dst['public_key']}")
    else:
        raise ValueError(
            f"Destination must be a public key string or contact object, got: {type(dst)}"
        )


class CommandHandlerBase:
    DEFAULT_TIMEOUT = 5.0

    def __init__(self, default_timeout: Optional[float] = None):
        self._sender_func: Optional[Callable[[bytes], Coroutine[Any, Any, None]]] = None
        self._reader: Optional[MessageReader] = None
        self.dispatcher: Optional[EventDispatcher] = None
        self.default_timeout = (
            default_timeout if default_timeout is not None else self.DEFAULT_TIMEOUT
        )

    def set_connection(self, connection: Any) -> None:
        async def sender(data: bytes) -> None:
            await connection.send(data)

        self._sender_func = sender

    def set_reader(self, reader: MessageReader) -> None:
        self._reader = reader

    def set_dispatcher(self, dispatcher: EventDispatcher) -> None:
        self.dispatcher = dispatcher

    def set_contact_getter_by_prefix(self, func: Callable[[str], Optional[Dict[str,Any]]]
        )-> None:
        self._get_contact_by_prefix = func

    async def wait_for_events(
        self,
        expected_events: Optional[Union[EventType, List[EventType]]] = None,
        timeout: Optional[float] = None,
    ) -> Event:
        try:
            # Convert single event to list if needed
            if not isinstance(expected_events, list):
                expected_events = [expected_events]

            logger.debug(f"Waiting for events {expected_events}, timeout={timeout}")

            # Create futures for all expected events
            futures = []
            for event_type in expected_events:
                future = asyncio.create_task(
                    self.dispatcher.wait_for_event(event_type, {}, timeout)
                )
                futures.append(future)

            # Wait for the first event to complete or all to timeout
            done, pending = await asyncio.wait(
                futures, timeout=timeout, return_when=asyncio.FIRST_COMPLETED
            )

            # Cancel all pending futures
            for future in pending:
                future.cancel()

            # Check if any future completed successfully
            for future in done:
                event = await future
                if event:
                    return event

            # Create an error event when no event is received
            return Event(EventType.ERROR, {"reason": "no_event_received"})
        except asyncio.TimeoutError:
            logger.debug(f"Command timed out {data}")
            return Event(EventType.ERROR, {"reason": "timeout"})
        except Exception as e:
            logger.debug(f"Command error: {e}")
            return Event(EventType.ERROR, {"error": str(e)})

        return Event(EventType.ERROR, {})


    async def send(
        self,
        data: bytes,
        expected_events: Optional[Union[EventType, List[EventType]]] = None,
        timeout: Optional[float] = None,
    ) -> Event:
        """
        Send a command and wait for expected event responses.

        Args:
            data: The data to send
            expected_events: EventType or list of EventTypes to wait for
            timeout: Timeout in seconds, or None to use default_timeout

        Returns:
            Event: The full event object that was received in response to the command
        """
        if not self.dispatcher:
            raise RuntimeError("Dispatcher not set, cannot send commands")

        # Use the provided timeout or fall back to default_timeout
        timeout = timeout if timeout is not None else self.default_timeout

        if self._sender_func:
            logger.debug(
                f"Sending raw data: {data.hex() if isinstance(data, bytes) else data}"
            )
            await self._sender_func(data)

        if expected_events:
        # For commands that don't expect events, return a success event
            return await self.wait_for_events(expected_events, timeout)

        return Event(EventType.OK, {})

    # attached at base because its a common method
    async def send_binary_req(self, dst: DestinationType, request_type: BinaryReqType, data: Optional[bytes] = None, context={}, timeout=None, min_timeout=0) -> Event:
        dst_bytes = _validate_destination(dst, prefix_length=32)
        pubkey_prefix = _validate_destination(dst, prefix_length=6)
        logger.debug(f"Binary request to {dst_bytes.hex()}")
        data = b"\x32" + dst_bytes + request_type.value.to_bytes(1, "little", signed=False) + (data if data else b"")

        result = await self.send(data, [EventType.MSG_SENT, EventType.ERROR])
        
        # Register the request with the reader if we have both reader and request_type
        if (result.type == EventType.MSG_SENT and 
            self._reader is not None and 
            request_type is not None):
            
            exp_tag = result.payload["expected_ack"].hex()
            # Use provided timeout or fallback to suggested timeout (with 5s default)
            actual_timeout = timeout if timeout is not None and timeout > 0 else result.payload.get("suggested_timeout", 4000) / 800.0
            actual_timeout = min_timeout if actual_timeout < min_timeout else actual_timeout
            self._reader.register_binary_request(pubkey_prefix.hex(), exp_tag, request_type, actual_timeout, context=context)

        return result
