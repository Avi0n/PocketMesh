from typing import Any, Optional

from ..events import EventDispatcher
from ..reader import MessageReader
from .base import CommandHandlerBase
from .binary import BinaryCommandHandler
from .contact import ContactCommands
from .device import DeviceCommands
from .messaging import MessagingCommands
from .control_data import ControlDataCommandHandler


class CommandHandler(
    DeviceCommands,
    ContactCommands,
    MessagingCommands,
    BinaryCommandHandler,
    ControlDataCommandHandler
):
    pass


__all__ = ["CommandHandler"]
