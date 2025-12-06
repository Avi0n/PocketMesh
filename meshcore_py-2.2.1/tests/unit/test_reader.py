#!/usr/bin/env python3

import asyncio
from unittest.mock import AsyncMock
from meshcore.events import EventType
from meshcore.reader import MessageReader

class MockDispatcher:
    def __init__(self):
        self.dispatched_events = []
        
    async def dispatch(self, event):
        self.dispatched_events.append(event)
        print(f"Dispatched: {event.type} with payload keys: {list(event.payload.keys()) if hasattr(event.payload, 'keys') else event.payload}")

import pytest

@pytest.mark.asyncio
async def test_binary_response():
    mock_dispatcher = MockDispatcher()
    reader = MessageReader(mock_dispatcher)
    
    packet_hex = "8c00417db968993acd42fc77c3bbd1f08b9b84c39756410c58cd03077162bcb489031869586ab4b103000000000000000000"
    packet_data = bytearray.fromhex(packet_hex)
    
    print(f"Testing packet: {packet_hex}")
    print(f"Packet type: 0x{packet_data[0]:02x} (should be 0x8c for BINARY_RESPONSE)")
    
    # Register the binary request first
    tag = "417db968"
    from meshcore.parsing import BinaryReqType
    reader.register_binary_request(tag, BinaryReqType.ACL, 10.0)
    print(f"Registered ACL request with tag {tag}")
    
    await reader.handle_rx(packet_data)
    
    # Check what was dispatched
    print(f"\nTotal events dispatched: {len(mock_dispatcher.dispatched_events)}")
    
    # Verify BINARY_RESPONSE was dispatched
    binary_responses = [e for e in mock_dispatcher.dispatched_events if e.type == EventType.BINARY_RESPONSE]
    assert len(binary_responses) == 1, f"Expected 1 BINARY_RESPONSE, got {len(binary_responses)}"
    print("✅ BINARY_RESPONSE event dispatched correctly")
    
    # Check the binary response payload
    binary_event = binary_responses[0]
    assert "tag" in binary_event.payload, "BINARY_RESPONSE should have 'tag' in payload"
    assert "data" in binary_event.payload, "BINARY_RESPONSE should have 'data' in payload"
    print(f"✅ Binary response tag: {binary_event.payload['tag']}")
    print(f"✅ Binary response data: {binary_event.payload['data']}")
    
    # Check if a specific parsed event was also dispatched
    other_events = [e for e in mock_dispatcher.dispatched_events if e.type != EventType.BINARY_RESPONSE]
    if other_events:
        print(f"✅ Additional parsed event dispatched: {other_events[0].type}")
        print(f"   Payload keys: {list(other_events[0].payload.keys()) if hasattr(other_events[0].payload, 'keys') else other_events[0].payload}")
    else:
        print("⚠️ No additional parsed event dispatched")
    
    # Parse the response data to see what request type it is
    response_data = packet_data[6:]
    if response_data:
        request_type = response_data[0]
        print(f"Request type in response: 0x{request_type:02x} ({request_type})")
        
        # Map request types to expected events
        from meshcore.parsing import BinaryReqType
        if request_type == BinaryReqType.STATUS.value:
            expected_event = EventType.STATUS_RESPONSE
        elif request_type == BinaryReqType.TELEMETRY.value:
            expected_event = EventType.TELEMETRY_RESPONSE
        elif request_type == BinaryReqType.MMA.value:
            expected_event = EventType.MMA_RESPONSE
        elif request_type == BinaryReqType.ACL.value:
            expected_event = EventType.ACL_RESPONSE
        else:
            expected_event = None
            
        if expected_event:
            specific_events = [e for e in mock_dispatcher.dispatched_events if e.type == expected_event]
            if specific_events:
                print(f"✅ Expected {expected_event} event was dispatched")
            else:
                print(f"❌ Expected {expected_event} event was NOT dispatched")
        else:
            print(f"⚠️ Unknown request type {request_type}, no specific event expected")

if __name__ == "__main__":
    asyncio.run(test_binary_response())