import sqlite3

conn = sqlite3.connect("chat.db")
cursor = conn.cursor()
cursor.execute("SELECT sender, receiver, text, spam FROM messages ORDER BY id DESC LIMIT 5")

print("\n=== LATEST 5 MESSAGES IN DATABASE ===")
for row in cursor.fetchall():
    print(f"From: {row[0]} | To: {row[1]} | Spam: {row[3]}")
    print(f"Encrypted Payload: {row[2]}\n")

conn.close()