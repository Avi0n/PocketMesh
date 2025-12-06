import asyncio
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from meshcore.ble_cx import (
    BLEConnection,
    UART_TX_CHAR_UUID,
    UART_RX_CHAR_UUID,
)

class TestBLEConnection(unittest.TestCase):
    @patch("meshcore.ble_cx.BleakClient")

    def test_ble_connection_and_disconnection(self, mock_bleak_client):
        """
        Tests the BLEConnection class for connecting and disconnecting from a BLE device.
        """
        # Arrange
        mock_client_instance = self._get_mock_bleak_client()
        mock_bleak_client.return_value = mock_client_instance

        address = "00:11:22:33:44:55"
        ble_conn = BLEConnection(address=address)

        # Act
        asyncio.run(ble_conn.connect())
        asyncio.run(ble_conn.disconnect())

        # Assert
        mock_client_instance.connect.assert_called_once()
        mock_client_instance.start_notify.assert_called_once_with(
            UART_TX_CHAR_UUID, ble_conn.handle_rx
        )
        mock_client_instance.disconnect.assert_called_once()

    @patch("meshcore.ble_cx.BleakClient")

    def test_send_data(self, mock_bleak_client):
        """
        Tests the send method of the BLEConnection class.
        """
        # Arrange
        mock_client_instance = self._get_mock_bleak_client()
        mock_bleak_client.return_value = mock_client_instance

        address = "00:11:22:33:44:55"
        ble_conn = BLEConnection(address=address)
        asyncio.run(ble_conn.connect())

        # Act
        data_to_send = b"Hello, BLE"
        asyncio.run(ble_conn.send(data_to_send))

        # Assert
        ble_conn.rx_char.write_gatt_char.assert_called_once_with(
            ble_conn.rx_char, data_to_send, response=True
        )

    def _get_mock_bleak_client(self):
        """
        Creates a mock BleakClient instance with all the necessary async methods and attributes.
        """
        mock_client = MagicMock()
        mock_client.connect = AsyncMock()
        mock_client.disconnect = AsyncMock()
        mock_client.start_notify = AsyncMock()
        mock_client.write_gatt_char = AsyncMock()
        mock_client.is_connected = True
        mock_service = MagicMock()
        mock_char = MagicMock()
        mock_char.uuid = UART_RX_CHAR_UUID
        mock_char.write_gatt_char = mock_client.write_gatt_char 
        mock_service.get_characteristic.return_value = mock_char
        mock_client.services.get_service.return_value = mock_service

        return mock_client

if __name__ == '__main__':

    unittest.main()
