from cayennelpp import LppFrame, LppData
from cayennelpp.lpp_type import LppType

# Format : type name "how to display value"
#   display : None: (use lib default), []: only one value to display, ["field1", "field2" ...]: meaning of each field
my_lpp_types = {
    0: ("digital input", []),
    1: ("digital output", []),
    2: ("analog input", []),
    3: ("analog output", []),
    100: ("generic sensor", []),
    101: ("illuminance", []),
    102: ("presence", []),
    103: ("temperature", []),
    104: ("humidity", []),
    113: ("accelerometer", ["acc_x", "acc_y", "acc_z"]),
    115: ("barometer", []),
    116: ("voltage", []),
    117: ("current", []),
    118: ("frequency", []),
    120: ("percentage", []),
    121: ("altitude", []),
    122: ("load", []),
    125: ("concentration", []),
    128: ("power", []),
    130: ("distance", []),
    131: ("energy", []),
    132: ("direction", None),
    133: ("time", []),
    134: ("gyrometer", None),
    135: ("colour", ["red", "green", "blue"]),
    136: ("gps", ["latitude", "longitude", "altitude"]),
    142: ("switch", []),
}


def lpp_format_val(type, val):
    if my_lpp_types[type.type][1] is None:
        return val

    if len(my_lpp_types[type.type][1]) == 0:
        return val[0]

    val_dict = {}
    i = 0
    for t in my_lpp_types[type.type][1]:
        val_dict[t] = val[i]
        i = i + 1
    return val_dict


def lpp_json_encoder(obj, types=my_lpp_types):
    """Encode LppType, LppData, and LppFrame to JSON."""
    if isinstance(obj, LppFrame):
        return obj.data
    if isinstance(obj, LppType):
        return my_lpp_types[obj.type][0]
    if isinstance(obj, LppData):
        return {
            "channel": obj.channel,
            "type": obj.type,
            "value": lpp_format_val(obj.type, obj.value),
        }
    raise TypeError(repr(obj) + " is not JSON serialized")
