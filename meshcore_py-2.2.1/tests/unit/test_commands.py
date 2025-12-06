import pytest
import asyncio
from unittest.mock import MagicMock, AsyncMock
from meshcore.commands import CommandHandler
from meshcore.events import EventType, Event

pytestmark = pytest.mark.asyncio


# Fixtures
@pytest.fixture
def mock_connection():
    connection = MagicMock()
    connection.send = AsyncMock()
    return connection


@pytest.fixture
def mock_dispatcher():
    dispatcher = MagicMock()
    dispatcher.wait_for_event = AsyncMock()
    dispatcher.dispatch = AsyncMock()
    return dispatcher


@pytest.fixture
def command_handler(mock_connection, mock_dispatcher):
    handler = CommandHandler()

    async def sender(data):
        await mock_connection.send(data)

    handler._sender_func = sender

    handler.dispatcher = mock_dispatcher
    return handler


# Test helper
def setup_event_response(mock_dispatcher, event_type, payload, attribute_filters=None):
    async def wait_response(requested_type, filters=None, timeout=None):
        if requested_type == event_type:
            if filters and attribute_filters:
                if not all(
                    attribute_filters.get(key) == value
                    for key, value in filters.items()
                ):
                    return None
            return Event(event_type, payload)
        return None

    mock_dispatcher.wait_for_event.side_effect = wait_response


# Basic tests
async def test_send_basic(command_handler, mock_connection):
    result = await command_handler.send(b"test_data")
    mock_connection.send.assert_called_once_with(b"test_data")
    assert result.type == EventType.OK
    assert result.payload == {}


async def test_send_with_event(command_handler, mock_connection, mock_dispatcher):
    expected_payload = {"value": 42}
    setup_event_response(mock_dispatcher, EventType.OK, expected_payload)

    result = await command_handler.send(b"test_command", [EventType.OK])

    mock_connection.send.assert_called_once_with(b"test_command")
    assert result.type == EventType.OK
    assert result.payload == expected_payload


async def test_send_timeout(command_handler, mock_connection, mock_dispatcher):
    mock_dispatcher.wait_for_event.side_effect = asyncio.TimeoutError

    result = await command_handler.send(b"test_command", [EventType.OK], timeout=0.1)
    assert result.type == EventType.ERROR
    assert result.payload == {"reason": "timeout"}


# Destination validation tests
async def test_validate_destination_bytes(command_handler, mock_connection):
    dst = b"123456789012"  # 12 bytes
    await command_handler.send_msg(dst, "test message")

    assert mock_connection.send.call_args[0][0].startswith(b"\x02\x00\x00")
    assert b"123456" in mock_connection.send.call_args[0][0]


async def test_validate_destination_hex_string(command_handler, mock_connection):
    dst = "0123456789abcdef"
    await command_handler.send_msg(dst, "test message")

    assert mock_connection.send.call_args[0][0].startswith(b"\x02\x00\x00")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


async def test_validate_destination_contact_object(command_handler, mock_connection):
    dst = {"public_key": "0123456789abcdef", "adv_name": "Test Contact"}
    await command_handler.send_msg(dst, "test message")

    assert mock_connection.send.call_args[0][0].startswith(b"\x02\x00\x00")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


# Command tests
async def test_send_login(command_handler, mock_connection):
    await command_handler.send_login("0123456789abcdef", "password")

    assert mock_connection.send.call_args[0][0].startswith(b"\x1a")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]
    assert b"password" in mock_connection.send.call_args[0][0]


async def test_send_msg(command_handler, mock_connection):
    await command_handler.send_msg("0123456789abcdef", "hello")

    assert mock_connection.send.call_args[0][0].startswith(b"\x02\x00\x00")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]
    assert b"hello" in mock_connection.send.call_args[0][0]


async def test_send_cmd(command_handler, mock_connection):
    await command_handler.send_cmd("0123456789abcdef", "test_cmd")

    assert mock_connection.send.call_args[0][0].startswith(b"\x02\x01\x00")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]
    assert b"test_cmd" in mock_connection.send.call_args[0][0]


# Device settings tests
async def test_set_name(command_handler, mock_connection):
    await command_handler.set_name("Test Device")

    assert mock_connection.send.call_args[0][0].startswith(b"\x08")
    assert b"Test Device" in mock_connection.send.call_args[0][0]


async def test_set_coords(command_handler, mock_connection):
    await command_handler.set_coords(37.7749, -122.4194)

    assert mock_connection.send.call_args[0][0].startswith(b"\x0e")
    # Could add more detailed assertions for the byte encoding


async def test_send_appstart(command_handler, mock_connection):
    await command_handler.send_appstart()
    assert mock_connection.send.call_args[0][0].startswith(b"\x01\x03")
    assert b"mccli" in mock_connection.send.call_args[0][0]


async def test_send_device_query(command_handler, mock_connection):
    await command_handler.send_device_query()
    assert mock_connection.send.call_args[0][0].startswith(b"\x16\x03")


async def test_send_advert(command_handler, mock_connection):
    # Test without flood
    await command_handler.send_advert(flood=False)
    assert mock_connection.send.call_args[0][0] == b"\x07"

    # Test with flood
    mock_connection.reset_mock()
    await command_handler.send_advert(flood=True)
    assert mock_connection.send.call_args[0][0] == b"\x07\x01"


async def test_reboot(command_handler, mock_connection):
    await command_handler.reboot()
    assert mock_connection.send.call_args[0][0].startswith(b"\x13reboot")


async def test_get_bat(command_handler, mock_connection):
    await command_handler.get_bat()
    assert mock_connection.send.call_args[0][0].startswith(b"\x14")


async def test_get_time(command_handler, mock_connection):
    await command_handler.get_time()
    assert mock_connection.send.call_args[0][0].startswith(b"\x05")


async def test_set_time(command_handler, mock_connection):
    timestamp = 1620000000  # Example timestamp
    await command_handler.set_time(timestamp)
    assert mock_connection.send.call_args[0][0].startswith(b"\x06")


async def test_set_tx_power(command_handler, mock_connection):
    await command_handler.set_tx_power(20)
    assert mock_connection.send.call_args[0][0].startswith(b"\x0c")


async def test_get_contacts(command_handler, mock_connection):
    await command_handler.get_contacts()
    assert mock_connection.send.call_args[0][0].startswith(b"\x04")


async def test_reset_path(command_handler, mock_connection):
    dst = "0123456789abcdef"
    await command_handler.reset_path(dst)
    assert mock_connection.send.call_args[0][0].startswith(b"\x0d")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


async def test_share_contact(command_handler, mock_connection):
    dst = "0123456789abcdef"
    await command_handler.share_contact(dst)
    assert mock_connection.send.call_args[0][0].startswith(b"\x10")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


async def test_export_contact(command_handler, mock_connection):
    # Test exporting all contacts
    await command_handler.export_contact()
    assert mock_connection.send.call_args[0][0] == b"\x11"

    # Test exporting specific contact
    mock_connection.reset_mock()
    dst = "0123456789abcdef"
    await command_handler.export_contact(dst)
    assert mock_connection.send.call_args[0][0].startswith(b"\x11")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


async def test_remove_contact(command_handler, mock_connection):
    dst = "0123456789abcdef"
    await command_handler.remove_contact(dst)
    assert mock_connection.send.call_args[0][0].startswith(b"\x0f")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


async def test_get_msg(command_handler, mock_connection):
    await command_handler.get_msg()
    assert mock_connection.send.call_args[0][0].startswith(b"\x0a")

    # Test with custom timeout
    mock_connection.reset_mock()
    await command_handler.get_msg(timeout=5.0)
    assert mock_connection.send.call_args[0][0].startswith(b"\x0a")


async def test_send_logout(command_handler, mock_connection):
    dst = "0123456789abcdef"
    await command_handler.send_logout(dst)
    assert mock_connection.send.call_args[0][0].startswith(b"\x1d")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


async def test_send_statusreq(command_handler, mock_connection):
    dst = "0123456789abcdef"
    await command_handler.send_statusreq(dst)
    assert mock_connection.send.call_args[0][0].startswith(b"\x1b")
    assert b"\x01\x23\x45\x67\x89\xab" in mock_connection.send.call_args[0][0]


async def test_send_trace(command_handler, mock_connection):
    # Test with minimal parameters
    await command_handler.send_trace()
    first_call = mock_connection.send.call_args[0][0]
    assert first_call.startswith(b"\x24")  # 36 in decimal = 0x24 in hex

    # Test with all parameters
    mock_connection.reset_mock()
    await command_handler.send_trace(
        auth_code=12345, tag=67890, flags=1, path="01,23,45"
    )
    second_call = mock_connection.send.call_args[0][0]
    assert second_call.startswith(b"\x24")


async def test_send_with_multiple_expected_events_returns_first_completed(
    command_handler, mock_connection, mock_dispatcher
):
    # Setup the dispatcher to return an ERROR event
    error_payload = {"reason": "command_failed"}

    async def simulate_error_event(*args, **kwargs):
        # Simulate an ERROR event being returned
        return Event(EventType.ERROR, error_payload)

    # Patch the wait_for_event method to return our simulated event
    mock_dispatcher.wait_for_event.side_effect = simulate_error_event

    # Call send with both OK and ERROR in the expected_events list, with OK first
    result = await command_handler.send(
        b"test_command", [EventType.OK, EventType.ERROR]
    )

    # Verify the command was sent
    mock_connection.send.assert_called_once_with(b"test_command")

    # Verify that even though OK was listed first, the ERROR event was returned
    assert result.type == EventType.ERROR
    assert result.payload == error_payload


# Channel command tests
async def test_get_channel(command_handler, mock_connection):
    await command_handler.get_channel(3)
    assert mock_connection.send.call_args[0][0] == b"\x1f\x03"


async def test_set_channel(command_handler, mock_connection):
    channel_secret = bytes(range(16))  # 16 bytes: 0x00, 0x01, ..., 0x0f
    await command_handler.set_channel(5, "MyChannel", channel_secret)

    expected_data = b"\x20\x05"  # CMD_SET_CHANNEL + channel_idx=5
    expected_data += b"MyChannel" + b"\x00" * (
        32 - len("MyChannel")
    )  # 32-byte padded name
    expected_data += channel_secret  # 16-byte secret

    assert mock_connection.send.call_args[0][0] == expected_data


async def test_set_channel_invalid_secret_length(command_handler):
    with pytest.raises(ValueError, match="Channel secret must be exactly 16 bytes"):
        await command_handler.set_channel(1, "Test", b"tooshort")
