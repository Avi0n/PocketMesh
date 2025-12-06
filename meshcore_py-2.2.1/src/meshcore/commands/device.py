import logging
from hashlib import sha256
from typing import Optional

from ..events import Event, EventType
from .base import CommandHandlerBase, DestinationType, _validate_destination

logger = logging.getLogger("meshcore")


class DeviceCommands(CommandHandlerBase):
    async def send_appstart(self) -> Event:
        logger.debug("Sending appstart command")
        b1 = bytearray(b"\x01\x03      mccli")
        return await self.send(b1, [EventType.SELF_INFO])

    async def send_device_query(self) -> Event:
        logger.debug("Sending device query command")
        return await self.send(b"\x16\x03", [EventType.DEVICE_INFO, EventType.ERROR])

    async def send_advert(self, flood: bool = False) -> Event:
        logger.debug(f"Sending advertisement command (flood={flood})")
        if flood:
            return await self.send(b"\x07\x01", [EventType.OK, EventType.ERROR])
        else:
            return await self.send(b"\x07", [EventType.OK, EventType.ERROR])

    async def set_name(self, name: str) -> Event:
        logger.debug(f"Setting device name to: {name}")
        return await self.send(
            b"\x08" + name.encode("utf-8"), [EventType.OK, EventType.ERROR]
        )

    async def set_coords(self, lat: float, lon: float) -> Event:
        logger.debug(f"Setting coordinates to: lat={lat}, lon={lon}")
        return await self.send(
            b"\x0e"
            + int(lat * 1e6).to_bytes(4, "little", signed=True)
            + int(lon * 1e6).to_bytes(4, "little", signed=True)
            + int(0).to_bytes(4, "little"),
            [EventType.OK, EventType.ERROR],
        )

    async def reboot(self) -> Event:
        logger.debug("Sending reboot command")
        return await self.send(b"\x13reboot")

    async def get_bat(self) -> Event:
        logger.debug("Getting battery information")
        return await self.send(b"\x14", [EventType.BATTERY, EventType.ERROR])

    async def get_time(self) -> Event:
        logger.debug("Getting device time")
        return await self.send(b"\x05", [EventType.CURRENT_TIME, EventType.ERROR])

    async def set_time(self, val: int) -> Event:
        logger.debug(f"Setting device time to: {val}")
        return await self.send(
            b"\x06" + int(val).to_bytes(4, "little"), [EventType.OK, EventType.ERROR]
        )

    async def set_tx_power(self, val: int) -> Event:
        logger.debug(f"Setting TX power to: {val}")
        return await self.send(
            b"\x0c" + int(val).to_bytes(4, "little"), [EventType.OK, EventType.ERROR]
        )

    async def set_radio(self, freq: float, bw: float, sf: int, cr: int) -> Event:
        logger.debug(f"Setting radio params: freq={freq}, bw={bw}, sf={sf}, cr={cr}")
        return await self.send(
            b"\x0b"
            + int(float(freq) * 1000).to_bytes(4, "little")
            + int(float(bw) * 1000).to_bytes(4, "little")
            + int(sf).to_bytes(1, "little")
            + int(cr).to_bytes(1, "little"),
            [EventType.OK, EventType.ERROR],
        )

    async def set_tuning(self, rx_dly: int, af: int) -> Event:
        logger.debug(f"Setting tuning params: rx_dly={rx_dly}, af={af}")
        return await self.send(
            b"\x15"
            + int(rx_dly).to_bytes(4, "little")
            + int(af).to_bytes(4, "little")
            + int(0).to_bytes(1, "little")
            + int(0).to_bytes(1, "little"),
            [EventType.OK, EventType.ERROR],
        )

    # the old set_other_params function has been replaced in
    # favour of set_other_params_from_infos to be more generic
    # stays here for backward compatibility but does not support
    # multi_acks for instance
    async def set_other_params(
            self,
            manual_add_contacts: bool,
            telemetry_mode_base: int,
            telemetry_mode_loc: int,
            telemetry_mode_env: int,
            advert_loc_policy: int,
        ) -> Event:
        telemetry_mode = (
            (telemetry_mode_base & 0b11)
            | ((telemetry_mode_loc & 0b11) << 2)
            | ((telemetry_mode_env & 0b11) << 4)
        )
        data = (
            b"\x26"
            + manual_add_contacts.to_bytes(1, "little")
            + telemetry_mode.to_bytes(1, "little")
            + advert_loc_policy.to_bytes(1, "little")
        )
        return await self.send(data, [EventType.OK, EventType.ERROR])

    async def set_other_params_from_infos(self, infos) -> Event:
        telemetry_mode = (
            (infos["telemetry_mode_base"] & 0b11)
            | ((infos["telemetry_mode_loc"] & 0b11) << 2)
            | ((infos["telemetry_mode_env"] & 0b11) << 4)
        )
        data = (
            b"\x26"
            + infos["manual_add_contacts"].to_bytes(1, "little")
            + telemetry_mode.to_bytes(1, "little")
            + infos["adv_loc_policy"].to_bytes(1, "little")
            + infos["multi_acks"].to_bytes(1, "little")
        )
        return await self.send(data, [EventType.OK, EventType.ERROR])

    async def set_telemetry_mode_base(self, telemetry_mode_base: int) -> Event:
        infos = (await self.send_appstart()).payload
        infos["telemetry_mode_base"] = telemetry_mode_base
        return await self.set_other_params_from_infos(infos)

    async def set_telemetry_mode_loc(self, telemetry_mode_loc: int) -> Event:
        infos = (await self.send_appstart()).payload
        infos["telemetry_mode_loc"] = telemetry_mode_loc
        return await self.set_other_params_from_infos(infos)

    async def set_telemetry_mode_env(self, telemetry_mode_env: int) -> Event:
        infos = (await self.send_appstart()).payload
        infos["telemetry_mode_env"] = telemetry_mode_env
        return await self.set_other_params_from_infos(infos)

    async def set_manual_add_contacts(self, manual_add_contacts: bool) -> Event:
        infos = (await self.send_appstart()).payload
        infos["manual_add_contacts"] = manual_add_contacts
        return await self.set_other_params_from_infos(infos)

    async def set_advert_loc_policy(self, advert_loc_policy: int) -> Event:
        infos = (await self.send_appstart()).payload
        infos["adv_loc_policy"] = advert_loc_policy
        return await self.set_other_params_from_infos(infos)

    async def set_multi_acks(self, multi_acks: int) -> Event:
        infos = (await self.send_appstart()).payload
        infos["multi_acks"] = multi_acks
        return await self.set_other_params_from_infos(infos)

    async def set_devicepin(self, pin: int) -> Event:
        logger.debug(f"Setting device PIN to: {pin}")
        return await self.send(
            b"\x25" + int(pin).to_bytes(4, "little"), [EventType.OK, EventType.ERROR]
        )

    async def get_self_telemetry(self) -> Event:
        logger.debug("Getting self telemetry")
        data = b"\x27\x00\x00\x00"
        return await self.send(data, [EventType.TELEMETRY_RESPONSE, EventType.ERROR])

    async def get_custom_vars(self) -> Event:
        logger.debug("Asking for custom vars")
        data = b"\x28"
        return await self.send(data, [EventType.CUSTOM_VARS, EventType.ERROR])

    async def set_custom_var(self, key, value) -> Event:
        logger.debug(f"Setting custom var {key} to {value}")
        data = b"\x29" + key.encode("utf-8") + b":" + value.encode("utf-8")
        return await self.send(data, [EventType.OK, EventType.ERROR])

    async def get_channel(self, channel_idx: int) -> Event:
        logger.debug(f"Getting channel info for channel {channel_idx}")
        data = b"\x1f" + channel_idx.to_bytes(1, "little")
        return await self.send(data, [EventType.CHANNEL_INFO, EventType.ERROR])

    async def set_channel(
        self, channel_idx: int, channel_name: str, channel_secret: bytes = None
    ) -> Event:
        logger.debug(f"Setting channel {channel_idx}: name={channel_name}")

        # Pad channel name to 32 bytes
        name_bytes = channel_name.encode("utf-8")[:32]
        name_bytes = name_bytes.ljust(32, b"\x00")

        if channel_name.startswith("#") or channel_secret is None: # auto name => key calculated from hash
            channel_secret = sha256(channel_name.encode("utf-8")).digest()[0:16]

        # Ensure channel secret is exactly 16 bytes
        if len(channel_secret) != 16:
            raise ValueError("Channel secret must be exactly 16 bytes")

        data = b"\x20" + channel_idx.to_bytes(1, "little") + name_bytes + channel_secret
        return await self.send(data, [EventType.OK, EventType.ERROR])

    async def export_private_key(self) -> Event:
        logger.debug("Requesting private key export")
        return await self.send(b"\x17", [EventType.PRIVATE_KEY, EventType.DISABLED, EventType.ERROR])
