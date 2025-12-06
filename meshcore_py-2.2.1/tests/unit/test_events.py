import pytest
import asyncio
from unittest.mock import MagicMock
from meshcore.events import EventDispatcher, EventType, Event

pytestmark = pytest.mark.asyncio


@pytest.fixture
def dispatcher():
    return EventDispatcher()


async def test_subscribe_with_attribute_filter(dispatcher):
    callback = MagicMock()

    # Subscribe with attribute filters
    dispatcher.subscribe(
        EventType.MSG_SENT,
        callback,
        attribute_filters={"type": 1, "expected_ack": "1234"},
    )

    # Start the dispatcher
    await dispatcher.start()

    try:
        # Dispatch event that should NOT match (wrong type)
        await dispatcher.dispatch(
            Event(
                EventType.MSG_SENT,
                {"some": "data"},
                {"type": 2, "expected_ack": "1234"},
            )
        )
        await asyncio.sleep(0.1)  # Allow processing

        # Callback should NOT have been called
        assert callback.call_count == 0

        # Dispatch event that should match all filters
        await dispatcher.dispatch(
            Event(
                EventType.MSG_SENT,
                {"some": "data"},
                {"type": 1, "expected_ack": "1234"},
            )
        )
        await asyncio.sleep(0.1)  # Allow processing

        # Callback should have been called once
        assert callback.call_count == 1

    finally:
        await dispatcher.stop()


async def test_wait_for_event_with_attribute_filter(dispatcher):
    await dispatcher.start()

    try:
        future_event = asyncio.create_task(
            dispatcher.wait_for_event(
                EventType.ACK, attribute_filters={"code": "1234"}, timeout=3.0
            )
        )

        await asyncio.sleep(0.1)

        await dispatcher.dispatch(
            Event(EventType.ACK, {"some": "data"}, {"code": "5678"})
        )

        await asyncio.sleep(0.1)

        await dispatcher.dispatch(
            Event(EventType.ACK, {"ack": "data"}, {"code": "1234"})
        )

        result = await asyncio.wait_for(future_event, 3.0)

        assert result is not None
        assert result.type == EventType.ACK
        assert result.attributes["code"] == "1234"
        assert result.payload == {"ack": "data"}

    finally:
        await dispatcher.stop()


async def test_wait_for_event_timeout_with_filter(dispatcher):
    await dispatcher.start()

    try:
        # Wait for an event that won't arrive
        result = await dispatcher.wait_for_event(
            EventType.ACK, attribute_filters={"code": "1234"}, timeout=0.1
        )

        # Should get None due to timeout
        assert result is None

    finally:
        await dispatcher.stop()


async def test_event_init_with_kwargs():
    # Test creating an event with keyword attributes
    event = Event(EventType.ACK, {"data": "value"}, code="1234", status="ok")

    assert event.type == EventType.ACK
    assert event.payload == {"data": "value"}
    assert event.attributes == {"code": "1234", "status": "ok"}


async def test_channel_info_event():
    # Test CHANNEL_INFO event type
    channel_payload = {
        "channel_idx": 3,
        "channel_name": "TestChannel",
        "channel_secret": b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10",
    }

    event = Event(EventType.CHANNEL_INFO, channel_payload)

    assert event.type == EventType.CHANNEL_INFO
    assert event.payload["channel_idx"] == 3
    assert event.payload["channel_name"] == "TestChannel"
    assert len(event.payload["channel_secret"]) == 16
