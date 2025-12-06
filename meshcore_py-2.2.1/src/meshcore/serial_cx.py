"""
mccli.py : CLI interface to MeschCore BLE companion app
"""

import asyncio
import logging
import serial_asyncio

# Get logger
logger = logging.getLogger("meshcore")


class SerialConnection:
    def __init__(self, port, baudrate, cx_dly=0.2):
        self.port = port
        self.baudrate = baudrate
        self.frame_started = False
        self.frame_size = 0
        self.transport = None
        self.header = b""
        self.reader = None
        self.inframe = b""
        self._disconnect_callback = None
        self.cx_dly = cx_dly
        self._connected_event = asyncio.Event()

    class MCSerialClientProtocol(asyncio.Protocol):
        def __init__(self, cx):
            self.cx = cx

        def connection_made(self, transport):
            self.cx.transport = transport
            logger.debug('port opened')
            if isinstance(transport, serial_asyncio.SerialTransport) and transport.serial:
                transport.serial.rts = False  # You can manipulate Serial object via transport
            self.cx._connected_event.set()

        def data_received(self, data):
            self.cx.handle_rx(data)

        def connection_lost(self, exc):
            logger.debug('Serial port closed')
            self.cx._connected_event.clear()

            if self.cx._disconnect_callback:
                asyncio.create_task(self.cx._disconnect_callback("serial_disconnect"))

        def pause_writing(self):
            logger.debug("pause writing")

        def resume_writing(self):
            logger.debug("resume writing")

    async def connect(self):
        """
        Connects to the device
        """
        self._connected_event.clear()
        
        loop = asyncio.get_running_loop()
        await serial_asyncio.create_serial_connection(
            loop,
            lambda: self.MCSerialClientProtocol(self),
            self.port,
            baudrate=self.baudrate,
        )

        await self._connected_event.wait()
        logger.info("Serial Connection started")
        return self.port

    def set_reader(self, reader):
        self.reader = reader

    def handle_rx(self, data: bytearray):
        headerlen = len(self.header)
        framelen = len(self.inframe)
        if not self.frame_started:  # wait start of frame
            if len(data) >= 3 - headerlen:
                self.header = self.header + data[: 3 - headerlen]
                self.frame_started = True
                self.frame_size = int.from_bytes(self.header[1:], byteorder="little")
                self.handle_rx(data[3 - headerlen :])
            else:
                self.header = self.header + data
        else:
            if framelen + len(data) < self.frame_size:
                self.inframe = self.inframe + data
            else:
                self.inframe = self.inframe + data[: self.frame_size - framelen]
                if self.reader is not None:
                    asyncio.create_task(self.reader.handle_rx(self.inframe))
                self.frame_started = False
                self.header = b""
                self.inframe = b""
                if framelen + len(data) > self.frame_size:
                    self.handle_rx(data[self.frame_size - framelen :])

    async def send(self, data):
        if not self.transport:
            logger.error("Transport not connected, cannot send data")
            return
        size = len(data)
        pkt = b"\x3c" + size.to_bytes(2, byteorder="little") + data
        logger.debug(f"sending pkt : {pkt}")
        self.transport.write(pkt)

    async def disconnect(self):
        """Close the serial connection."""
        if self.transport:
            self.transport.close()
            self.transport = None
            self._connected_event.clear()
            logger.debug("Serial Connection closed")

    def set_disconnect_callback(self, callback):
        """Set callback to handle disconnections."""
        self._disconnect_callback = callback
