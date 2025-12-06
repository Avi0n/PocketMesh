import logging
import json
import time
import io
from typing import Any, Dict
from .events import Event, EventType, EventDispatcher
from .packets import BinaryReqType, PacketType, ControlType
from .parsing import lpp_parse, lpp_parse_mma, parse_acl, parse_status
from cayennelpp import LppFrame, LppData
from meshcore.lpp_json_encoder import lpp_json_encoder

logger = logging.getLogger("meshcore")


class MessageReader:
    def __init__(self, dispatcher: EventDispatcher):
        self.dispatcher = dispatcher
        # We're only keeping state here that's needed for processing
        # before events are dispatched
        self.contacts = {}  # Temporary storage during contact list building
        self.contact_nb = 0  # Used for contact processing

        # Track pending binary requests by tag for proper response parsing
        self.pending_binary_requests: Dict[str, Dict[str, Any]] = {}  # tag -> {request_type, expires_at}

    def register_binary_request(self, prefix: str, tag: str, request_type: BinaryReqType, timeout_seconds: float, context={}):
        """Register a pending binary request for proper response parsing"""
        # Clean up expired requests before adding new one
        self.cleanup_expired_requests()

        expires_at = time.time() + timeout_seconds
        self.pending_binary_requests[tag] = {
            "request_type": request_type,
            "pubkey_prefix": prefix,
            "expires_at": expires_at,
            "context": context # optional info we want to keep from req to resp
        }
        logger.debug(f"Registered binary request: tag={tag}, type={request_type}, expires in {timeout_seconds}s")

    def cleanup_expired_requests(self):
        """Remove expired binary requests"""
        current_time = time.time()
        expired_tags = [
            tag for tag, info in self.pending_binary_requests.items()
            if current_time > info["expires_at"]
        ]

        for tag in expired_tags:
            logger.debug(f"Cleaning up expired binary request: tag={tag}")
            del self.pending_binary_requests[tag]

    async def handle_rx(self, data: bytearray):
        dbuf = io.BytesIO(data)
        packet_type_value = dbuf.read(1)[0]
        logger.debug(f"Received data: {data.hex()}")

        # Handle command responses
        if packet_type_value == PacketType.OK.value:
            result: Dict[str, Any] = {}
            if len(data) == 5:
                result["value"] = int.from_bytes(data[1:5], byteorder="little")

            # Dispatch event for the OK response
            await self.dispatcher.dispatch(Event(EventType.OK, result))

        elif packet_type_value == PacketType.ERROR.value:
            if len(data) > 1:
                result = {"error_code": data[1]}
            else:
                result = {}

            # Dispatch event for the ERROR response
            await self.dispatcher.dispatch(Event(EventType.ERROR, result))

        elif packet_type_value == PacketType.CONTACT_START.value:
            self.contact_nb = int.from_bytes(data[1:5], byteorder="little")
            self.contacts = {}

        elif (
            packet_type_value == PacketType.CONTACT.value
            or packet_type_value == PacketType.PUSH_CODE_NEW_ADVERT.value
        ):
            c = {}
            c["public_key"] = dbuf.read(32).hex()
            c["type"] = dbuf.read(1)[0]
            c["flags"] = dbuf.read(1)[0]
            plen = int.from_bytes(dbuf.read(1), signed=True, byteorder="little")
            c["out_path_len"] = plen
            if plen == -1:
                plen = 0
            path = dbuf.read(64)
            c["out_path"] = path[0:plen].hex()
            c["adv_name"] = dbuf.read(32).decode("utf-8", "ignore").replace("\0", "")
            c["last_advert"] = int.from_bytes(dbuf.read(4), byteorder="little")
            c["adv_lat"] = (
                int.from_bytes(dbuf.read(4), byteorder="little", signed=True) / 1e6
            )
            c["adv_lon"] = (
                int.from_bytes(dbuf.read(4), byteorder="little", signed=True) / 1e6
            )
            c["lastmod"] = int.from_bytes(dbuf.read(4), byteorder="little")

            if packet_type_value == PacketType.PUSH_CODE_NEW_ADVERT.value:
                await self.dispatcher.dispatch(Event(EventType.NEW_CONTACT, c))
            else:
                await self.dispatcher.dispatch(Event(EventType.NEXT_CONTACT, c))
                self.contacts[c["public_key"]] = c

        elif packet_type_value == PacketType.CONTACT_END.value:
            lastmod = int.from_bytes(dbuf.read(4), byteorder="little")
            attributes = {
                "lastmod": lastmod,
            }
            await self.dispatcher.dispatch(
                Event(EventType.CONTACTS, self.contacts, attributes)
            )

        elif packet_type_value == PacketType.SELF_INFO.value:
            self_info = {}
            self_info["adv_type"] = dbuf.read(1)[0]
            self_info["tx_power"] = dbuf.read(1)[0]
            self_info["max_tx_power"] = dbuf.read(1)[0]
            self_info["public_key"] = dbuf.read(32).hex()
            self_info["adv_lat"] = (
                int.from_bytes(dbuf.read(4), byteorder="little", signed=True) / 1e6
            )
            self_info["adv_lon"] = (
                int.from_bytes(dbuf.read(4), byteorder="little", signed=True) / 1e6
            )
            self_info["multi_acks"] = dbuf.read(1)[0]
            self_info["adv_loc_policy"] = dbuf.read(1)[0]
            telemetry_mode = dbuf.read(1)[0]
            self_info["telemetry_mode_env"] = (telemetry_mode >> 4) & 0b11
            self_info["telemetry_mode_loc"] = (telemetry_mode >> 2) & 0b11
            self_info["telemetry_mode_base"] = (telemetry_mode) & 0b11
            self_info["manual_add_contacts"] = dbuf.read(1)[0] > 0
            self_info["radio_freq"] = (
                int.from_bytes(dbuf.read(4), byteorder="little") / 1000
            )
            self_info["radio_bw"] = (
                int.from_bytes(dbuf.read(4), byteorder="little") / 1000
            )
            self_info["radio_sf"] = dbuf.read(1)[0]
            self_info["radio_cr"] = dbuf.read(1)[0]
            self_info["name"] = dbuf.read().decode("utf-8", "ignore")
            await self.dispatcher.dispatch(Event(EventType.SELF_INFO, self_info))

        elif packet_type_value == PacketType.MSG_SENT.value:
            res = {}
            res["type"] = dbuf.read(1)[0]
            res["expected_ack"] = dbuf.read(4)
            res["suggested_timeout"] = int.from_bytes(dbuf.read(4), byteorder="little")

            attributes = {
                "type": res["type"],
                "expected_ack": res["expected_ack"].hex(),
            }

            await self.dispatcher.dispatch(Event(EventType.MSG_SENT, res, attributes))

        elif packet_type_value == PacketType.CONTACT_MSG_RECV.value:
            res = {}
            res["type"] = "PRIV"
            res["pubkey_prefix"] = dbuf.read(6).hex()
            res["path_len"] = dbuf.read(1)[0]
            txt_type = dbuf.read(1)[0]
            res["txt_type"] = txt_type
            res["sender_timestamp"] = int.from_bytes(dbuf.read(4), byteorder="little")
            if txt_type == 2:
                res["signature"] = dbuf.read(4).hex()
            res["text"] = dbuf.read().decode("utf-8", "ignore")

            attributes = {
                "pubkey_prefix": res["pubkey_prefix"],
                "txt_type": res["txt_type"],
            }

            evt_type = EventType.CONTACT_MSG_RECV

            await self.dispatcher.dispatch(Event(evt_type, res, attributes))

        elif packet_type_value == 16:  # A reply to CMD_SYNC_NEXT_MESSAGE (ver >= 3)
            res = {}
            res["type"] = "PRIV"
            res["SNR"] = int.from_bytes(dbuf.read(1), byteorder="little", signed=True) / 4
            dbuf.read(2) # reserved
            res["pubkey_prefix"] = dbuf.read(6).hex()
            res["path_len"] = dbuf.read(1)[0]
            txt_type = dbuf.read(1)[0]
            res["txt_type"] = txt_type
            res["sender_timestamp"] = int.from_bytes(dbuf.read(4), byteorder="little")
            if txt_type == 2:
                res["signature"] = dbuf.read(4).hex()
            res["text"] = dbuf.read().decode("utf-8", "ignore")

            attributes = {
                "pubkey_prefix": res["pubkey_prefix"],
                "txt_type": res["txt_type"],
            }

            await self.dispatcher.dispatch(
                Event(EventType.CONTACT_MSG_RECV, res, attributes)
            )

        elif packet_type_value == PacketType.CHANNEL_MSG_RECV.value:
            res = {}
            res["type"] = "CHAN"
            res["channel_idx"] = dbuf.read(1)[0]
            res["path_len"] = dbuf.read(1)[0]
            res["txt_type"] = dbuf.read(1)[0]
            res["sender_timestamp"] = int.from_bytes(dbuf.read(4), byteorder="little")
            res["text"] = dbuf.read().decode("utf-8", "ignore")

            attributes = {
                "channel_idx": res["channel_idx"],
                "txt_type": res["txt_type"],
            }

            await self.dispatcher.dispatch(
                Event(EventType.CHANNEL_MSG_RECV, res, attributes)
            )

        elif packet_type_value == 17:  # A reply to CMD_SYNC_NEXT_MESSAGE (ver >= 3)
            res = {}
            res["type"] = "CHAN"
            res["SNR"] = int.from_bytes(dbuf.read(1), byteorder="little", signed=True) / 4
            dbuf.read(2) # reserved
            res["channel_idx"] = dbuf.read(1)[0]
            res["path_len"] = dbuf.read(1)[0]
            res["txt_type"] = dbuf.read(1)[0]
            res["sender_timestamp"] = int.from_bytes(dbuf.read(4), byteorder="little")
            res["text"] = dbuf.read().decode("utf-8", "ignore")

            attributes = {
                "channel_idx": res["channel_idx"],
                "txt_type": res["txt_type"],
            }

            await self.dispatcher.dispatch(
                Event(EventType.CHANNEL_MSG_RECV, res, attributes)
            )

        elif packet_type_value == PacketType.CURRENT_TIME.value:
            time_value = int.from_bytes(dbuf.read(4), byteorder="little")
            result = {"time": time_value}
            await self.dispatcher.dispatch(Event(EventType.CURRENT_TIME, result))

        elif packet_type_value == PacketType.NO_MORE_MSGS.value:
            result = {"messages_available": False}
            await self.dispatcher.dispatch(Event(EventType.NO_MORE_MSGS, result))

        elif packet_type_value == PacketType.CONTACT_URI.value:
            contact_uri = "meshcore://" + dbuf.read().hex()
            result = {"uri": contact_uri}
            await self.dispatcher.dispatch(Event(EventType.CONTACT_URI, result))

        elif packet_type_value == PacketType.BATTERY.value:
            battery_level = int.from_bytes(dbuf.read(2), byteorder="little")
            result = {"level": battery_level}
            if len(data) > 3:  # has storage info as well
                result["used_kb"] = int.from_bytes(dbuf.read(4), byteorder="little")
                result["total_kb"] = int.from_bytes(dbuf.read(4), byteorder="little")
            await self.dispatcher.dispatch(Event(EventType.BATTERY, result))

        elif packet_type_value == PacketType.DEVICE_INFO.value:
            res = {}
            res["fw ver"] = dbuf.read(1)[0]
            if data[1] >= 3:
                res["max_contacts"] = dbuf.read(1)[0] * 2
                res["max_channels"] = dbuf.read(1)[0]
                res["ble_pin"] = int.from_bytes(dbuf.read(4), byteorder="little")
                res["fw_build"] = dbuf.read(12).decode("utf-8", "ignore").replace("\0", "")
                res["model"] = dbuf.read(40).decode("utf-8", "ignore").replace("\0", "")
                res["ver"] = dbuf.read(20).decode("utf-8", "ignore").replace("\0", "")
            await self.dispatcher.dispatch(Event(EventType.DEVICE_INFO, res))

        elif packet_type_value == PacketType.CUSTOM_VARS.value:
            logger.debug(f"received custom vars response: {data.hex()}")
            res = {}
            rawdata = dbuf.read().decode("utf-8", "ignore")
            if not rawdata == "":
                pairs = rawdata.split(",")
                for p in pairs:
                    psplit = p.split(":")
                    res[psplit[0]] = psplit[1]
            logger.debug(f"got custom vars : {res}")
            await self.dispatcher.dispatch(Event(EventType.CUSTOM_VARS, res))

        elif packet_type_value == PacketType.CHANNEL_INFO.value:
            logger.debug(f"received channel info response: {data.hex()}")
            res = {}
            res["channel_idx"] = dbuf.read(1)[0]

            # Channel name is null-terminated, so find the first null byte
            name_bytes = dbuf.read(32)
            null_pos = name_bytes.find(0)
            if null_pos >= 0:
                res["channel_name"] = name_bytes[:null_pos].decode("utf-8", "ignore")
            else:
                res["channel_name"] = name_bytes.decode("utf-8", "ignore")

            res["channel_secret"] = dbuf.read(16)
            await self.dispatcher.dispatch(Event(EventType.CHANNEL_INFO, res, res))

        # Push notifications
        elif packet_type_value == PacketType.ADVERTISEMENT.value:
            logger.debug("Advertisement received")
            res = {}
            res["public_key"] = dbuf.read(32).hex()
            await self.dispatcher.dispatch(Event(EventType.ADVERTISEMENT, res, res))

        elif packet_type_value == PacketType.PATH_UPDATE.value:
            logger.debug("Code path update")
            res = {}
            res["public_key"] = dbuf.read(32).hex()
            await self.dispatcher.dispatch(Event(EventType.PATH_UPDATE, res, res))

        elif packet_type_value == PacketType.ACK.value:
            logger.debug("Received ACK")
            ack_data = {}

            if len(data) >= 5:
                ack_data["code"] = dbuf.read(4).hex()

            attributes = {"code": ack_data.get("code", "")}

            await self.dispatcher.dispatch(Event(EventType.ACK, ack_data, attributes))

        elif packet_type_value == PacketType.MESSAGES_WAITING.value:
            logger.debug("Msgs are waiting")
            await self.dispatcher.dispatch(Event(EventType.MESSAGES_WAITING, {}))

        elif packet_type_value == PacketType.RAW_DATA.value:
            res = {}
            res["SNR"] = int.from_bytes(dbuf.read(1), byteorder="little", signed=True) / 4
            res["RSSI"] = int.from_bytes(dbuf.read(1), byteorder="little", signed=True)
            res["payload"] = dbuf.read(4).hex()
            logger.debug("Received raw data")
            print(res)
            await self.dispatcher.dispatch(Event(EventType.RAW_DATA, res))

        elif packet_type_value == PacketType.LOGIN_SUCCESS.value:
            res = {}
            attributes = {}
            if len(data) > 1:
                perms = dbuf.read(1)[0]
                res["permissions"] = perms
                res["is_admin"] = (perms & 1) == 1  # Check if admin bit is set

                res["pubkey_prefix"] = dbuf.read(6).hex()

                attributes = {"pubkey_prefix": res.get("pubkey_prefix")}

            await self.dispatcher.dispatch(
                Event(EventType.LOGIN_SUCCESS, res, attributes)
            )

        elif packet_type_value == PacketType.LOGIN_FAILED.value:
            res = {}
            attributes = {}

            pbuf.read(1)

            if len(data) > 7:
                res["pubkey_prefix"] = pbuf.read(6).hex()

                attributes = {"pubkey_prefix": res.get("pubkey_prefix")}

            await self.dispatcher.dispatch(
                Event(EventType.LOGIN_FAILED, res, attributes)
            )

        elif packet_type_value == PacketType.STATUS_RESPONSE.value:
            res = parse_status(data, offset=8)
            data_hex = data[8:].hex()
            logger.debug(f"Status response: {data_hex}")

            attributes = {
                "pubkey_prefix": res["pubkey_pre"],
            }

            await self.dispatcher.dispatch(
                Event(EventType.STATUS_RESPONSE, res, attributes)
            )

        elif packet_type_value == PacketType.LOG_DATA.value:
            logger.debug(f"Received RF log data: {data.hex()}")

            # Parse as raw RX data
            log_data: Dict[str, Any] = {"raw_hex": data[1:].hex()}

            # First byte is SNR (signed byte, multiplied by 4)
            if len(data) > 1:
                snr_byte = dbuf.read(1)[0]
                # Convert to signed value
                snr = (snr_byte if snr_byte < 128 else snr_byte - 256) / 4.0
                log_data["snr"] = snr

            # Second byte is RSSI (signed byte)
            if len(data) > 2:
                rssi_byte = dbuf.read(1)[0]
                # Convert to signed value
                rssi = rssi_byte if rssi_byte < 128 else rssi_byte - 256
                log_data["rssi"] = rssi

            # Remaining bytes are the raw data payload
            if len(data) > 3:
                payload=dbuf.read()
                log_data["payload"] = payload.hex()
                log_data["payload_length"] = len(payload)

            attributes = {
                "pubkey_prefix": log_data["raw_hex"],
            }

            # Dispatch as RF log data
            await self.dispatcher.dispatch(
                Event(EventType.RX_LOG_DATA, log_data, attributes)
            )

        elif packet_type_value == PacketType.TRACE_DATA.value:
            logger.debug(f"Received trace data: {data.hex()}")
            res = {}

            # According to the source, format is:
            # 0x89, reserved(0), path_len, flags, tag(4), auth(4), path_hashes[], path_snrs[], final_snr

            path_len = data[2]
            flags = data[3]
            tag = int.from_bytes(data[4:8], byteorder="little")
            auth_code = int.from_bytes(data[8:12], byteorder="little")

            # Initialize result
            res["tag"] = tag
            res["auth"] = auth_code
            res["flags"] = flags
            res["path_len"] = path_len

            # Process path as array of objects with hash and SNR
            path_nodes = []

            if path_len > 0 and len(data) >= 12 + path_len * 2 + 1:
                # Extract path with hash and SNR pairs
                for i in range(path_len):
                    node = {
                        "hash": f"{data[12+i]:02x}",
                        # SNR is stored as a signed byte representing SNR * 4
                        "snr": (
                            data[12 + path_len + i]
                            if data[12 + path_len + i] < 128
                            else data[12 + path_len + i] - 256
                        )
                        / 4.0,
                    }
                    path_nodes.append(node)

                # Add the final node (our device) with its SNR
                final_snr_byte = data[12 + path_len * 2]
                final_snr = (
                    final_snr_byte if final_snr_byte < 128 else final_snr_byte - 256
                ) / 4.0
                path_nodes.append({"snr": final_snr})

                res["path"] = path_nodes

            logger.debug(f"Parsed trace data: {res}")

            attributes = {
                "tag": res["tag"],
                "auth_code": res["auth"],
            }

            await self.dispatcher.dispatch(Event(EventType.TRACE_DATA, res, attributes))

        elif packet_type_value == PacketType.TELEMETRY_RESPONSE.value:
            logger.debug(f"Received telemetry data: {data.hex()}")
            res = {}

            dbuf.read(1)

            res["pubkey_pre"] = dbuf.read(6).hex()
            buf = dbuf.read()

            """Parse a given byte string and return as a LppFrame object."""
            i = 0
            lpp_data_list = []
            while i < len(buf) and buf[i] != 0:
                lppdata = LppData.from_bytes(buf[i:])
                lpp_data_list.append(lppdata)
                i = i + len(lppdata)

            lpp = json.loads(
                json.dumps(LppFrame(lpp_data_list), default=lpp_json_encoder)
            )

            res["lpp"] = lpp

            attributes = {
                "raw": buf.hex(),
                "pubkey_prefix": res["pubkey_pre"],
            }

            await self.dispatcher.dispatch(
                Event(EventType.TELEMETRY_RESPONSE, res, attributes)
            )

        elif packet_type_value == PacketType.BINARY_RESPONSE.value:
            logger.debug(f"Received binary data: {data.hex()}")
            dbuf.read(1)
            tag = dbuf.read(4).hex()
            response_data = dbuf.read()

            # Always dispatch generic BINARY_RESPONSE
            binary_res = {"tag": tag, "data": response_data.hex()}
            await self.dispatcher.dispatch(
                Event(EventType.BINARY_RESPONSE, binary_res, {"tag": tag})
            )

            # Check for tracked request type and dispatch specific response
            if tag in self.pending_binary_requests:
                request_type = self.pending_binary_requests[tag]["request_type"]
                pubkey_prefix = self.pending_binary_requests[tag]["pubkey_prefix"]
                context = self.pending_binary_requests[tag]["context"]
                del self.pending_binary_requests[tag]
                logger.debug(f"Processing binary response for tag {tag}, type {request_type}, pubkey_prefix {pubkey_prefix}")

                if request_type == BinaryReqType.STATUS and len(response_data) >= 52:
                    res = {}
                    res = parse_status(response_data, pubkey_prefix=pubkey_prefix)
                    await self.dispatcher.dispatch(
                        Event(EventType.STATUS_RESPONSE, res, {"pubkey_prefix": res["pubkey_pre"], "tag": tag})
                    )

                elif request_type == BinaryReqType.TELEMETRY:
                    try:
                        lpp = lpp_parse(response_data)
                        telem_res = {"tag": tag, "lpp": lpp, "pubkey_prefix": pubkey_prefix}
                        await self.dispatcher.dispatch(
                            Event(EventType.TELEMETRY_RESPONSE, telem_res, telem_res)
                        )
                    except Exception as e:
                        logger.error(f"Error parsing binary telemetry response: {e}")

                elif request_type == BinaryReqType.MMA:
                    try:
                        mma_result = lpp_parse_mma(response_data[4:])  # Skip 4-byte header
                        mma_res = {"tag": tag, "mma_data": mma_result, "pubkey_prefix": pubkey_prefix}
                        await self.dispatcher.dispatch(
                            Event(EventType.MMA_RESPONSE, mma_res, mma_res)
                        )
                    except Exception as e:
                        logger.error(f"Error parsing binary MMA response: {e}")

                elif request_type == BinaryReqType.ACL:
                    try:
                        acl_result = parse_acl(response_data)
                        acl_res = {"tag": tag, "acl_data": acl_result, "pubkey_prefix": pubkey_prefix}
                        await self.dispatcher.dispatch(
                            Event(EventType.ACL_RESPONSE, acl_res, {"tag": tag, "pubkey_prefix": pubkey_prefix})
                        )
                    except Exception as e:
                        logger.error(f"Error parsing binary ACL response: {e}")

                elif request_type == BinaryReqType.NEIGHBOURS:
                    try:
                        pk_plen = context["pubkey_prefix_length"]
                        bbuf = io.BytesIO(response_data)

                        res = {
                            "pubkey_prefix": pubkey_prefix,
                            "tag": tag
                        }
                        res.update(context) # add context in result

                        res["neighbours_count"] = int.from_bytes(bbuf.read(2), "little", signed=True)
                        results_count = int.from_bytes(bbuf.read(2), "little", signed=True)
                        res["results_count"] = results_count

                        neighbours_list = []

                        for _ in range (results_count):
                            neighb = {}
                            neighb["pubkey"] = bbuf.read(pk_plen).hex()
                            neighb["secs_ago"] = int.from_bytes(bbuf.read(4), "little", signed=True)
                            neighb["snr"] = int.from_bytes(bbuf.read(1), "little", signed=True) / 4
                            neighbours_list.append(neighb)

                        res["neighbours"] = neighbours_list

                        await self.dispatcher.dispatch(
                            Event(EventType.NEIGHBOURS_RESPONSE, res, {"tag": tag, "pubkey_prefix": pubkey_prefix})
                        )

                    except Exception as e:
                        logger.error(f"Error parsing binary NEIGHBOURS response: {e}")

            else:
                logger.debug(f"No tracked request found for binary response tag {tag}")

        elif packet_type_value == PacketType.PATH_DISCOVERY_RESPONSE.value:
            logger.debug(f"Received path discovery response: {data.hex()}")
            res = {}
            dbuf.read(1)
            res["pubkey_pre"] = dbuf.read(6).hex()
            opl = dbuf.read(1)[0]
            res["out_path_len"] = opl
            res["out_path"] = dbuf.read(opl).hex()
            ipl = dbuf.read(1)[0]
            res["in_path_len"] = ipl
            res["in_path"] = dbuf.read(ipl).hex()

            attributes = {"pubkey_pre": res["pubkey_pre"]}

            await self.dispatcher.dispatch(
                Event(EventType.PATH_RESPONSE, res, attributes)
            )

        elif packet_type_value == PacketType.PRIVATE_KEY.value:
            logger.debug(f"Received private key response: {data.hex()}")
            if len(data) >= 65:  # 1 byte response code + 64 bytes private key
                private_key = dbuf.read(64)  # Extract 64-byte private key
                res = {"private_key": private_key}
                await self.dispatcher.dispatch(Event(EventType.PRIVATE_KEY, res))
            else:
                logger.error(f"Invalid private key response length: {len(data)}")

        elif packet_type_value == PacketType.DISABLED.value:
            logger.debug("Received disabled response")
            res = {"reason": "private_key_export_disabled"}
            await self.dispatcher.dispatch(Event(EventType.DISABLED, res))

        elif packet_type_value == PacketType.CONTROL_DATA.value:
            logger.debug("Received control data packet")
            res={}
            res["SNR"] = int.from_bytes(dbuf.read(1), byteorder="little", signed=True) / 4
            res["RSSI"] = int.from_bytes(dbuf.read(1), byteorder="little", signed=True)
            res["path_len"] = dbuf.read(1)[0]
            payload = dbuf.read()
            payload_type = payload[0]
            res["payload_type"] = payload_type
            res["payload"] = payload

            attributes = {"payload_type": payload_type}
            await self.dispatcher.dispatch(
                Event(EventType.CONTROL_DATA, res, attributes)
            )

            # decode NODE_DISCOVER_RESP
            if payload_type & 0xF0 == ControlType.NODE_DISCOVER_RESP.value:
                pbuf = io.BytesIO(payload[1:])
                ndr = dict(res)
                del ndr["payload_type"]
                del ndr["payload"]
                ndr["node_type"] = payload_type & 0x0F
                ndr["SNR_in"] = int.from_bytes(pbuf.read(1), byteorder="little", signed=True)/4
                ndr["tag"] = pbuf.read(4).hex()

                pubkey = pbuf.read()
                if len(pubkey) < 32:
                    pubkey = pubkey[0:8]
                else:
                    pubkey = pubkey[0:32]

                ndr["pubkey"] = pubkey.hex()

                attributes = {
                    "node_type" : ndr["node_type"],
                    "tag" : ndr["tag"],
                    "pubkey" : ndr["pubkey"],
                }

                await self.dispatcher.dispatch(
                    Event(EventType.DISCOVER_RESPONSE, ndr, attributes)
                )

        else:
            logger.debug(f"Unhandled data received {data}")
            logger.debug(f"Unhandled packet type: {packet_type_value}")
