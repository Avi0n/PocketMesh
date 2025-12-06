from enum import Enum
import inspect
import logging
from typing import Any, Dict, Optional, Callable, List, Union
import asyncio
from dataclasses import dataclass, field

logger = logging.getLogger("meshcore")


# Public event types for users to subscribe to
class EventType(Enum):
    CONTACTS = "contacts"
    SELF_INFO = "self_info"
    CONTACT_MSG_RECV = "contact_message"
    CHANNEL_MSG_RECV = "channel_message"
    CURRENT_TIME = "time_update"
    NO_MORE_MSGS = "no_more_messages"
    CONTACT_URI = "contact_uri"
    BATTERY = "battery_info"
    DEVICE_INFO = "device_info"
    MSG_SENT = "message_sent"
    NEW_CONTACT = "new_contact"
    NEXT_CONTACT = "next_contact"

    # Push notifications
    ADVERTISEMENT = "advertisement"
    PATH_UPDATE = "path_update"
    ACK = "acknowledgement"
    MESSAGES_WAITING = "messages_waiting"
    RAW_DATA = "raw_data"
    LOGIN_SUCCESS = "login_success"
    LOGIN_FAILED = "login_failed"
    STATUS_RESPONSE = "status_response"
    LOG_DATA = "log_data"
    TRACE_DATA = "trace_data"
    RX_LOG_DATA = "rx_log_data"
    TELEMETRY_RESPONSE = "telemetry_response"
    BINARY_RESPONSE = "binary_response"
    MMA_RESPONSE = "mma_response"
    ACL_RESPONSE = "acl_response"
    CUSTOM_VARS = "custom_vars"
    CHANNEL_INFO = "channel_info"
    PATH_RESPONSE = "path_response"
    PRIVATE_KEY = "private_key"
    DISABLED = "disabled"
    CONTROL_DATA = "control_data"
    DISCOVER_RESPONSE = "discover_response"
    NEIGHBOURS_RESPONSE = "neighbours_response"

    # Command response types
    OK = "command_ok"
    ERROR = "command_error"

    # Connection events
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"


@dataclass
class Event:
    type: EventType
    payload: Any
    attributes: Dict[str, Any] = field(default_factory=dict)

    def __init__(
        self,
        type: EventType,
        payload: Any,
        attributes: Optional[Dict[str, Any]] = None,
        **kwargs,
    ):
        """
        Initialize an Event

        Args:
            type: The event type
            payload: The event payload
            attributes: Dictionary of event attributes for filtering
            **kwargs: Additional attributes to add to the attributes dictionary
        """
        self.type = type
        self.payload = payload
        self.attributes = attributes or {}

        # Add any keyword arguments to the attributes dictionary
        if kwargs:
            self.attributes.update(kwargs)

    def clone(self):
        """
        Create a copy of the event.

        Returns:
            A new Event object with the same type, payload, and attributes.
        """
        copied_payload = (
            self.payload.copy() if isinstance(self.payload, dict) else self.payload
        )
        return Event(self.type, copied_payload, self.attributes.copy())


class Subscription:
    def __init__(self, dispatcher, event_type, callback, attribute_filters=None):
        self.dispatcher = dispatcher
        self.event_type = event_type
        self.callback = callback
        self.attribute_filters = attribute_filters or {}

    def unsubscribe(self):
        self.dispatcher._remove_subscription(self)


class EventDispatcher:
    def __init__(self):
        self.queue: asyncio.Queue[Event] = asyncio.Queue()
        self.subscriptions: List[Subscription] = []
        self.running = False
        self._task = None

    def subscribe(
        self,
        event_type: Union[EventType, None],
        callback: Callable[[Event], Union[None, asyncio.Future]],
        attribute_filters: Optional[Dict[str, Any]] = None,
    ) -> Subscription:
        """
        Subscribe to events with optional attribute filtering.

        Parameters:
        -----------
        event_type : EventType or None
            The type of event to subscribe to, or None to subscribe to all events.
        callback : Callable
            Function to call when a matching event is received.
        attribute_filters : Dict[str, Any], optional
            Dictionary of attribute key-value pairs that must match for the event to trigger the callback.

        Returns:
        --------
        Subscription object that can be used to unsubscribe.
        """
        subscription = Subscription(self, event_type, callback, attribute_filters)
        self.subscriptions.append(subscription)
        return subscription

    def _remove_subscription(self, subscription: Subscription):
        if subscription in self.subscriptions:
            self.subscriptions.remove(subscription)

    async def dispatch(self, event: Event):
        await self.queue.put(event)

    async def _process_events(self):
        while self.running:
            event = await self.queue.get()
            logger.debug(
                f"Dispatching event: {event.type}, {event.payload}, {event.attributes}"
            )

            for subscription in self.subscriptions.copy():
                # Check if event type matches
                if (
                    subscription.event_type is None
                    or subscription.event_type == event.type
                ):
                    # Check if all attribute filters match
                    if (
                        subscription.attribute_filters
                        and subscription.attribute_filters != {}
                    ):
                        # Skip if any filter doesn't match the corresponding event attribute
                        if not all(
                            event.attributes.get(key) == value
                            for key, value in subscription.attribute_filters.items()
                        ):
                            continue
                    
                    # Fire the call back asychronously
                    asyncio.create_task(self._execute_callback(subscription.callback, event.clone()))
                        
            self.queue.task_done()

    async def _execute_callback(self, callback, event):
        """Execute a callback with proper error handling"""
        try:
            if asyncio.iscoroutinefunction(callback):
                await callback(event)
            else:
                result = callback(event)
                if inspect.iscoroutine(result):
                    await result
        except Exception as e:
            logger.error(f"Error in event handler for {event.type}: {e}", exc_info=True)

    async def start(self):
        if not self.running:
            self.running = True
            self._task = asyncio.create_task(self._process_events())

    async def stop(self):
        if self.running:
            self.running = False
            if self._task:
                await self.queue.join()
                self._task.cancel()
                try:
                    await self._task
                except asyncio.CancelledError:
                    pass
                self._task = None

    async def wait_for_event(
        self,
        event_type: EventType,
        attribute_filters: Optional[Dict[str, Any]] = None,
        timeout: float | None = None,
    ) -> Optional[Event]:
        """
        Wait for an event of the specified type that matches all attribute filters.

        Parameters:
        -----------
        event_type : EventType
            The type of event to wait for.
        attribute_filters : Dict[str, Any], optional
            Dictionary of attribute key-value pairs that must match for the event to be returned.
        timeout : float | None, optional
            Maximum time to wait for the event, in seconds.

        Returns:
        --------
        The matched event, or None if timeout occurred before a matching event.
        """
        future = asyncio.Future()

        def event_handler(event: Event):
            if not future.done():
                future.set_result(event)

        subscription = self.subscribe(event_type, event_handler, attribute_filters)

        try:
            return await asyncio.wait_for(future, timeout)
        except asyncio.TimeoutError:
            return None
        finally:
            subscription.unsubscribe()
