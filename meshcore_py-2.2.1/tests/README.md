# MeshCore Tests

## Running Tests

To run the tests, first install the development dependencies:

```bash
pip install -e ".[dev]"
```

Then run the tests using pytest:

```bash
# Run all tests
pytest

# Run tests with verbose output
pytest -v

# Run a specific test file
pytest tests/unit/test_commands.py

# Run a specific test
pytest tests/unit/test_commands.py::test_send_msg
```