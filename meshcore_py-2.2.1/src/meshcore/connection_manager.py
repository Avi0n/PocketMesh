"""
Connection manager that orchestrates reconnection logic for any connection type.
"""

import asyncio
import logging
from typing import Optional, Any, Callable, Protocol
from .events import Event, EventType

logger = logging.getLogger("meshcore")


class ConnectionProtocol(Protocol):
    """Protocol defining the interface that connection classes must implement."""

    async def connect(self) -> Optional[Any]:
        """Connect and return connection info, or None if failed."""
        ...

    async def disconnect(self):
        """Disconnect from the device/server."""
        ...

    async def send(self, data):
        """Send data through the connection."""
        ...

    def set_reader(self, reader):
        """Set the message reader."""
        ...


class ConnectionManager:
    """Manages connection lifecycle with auto-reconnect and event emission."""

    def __init__(
        self,
        connection: ConnectionProtocol,
        event_dispatcher=None,
        auto_reconnect: bool = False,
        max_reconnect_attempts: int = 3,
    ):
        self.connection = connection
        self.event_dispatcher = event_dispatcher
        self.auto_reconnect = auto_reconnect
        self.max_reconnect_attempts = max_reconnect_attempts

        self._reconnect_attempts = 0
        self._is_connected = False
        self._reconnect_task = None
        self._disconnect_callback: Optional[Callable] = None

    def set_disconnect_callback(self, callback: Callable):
        """Set a callback to be called when disconnection is detected."""
        self._disconnect_callback = callback

    async def connect(self) -> Optional[Any]:
        """Connect with event handling and state management."""
        result = await self.connection.connect()

        if result is not None:
            self._is_connected = True
            self._reconnect_attempts = 0
            await self._emit_event(EventType.CONNECTED, {"connection_info": result})
            logger.debug(f"Connected successfully: {result}")
        else:
            logger.debug("Connection failed")

        return result

    async def disconnect(self):
        """Disconnect with proper cleanup."""
        if self._reconnect_task:
            self._reconnect_task.cancel()
            try:
                await self._reconnect_task
            except asyncio.CancelledError:
                pass
            self._reconnect_task = None

        if self._is_connected:
            await self.connection.disconnect()
            self._is_connected = False
            await self._emit_event(
                EventType.DISCONNECTED, {"reason": "manual_disconnect"}
            )

    async def handle_disconnect(self, reason: str = "unknown"):
        """Handle unexpected disconnections with optional auto-reconnect."""
        if not self._is_connected:
            return

        self._is_connected = False
        logger.debug(f"Connection lost: {reason}")

        if (
            self.auto_reconnect
            and self._reconnect_attempts < self.max_reconnect_attempts
        ):
            self._reconnect_task = asyncio.create_task(self._attempt_reconnect())
        else:
            await self._emit_event(
                EventType.DISCONNECTED,
                {
                    "reason": reason,
                    "reconnect_failed": self._reconnect_attempts
                    >= self.max_reconnect_attempts,
                },
            )

    async def _attempt_reconnect(self):
        """Attempt to reconnect with flat delay."""
        logger.debug(
            f"Attempting reconnection ({self._reconnect_attempts + 1}/{self.max_reconnect_attempts})"
        )
        self._reconnect_attempts += 1

        # Flat 1 second delay for all attempts
        await asyncio.sleep(1)

        try:
            result = await self.connection.connect()
            if result is not None:
                self._is_connected = True
                self._reconnect_attempts = 0
                await self._emit_event(
                    EventType.CONNECTED,
                    {"connection_info": result, "reconnected": True},
                )
                logger.debug("Reconnected successfully")
            else:
                # Reconnection failed, try again if we haven't exceeded max attempts
                if self._reconnect_attempts < self.max_reconnect_attempts:
                    self._reconnect_task = asyncio.create_task(
                        self._attempt_reconnect()
                    )
                else:
                    await self._emit_event(
                        EventType.DISCONNECTED,
                        {"reason": "reconnect_failed", "max_attempts_exceeded": True},
                    )
        except Exception as e:
            logger.debug(f"Reconnection attempt failed: {e}")
            if self._reconnect_attempts < self.max_reconnect_attempts:
                self._reconnect_task = asyncio.create_task(self._attempt_reconnect())
            else:
                await self._emit_event(
                    EventType.DISCONNECTED,
                    {"reason": f"reconnect_error: {e}", "max_attempts_exceeded": True},
                )

    async def _emit_event(self, event_type: EventType, payload: dict):
        """Emit connection events if dispatcher is available."""
        if self.event_dispatcher:
            event = Event(event_type, payload)
            await self.event_dispatcher.dispatch(event)

    @property
    def is_connected(self) -> bool:
        """Check if the connection is active."""
        return self._is_connected

    async def send(self, data):
        """Send data through the managed connection."""
        return await self.connection.send(data)

    def set_reader(self, reader):
        """Set the message reader on the underlying connection."""
        self.connection.set_reader(reader)
