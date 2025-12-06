"""A library for communicating with meshcore devices."""
import logging

from .ble_cx import BLEConnection
from .connection_manager import ConnectionManager
from .events import EventType
from .meshcore import MeshCore
from .packets import BinaryReqType
from .serial_cx import SerialConnection
from .tcp_cx import TCPConnection

# Setup default logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

__all__ = [
    "BinaryReqType",
    "BLEConnection",
    "ConnectionManager",
    "EventType",
    "MeshCore",
    "SerialConnection",
    "TCPConnection",
    "logger",
]
