import logging
from enum import Enum
import json
from cayennelpp import LppFrame, LppData
from cayennelpp.lpp_type import LppType
from .lpp_json_encoder import lpp_json_encoder, my_lpp_types, lpp_format_val

logger = logging.getLogger("meshcore")


def lpp_parse(buf):
    """Parse a given byte string and return as a LppFrame object."""
    i = 0
    lpp_data_list = []
    while i < len(buf) and buf[i] != 0:
        lppdata = LppData.from_bytes(buf[i:])
        lpp_data_list.append(lppdata)
        i = i + len(lppdata)

    return json.loads(json.dumps(LppFrame(lpp_data_list), default=lpp_json_encoder))


def lpp_parse_mma(buf):
    i = 0
    res = []
    while i < len(buf) and buf[i] != 0:
        chan = buf[i]
        i = i + 1
        type = buf[i]
        lpp_type = LppType.get_lpp_type(type)
        if lpp_type is None:
            logger.error(f"Unknown LPP type: {type}")
            return None
        size = lpp_type.size
        i = i + 1
        min = lpp_format_val(lpp_type, lpp_type.decode(buf[i : i + size]))
        i = i + size
        max = lpp_format_val(lpp_type, lpp_type.decode(buf[i : i + size]))
        i = i + size
        avg = lpp_format_val(lpp_type, lpp_type.decode(buf[i : i + size]))
        i = i + size
        res.append(
            {
                "channel": chan,
                "type": my_lpp_types[type][0],
                "min": min,
                "max": max,
                "avg": avg,
            }
        )
    return res


def parse_acl(buf):
    i = 0
    res = []
    while i + 7 <= len(buf):
        key = buf[i : i + 6].hex()
        perm = buf[i + 6]
        if key != "000000000000":
            res.append({"key": key, "perm": perm})
        i = i + 7
    return res


def parse_status(data, pubkey_prefix=None, offset=0):
    """
    Parse binary data into a dictionary of fields.
    
    Args:
        data: bytes object containing the data to parse
        pubkey_prefix: Either a string prefix or None (if None, extract from data)
        offset: Starting offset for field parsing (0 or 8)
    
    Returns:
        Dictionary with parsed fields
    """
    res = {}
    
    # Handle pubkey
    if pubkey_prefix is None:
        # Extract from data (format 1)
        res["pubkey_pre"] = data[2:8].hex()
        offset = 8  # Fields start at offset 8
    else:
        # Use provided prefix (format 2)
        res["pubkey_pre"] = pubkey_prefix
        # offset stays as provided (typically 0)
    
    # Parse all fields with the given offset
    res["bat"] = int.from_bytes(data[offset:offset+2], byteorder="little")
    res["tx_queue_len"] = int.from_bytes(data[offset+2:offset+4], byteorder="little")
    res["noise_floor"] = int.from_bytes(data[offset+4:offset+6], byteorder="little", signed=True)
    res["last_rssi"] = int.from_bytes(data[offset+6:offset+8], byteorder="little", signed=True)
    res["nb_recv"] = int.from_bytes(data[offset+8:offset+12], byteorder="little", signed=False)
    res["nb_sent"] = int.from_bytes(data[offset+12:offset+16], byteorder="little", signed=False)
    res["airtime"] = int.from_bytes(data[offset+16:offset+20], byteorder="little")
    res["uptime"] = int.from_bytes(data[offset+20:offset+24], byteorder="little")
    res["sent_flood"] = int.from_bytes(data[offset+24:offset+28], byteorder="little")
    res["sent_direct"] = int.from_bytes(data[offset+28:offset+32], byteorder="little")
    res["recv_flood"] = int.from_bytes(data[offset+32:offset+36], byteorder="little")
    res["recv_direct"] = int.from_bytes(data[offset+36:offset+40], byteorder="little")
    res["full_evts"] = int.from_bytes(data[offset+40:offset+42], byteorder="little")
    res["last_snr"] = int.from_bytes(data[offset+42:offset+44], byteorder="little", signed=True) / 4
    res["direct_dups"] = int.from_bytes(data[offset+44:offset+46], byteorder="little")
    res["flood_dups"] = int.from_bytes(data[offset+46:offset+48], byteorder="little")
    res["rx_airtime"] = int.from_bytes(data[offset+48:offset+52], byteorder="little")
    
    return res