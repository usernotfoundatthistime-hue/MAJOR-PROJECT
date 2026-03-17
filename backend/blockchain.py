import json
import hashlib
from datetime import datetime
import os

BLOCKCHAIN_FILE = "blockchain.json"


class Blockchain:

    def __init__(self):
        if not os.path.exists(BLOCKCHAIN_FILE):
            self.create_genesis_block()

    def create_genesis_block(self):
        genesis_block = {
            "index": 0,
            "timestamp": str(datetime.now()),
            "event_type": "GENESIS_BLOCK",
            "data": "Initial Block",
            "previous_hash": "0",
        }

        genesis_block["hash"] = self.calculate_hash(genesis_block)

        with open(BLOCKCHAIN_FILE, "w") as f:
            json.dump([genesis_block], f, indent=4)

    def load_chain(self):
        with open(BLOCKCHAIN_FILE, "r") as f:
            return json.load(f)

    def calculate_hash(self, block):
        block_string = json.dumps({
            "index": block["index"],
            "timestamp": block["timestamp"],
            "event_type": block["event_type"],
            "data": block["data"],
            "previous_hash": block["previous_hash"],
        }, sort_keys=True)

        return hashlib.sha256(block_string.encode()).hexdigest()

    def get_last_block(self):
        chain = self.load_chain()
        return chain[-1]

    def add_block(self, event_type, data):
        chain = self.load_chain()
        last_block = chain[-1]

        new_block = {
            "index": last_block["index"] + 1,
            "timestamp": str(datetime.now()),
            "event_type": event_type,
            "data": data,
            "previous_hash": last_block["hash"],
        }

        new_block["hash"] = self.calculate_hash(new_block)

        chain.append(new_block)

        with open(BLOCKCHAIN_FILE, "w") as f:
            json.dump(chain, f, indent=4)

    def verify_chain(self):
        chain = self.load_chain()

        for i in range(1, len(chain)):
            current = chain[i]
            previous = chain[i - 1]

            # Verify hash integrity
            if current["hash"] != self.calculate_hash(current):
                return False

            # Verify chain linkage
            if current["previous_hash"] != previous["hash"]:
                return False

        return True
