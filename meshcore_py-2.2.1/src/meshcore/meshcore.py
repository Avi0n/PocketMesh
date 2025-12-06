import asyncio
import logging
from typing import Any, Callable, Coroutine, Dict, Optional, Union

from .events import Event, EventDispatcher, EventType, Subscription
from .reader import MessageReader
from .commands import CommandHandler
from .connection_manager import ConnectionManager
from .ble_cx import BLEConnection
from .tcp_cx import TCPConnection
from .serial_cx import SerialConnection

# Setup default logger
logger = logging.getLogger("meshcore")


class MeshCore:
    """
    Interface to a MeshCore device
    """

    def __init__(
        self,
        cx: Union[BLEConnection, TCPConnection, SerialConnection],
        debug: bool = False,
        only_error: bool = False,
        default_timeout: Optional[float] = None,
        auto_reconnect: bool = False,
        max_reconnect_attempts: int = 3,
    ):
        # Wrap connection with ConnectionManager
        self.dispatcher = EventDispatcher()
        self.connection_manager = ConnectionManager(
            cx, self.dispatcher, auto_reconnect, max_reconnect_attempts
        )
        self.cx = self.connection_manager  # For backward compatibility

        self._reader = MessageReader(self.dispatcher)
        self.commands = CommandHandler(default_timeout=default_timeout)
        self.commands.set_contact_getter_by_prefix(self.get_contact_by_key_prefix)

        # Set up logger
        if debug:
            logger.setLevel(logging.DEBUG)
        elif only_error:
            logger.setLevel(logging.ERROR)
        else:
            logger.setLevel(logging.INFO)

        # Set up connections
        self.commands.set_connection(self.connection_manager)

        # Set the dispatcher in the command handler
        self.commands.set_dispatcher(self.dispatcher)
        self.commands.set_reader(self._reader)

        # Initialize state (private)
        self._contacts = {}
        self._contacts_dirty = True
        self._pending_contacts = {}
        self._self_info = {}
        self._time = 0
        self._lastmod = 0
        self._auto_update_contacts = False

        # Set up event subscriptions to track data
        self._setup_data_tracking()

        self.connection_manager.set_reader(self._reader)

        # Set up disconnect callback
        cx.set_disconnect_callback(self.connection_manager.handle_disconnect)

    @classmethod
    async def create_tcp(
        cls,
        host: str,
        port: int,
        debug: bool = False,
        only_error: bool = False,
        default_timeout=None,
        auto_reconnect: bool = False,
        max_reconnect_attempts: int = 3,
    ) -> "MeshCore":
        """Create and connect a MeshCore instance using TCP connection"""
        connection = TCPConnection(host, port)

        mc = cls(
            connection,
            debug=debug,
            only_error=only_error,
            default_timeout=default_timeout,
            auto_reconnect=auto_reconnect,
            max_reconnect_attempts=max_reconnect_attempts,
        )
        await mc.connect()
        return mc

    @classmethod
    async def create_serial(
        cls,
        port: str,
        baudrate: int = 115200,
        debug: bool = False,
        only_error: bool = False,
        default_timeout=None,
        auto_reconnect: bool = False,
        max_reconnect_attempts: int = 3,
        cx_dly: float = 0.1,
    ) -> "MeshCore":
        """Create and connect a MeshCore instance using serial connection"""
        connection = SerialConnection(port, baudrate, cx_dly=cx_dly)

        mc = cls(
            connection,
            debug=debug,
            only_error=only_error,
            default_timeout=default_timeout,
            auto_reconnect=auto_reconnect,
            max_reconnect_attempts=max_reconnect_attempts,
        )
        await mc.connect()
        return mc

    @classmethod
    async def create_ble(
        cls,
        address: Optional[str] = None,
        client=None,
        device=None,
        pin: Optional[str] = None,
        debug: bool = False,
        only_error: bool = False,
        default_timeout=None,
        auto_reconnect: bool = False,
        max_reconnect_attempts: int = 3,
    ) -> "MeshCore":

        """
        Create and connect a MeshCore instance using BLE connection.

        Args:
            address (str, optional): The Bluetooth address of the device.
            client (BleakClient, optional): An existing BleakClient instance to use.
                                            If provided, 'address' is ignored for connection
                                            but can be used for identification.
            device (BLEDevice, optional): A BLEDevice instance to use for connection.
            pin (str, optional): PIN for BLE pairing authentication.
        """
        connection = BLEConnection(address=address, client=client, device=device, pin=pin)

        mc = cls(
            connection,
            debug=debug,
            only_error=only_error,
            default_timeout=default_timeout,
            auto_reconnect=auto_reconnect,
            max_reconnect_attempts=max_reconnect_attempts,
        )

        await mc.connect()
        return mc

    async def connect(self):
        await self.dispatcher.start()
        result = await self.connection_manager.connect()
        if result is None:
            await self.dispatcher.stop()
            raise ConnectionError("Failed to connect to device")
        return await self.commands.send_appstart()

    async def disconnect(self):
        """Disconnect from the device and clean up resources."""
        # First stop the dispatcher to prevent any new events
        await self.dispatcher.stop()

        # Stop auto message fetching if it's running
        if hasattr(self, "_auto_fetch_subscription") and self._auto_fetch_subscription:
            await self.stop_auto_message_fetching()

        # Disconnect the connection object
        await self.connection_manager.disconnect()

    def stop(self):
        """Synchronously stop the event dispatcher task"""
        if self.dispatcher._task and not self.dispatcher._task.done():
            self.dispatcher.running = False
            self.dispatcher._task.cancel()

    def subscribe(
        self,
        event_type: Union[EventType, None],
        callback: Callable[[Event], Coroutine[Any, Any, None]],
        attribute_filters: Optional[Dict[str, Any]] = None,
    ) -> Subscription:
        """
        Subscribe to events using EventType enum with optional attribute filtering

        Args:
            event_type: Type of event to subscribe to, from EventType enum
            callback: Async function to call when event occurs
            attribute_filters: Dictionary of attribute key-value pairs that must match for the event to trigger the callback

        Returns:
            Subscription object that can be used to unsubscribe

        Example:
            # Subscribe to ACK events where the 'code' attribute has a specific value
            mc.subscribe(
                EventType.ACK,
                my_callback_function,
                attribute_filters={'code': 'SUCCESS'}
            )
        """
        return self.dispatcher.subscribe(event_type, callback, attribute_filters)

    def unsubscribe(self, subscription: Subscription) -> None:
        """
        Unsubscribe from events using a subscription object

        Args:
            subscription: Subscription object returned from subscribe()
        """
        if subscription:
            subscription.unsubscribe()

    async def wait_for_event(
        self,
        event_type: EventType,
        attribute_filters: Optional[Dict[str, Any]] = None,
        timeout: Optional[float] = None,
    ) -> Optional[Event]:
        """
        Wait for an event using EventType enum with optional attribute filtering

        Args:
            event_type: Type of event to wait for, from EventType enum
            attribute_filters: Dictionary of attribute key-value pairs to match against the event
            timeout: Maximum time to wait in seconds, or None to use default_timeout

        Returns:
            Event object or None if timeout

        Example:
            # Wait for an ACK event where the 'code' attribute has a specific value
            await mc.wait_for_event(
                EventType.ACK,
                attribute_filters={'code': 'SUCCESS'},
                timeout=30.0
            )
        """
        # Use the provided timeout or fall back to default_timeout
        if timeout is None:
            timeout = self.default_timeout

        return await self.dispatcher.wait_for_event(
            event_type, attribute_filters, timeout
        )

    def _setup_data_tracking(self):
        """Set up event subscriptions to track data internally"""

        async def _update_contacts(event):
            # self._contacts.update(event.payload)
            for c in event.payload.values():
                if c["public_key"] in self._contacts:
                    self._contacts[c["public_key"]].update(c)
                else:
                    self._contacts[c["public_key"]] = c
            if "lastmod" in event.attributes:
                self._lastmod = event.attributes["lastmod"]
            self._contacts_dirty = False

        async def _add_pending_contact(event):
            c = event.payload
            self._pending_contacts[c["public_key"]] = c

        async def _contact_change(event):
            self._contacts_dirty = True
            if self._auto_update_contacts:
                await self.ensure_contacts(follow=True)

        async def _update_self_info(event):
            self._self_info = event.payload

        async def _update_time(event):
            self._time = event.payload.get("time", 0)

        # Subscribe to events to update internal state
        self.subscribe(EventType.CONTACTS, _update_contacts)
        self.subscribe(EventType.NEW_CONTACT, _add_pending_contact)
        self.subscribe(EventType.SELF_INFO, _update_self_info)
        self.subscribe(EventType.CURRENT_TIME, _update_time)
        self.subscribe(EventType.ADVERTISEMENT, _contact_change)
        self.subscribe(EventType.PATH_UPDATE, _contact_change)

    # Getter methods for state
    @property
    def contacts(self) -> Dict[str, Any]:
        """Get the current contacts"""
        return self._contacts

    @property
    def contacts_dirty(self) -> bool:
        """Get wether contact list is in sync"""
        return self._contacts_dirty

    @property
    def auto_update_contacts(self) -> bool:
        """Get wether contact list is in sync"""
        return self._auto_update_contacts

    @auto_update_contacts.setter
    def auto_update_contacts(self, value: bool) -> None:
        self._auto_update_contacts = value

    @property
    def self_info(self) -> Dict[str, Any]:
        """Get device self info"""
        return self._self_info

    @property
    def time(self) -> int:
        """Get the current device time"""
        return self._time

    @property
    def is_connected(self) -> bool:
        """Check if the connection is active"""
        return self.connection_manager.is_connected

    @property
    def default_timeout(self) -> float:
        """Get the default timeout for commands"""
        return self.commands.default_timeout

    @default_timeout.setter
    def default_timeout(self, value: float) -> None:
        """Set the default timeout for commands"""
        self.commands.default_timeout = value

    @property
    def pending_contacts(self) -> Dict[str, Any]:
        """Get pending contacts"""
        return self._pending_contacts

    def pop_pending_contact(self, key: str) -> Optional[Dict[str, Any]]:
        return self._pending_contacts.pop(key, None)

    def flush_pending_contacts(self) -> None:  # would be interesting to have a time param
        self._pending_contacts = {}

    def get_contact_by_name(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Find a contact by its name (adv_name field)

        Args:
            name: The name to search for

        Returns:
            Contact dictionary or None if not found
        """
        if not self._contacts:
            return None

        for _, contact in self._contacts.items():
            if contact.get("adv_name", "").lower() == name.lower():
                return contact

        return None

    def get_contact_by_key_prefix(self, prefix: str) -> Optional[Dict[str, Any]]:
        """
        Find a contact by its public key prefix

        Args:
            prefix: The public key prefix to search for (can be a partial prefix)

        Returns:
            Contact dictionary or None if not found
        """
        if not self._contacts or not prefix:
            return None

        # Convert the prefix to lowercase for case-insensitive matching
        prefix = prefix.lower()

        for contact_id, contact in self._contacts.items():
            public_key = contact.get("public_key", "").lower()
            if public_key.startswith(prefix):
                return contact

        return None

    async def start_auto_message_fetching(self) -> Subscription:
        """
        Start automatically fetching messages when messages_waiting events are received.
        This will continuously check for new messages when the device indicates
        messages are waiting.
        """
        self._auto_fetch_task = None
        self._auto_fetch_running = True

        async def _handle_messages_waiting(event):
            # Only start a new fetch task if one isn't already running
            if not self._auto_fetch_task or self._auto_fetch_task.done():
                self._auto_fetch_task = asyncio.create_task(_fetch_messages_loop())

        async def _fetch_messages_loop():
            while self._auto_fetch_running:
                try:
                    # Request the next message
                    result = await self.commands.get_msg()

                    # If we got a NO_MORE_MSGS event or an error, stop fetching
                    if (
                        result.type == EventType.NO_MORE_MSGS
                        or result.type == EventType.ERROR
                    ):
                        logger.debug(
                            "No more messages or error occurred, stopping auto-fetch."
                        )
                        break

                    # Small delay to prevent overwhelming the device
                    await asyncio.sleep(0.1)
                except Exception as e:
                    logger.error(f"Error fetching messages: {e}")
                    break

        # Subscribe to MESSAGES_WAITING events
        self._auto_fetch_subscription = self.subscribe(
            EventType.MESSAGES_WAITING, _handle_messages_waiting
        )

        # Check for any pending messages immediately
        await self.commands.get_msg()

        return self._auto_fetch_subscription

    async def stop_auto_message_fetching(self):
        """
        Stop automatically fetching messages when messages_waiting events are received.
        """
        if hasattr(self, "_auto_fetch_subscription") and self._auto_fetch_subscription:
            self.unsubscribe(self._auto_fetch_subscription)
            self._auto_fetch_subscription = None

        if hasattr(self, "_auto_fetch_running"):
            self._auto_fetch_running = False

        if (
            hasattr(self, "_auto_fetch_task")
            and self._auto_fetch_task
            and not self._auto_fetch_task.done()
        ):
            self._auto_fetch_task.cancel()
            try:
                await self._auto_fetch_task  # type: ignore
            except asyncio.CancelledError:
                pass
            self._auto_fetch_task = None

    async def ensure_contacts(self, follow: bool = False) -> bool:
        """Ensure contacts are fetched"""
        if not self._contacts or (follow and self._contacts_dirty):
            await self.commands.get_contacts(lastmod=self._lastmod)
            return True
        return False
