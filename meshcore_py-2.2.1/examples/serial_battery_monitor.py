#!/usr/bin/env python3
"""
Simple example of eventing approach with battery monitoring
"""
import asyncio
import argparse

from meshcore import MeshCore
from meshcore.events import EventType


async def main():
    parser = argparse.ArgumentParser(description="Battery Monitor Example")
    parser.add_argument("--port", "-p", help="Serial port", required=True)
    parser.add_argument("--baud", "-b", type=int, help="Baud rate", default=115200)
    args = parser.parse_args()

    print(f"Connecting to {args.port}...")
    
    # Connect to device
    meshcore = await MeshCore.create_serial(args.port, args.baud)
    
    # Event handler for battery updates
    async def on_battery(event):
        print(f"Battery event: {event.payload}mV")
    
    # Subscribe to battery events
    meshcore.subscribe(EventType.BATTERY, on_battery)
    
    # Background task that checks battery every 10 seconds
    async def check_battery():
        while True:
            print("Requesting battery level...")
            await meshcore.commands.get_bat()  # This command will trigger a battery event
            await asyncio.sleep(10)
    
    # Start the battery check task
    task = asyncio.create_task(check_battery())
    
    try:
        # Keep program running
        print("Monitoring battery (press Ctrl+C to exit)...")
        await asyncio.sleep(float('inf'))
    except KeyboardInterrupt:
        print("\nExiting...")
    finally:
        # Clean up
        task.cancel()
        await meshcore.disconnect()


if __name__ == "__main__":
    asyncio.run(main())