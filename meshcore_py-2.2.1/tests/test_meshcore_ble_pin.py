import unittest
from meshcore.ble_cx import BLEConnection


class TestMeshCoreBLEPin(unittest.TestCase):
    """Test MeshCore BLE PIN pairing functionality"""

    def test_ble_connection_pin_parameter_propagation(self):
        """Test that PIN parameter is properly passed to BLEConnection"""
        # Arrange
        address = "00:11:22:33:44:55"
        pin = "654321"

        # Act
        connection = BLEConnection(address=address, pin=pin)

        # Assert
        self.assertEqual(connection.pin, pin)
        self.assertEqual(connection.address, address)

    def test_ble_connection_pin_none_by_default(self):
        """Test that PIN is None by default when not specified"""
        # Arrange
        address = "00:11:22:33:44:55"

        # Act
        connection = BLEConnection(address=address)

        # Assert
        self.assertIsNone(connection.pin)
        self.assertEqual(connection.address, address)


if __name__ == "__main__":
    unittest.main()