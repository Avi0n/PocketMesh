"""
Example demonstrating connection events and auto-reconnect functionality.
"""
import asyncio
import logging
import sys
from meshcore import MeshCore
from meshcore.events import EventType

logging.basicConfig(level=logging.DEBUG)

async def main():
    mc = None
    # Example with auto-reconnect enabled
    try:
        # mc = await MeshCore.create_serial(
        #     port="/dev/cu.usbmodem1101", 
        #     auto_reconnect=True, 
        #     max_reconnect_attempts=3,
        #     debug=True
        # )
        
        # mc = await MeshCore.create_tcp(
        #     host="192.168.1.22",
        #     port=5000, 
        #     auto_reconnect=True, 
        #     max_reconnect_attempts=sys.maxsize,
        #     debug=True
        # )
        
        mc = await MeshCore.create_ble(
            address="92849669", 
            auto_reconnect=True, 
            max_reconnect_attempts=3,
            debug=True
        )
        
        # Subscribe to connection events
        async def on_connected(event):
            print(f"✅ Connected! Info: {event.payload}")
            if event.payload.get('reconnected'):
                print("🔄 This was a reconnection!")
            
        async def on_disconnected(event):
            print(f"❌ Disconnected! Reason: {event.payload.get('reason')}")
            if event.payload.get('max_attempts_exceeded'):
                print("⚠️  Max reconnection attempts exceeded")
        
        mc.subscribe(EventType.CONNECTED, on_connected)
        mc.subscribe(EventType.DISCONNECTED, on_disconnected)
        
        # Check connection status
        
        print("\n📱 Disconnect your device now to test auto-reconnect...")
        print("Press Ctrl+C to exit")
        
        # Keep running and periodically test the connection
        while True:
            await asyncio.sleep(2)
            print(f"Connected: {mc.is_connected}")
            if mc.is_connected:
                try:
                    print("🔄 Testing connection by getting battery...")
                    result = await mc.commands.get_bat()
                    
                    if result.type == EventType.ERROR:
                        print(f"❌ Error getting battery: {result.payload}")
                    else:
                        print("✅ Connection test successfeul")
                except Exception as e:
                    print(f"❌ Connection test failed: {e}")
                    # This should trigger the disconnect detection
            else:
                print("⏳ Waiting for reconnection...")
        
    except KeyboardInterrupt:
        print("\n🛑 Exiting...")
    except ConnectionError as e:
        print(f"❌ Failed to connect: {e}")
    finally:
        if mc is not None:
            await mc.disconnect()
            print(f"Connected after disconnect: {mc.is_connected}")
            print(f"Connected after disconnect: {mc.is_connected}")

if __name__ == "__main__":
    asyncio.run(main())