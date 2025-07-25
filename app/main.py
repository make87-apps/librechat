import logging
import time
from make87_messages.core.header_pb2 import Header
from make87_messages.text.text_plain_pb2 import PlainText
from make87.encodings import ProtobufEncoder
from make87.interfaces.zenoh import ZenohInterface

logging.Formatter.converter = time.gmtime
logging.basicConfig(
    format="[%(asctime)sZ %(levelname)s  %(name)s] %(message)s", level=logging.INFO, datefmt="%Y-%m-%dT%H:%M:%S"
)


def main():
    message_encoder = ProtobufEncoder(message_type=PlainText)
    zenoh_interface = ZenohInterface(name="zenoh")

    publisher = zenoh_interface.get_publisher("outgoing_message")
    header = Header(entity_path="/pytest/pub_sub", reference_id=0)

    while True:
        header.timestamp.GetCurrentTime()
        message = PlainText(header=header, body="Hello, World! 🐍")
        message_encoded = message_encoder.encode(message)
        publisher.put(payload=message_encoded)

        logging.info(f"Published: {message}")
        time.sleep(1)


if __name__ == "__main__":
    main()
