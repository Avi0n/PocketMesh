"""
mccli.py : CLI interface to MeschCore BLE companion app
"""

import asyncio
import logging

# Get logger
logger = logging.getLogger("meshcore")

# TCP disconnect detection threshold
TCP_DISCONNECT_THRESHOLD = 5


class TCPConnection:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.transport = None
        self.frame_started = False
        self.frame_size = 0
        self.header = b""
        self.inframe = b""
        self._disconnect_callback = None
        self._send_count = 0
        self._receive_count = 0

    class MCClientProtocol(asyncio.Protocol):
        def __init__(self, cx):
            self.cx = cx

        def connection_made(self, transport):
            self.cx.transport = transport
            # Reset counters on new connection
            self.cx._send_count = 0
            self.cx._receive_count = 0
            logger.debug("connection established")

        def data_received(self, data):
            logger.debug("data received")
            self.cx._receive_count += 1
            self.cx.handle_rx(data)

        def error_received(self, exc):
            logger.error(f"Error received: {exc}")

        def connection_lost(self, exc):
            logger.debug("TCP server closed the connection")
            if self.cx._disconnect_callback:
                asyncio.create_task(self.cx._disconnect_callback("tcp_disconnect"))

    async def connect(self):
        """
        Connects to the device
        """
        loop = asyncio.get_running_loop()
        await loop.create_connection(
            lambda: self.MCClientProtocol(self), self.host, self.port
        )

        logger.info("TCP Connection started")
        future = asyncio.Future()
        future.set_result(self.host)

        return future

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
            if self._disconnect_callback:
                await self._disconnect_callback("tcp_transport_lost")
            return

        self._send_count += 1

        # Check if we've sent packets without any responses
        if self._send_count - self._receive_count >= TCP_DISCONNECT_THRESHOLD:
            logger.debug(
                f"TCP disconnect detected: sent {self._send_count}, received {self._receive_count}"
            )
            if self._disconnect_callback:
                await self._disconnect_callback("tcp_no_response")
            return

        size = len(data)
        pkt = b"\x3c" + size.to_bytes(2, byteorder="little") + data
        logger.debug(f"sending pkt : {pkt}")
        self.transport.write(pkt)

    async def disconnect(self):
        """Close the TCP connection."""
        if self.transport:
            self.transport.close()
            self.transport = None
            logger.debug("TCP Connection closed")

    def set_disconnect_callback(self, callback):
        """Set callback to handle disconnections."""
        self._disconnect_callback = callback
