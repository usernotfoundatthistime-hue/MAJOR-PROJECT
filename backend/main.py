from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from typing import List
import sqlite3
import re
from datetime import datetime
from zoneinfo import ZoneInfo
import joblib
import json
import os
import hashlib


from blockchain import Blockchain
blockchain = Blockchain()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ================= DATABASE =================

def get_db():
    conn = sqlite3.connect("chat.db")
    conn.row_factory = sqlite3.Row
    return conn

def create_tables():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT
    )
    """)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT,
        receiver TEXT,
        text TEXT,
        timestamp TEXT,
        spam INTEGER DEFAULT 0
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS contacts (
        owner TEXT,
        contact TEXT,
        UNIQUE(owner, contact)
    )
    """)
    conn.commit()
    conn.close()

create_tables()

# ================= MODELS =================

class User(BaseModel):
    username: str
    password: str

class Message(BaseModel):
    sender: str
    receiver: str
    text: str
    scan_text: str = None  

class ContactRequest(BaseModel):
    owner: str
    contact: str

# ================= SECURITY ENGINE (HYBRID AI) =================

SUSPICIOUS_TLDS = [".ru", ".xyz", ".tk", ".cn"]

try:
    ai_model = joblib.load('ai_model.pkl')
    ai_vectorizer = joblib.load('ai_vectorizer.pkl')
    print("✅ AI Model Loaded Successfully")
except Exception as e:
    print(f"⚠️ Warning: AI model not found. Error: {e}")
    ai_model = None

def detect_phishing(text):
    urls = re.findall(r"http[s]?://[^\s]+", text)
    for url in urls:
        if any(tld in url for tld in SUSPICIOUS_TLDS):
            return True
    return False

def detect_spam_ai(text):
    if ai_model is None:
        return False 
    transformed_text = ai_vectorizer.transform([text])
    prediction = ai_model.predict(transformed_text)
    return prediction[0] == 'spam'

# ================= WEBSOCKET MANAGER =================

class ConnectionManager:
    def __init__(self):
        self.active_connections: dict = {}

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket

    def disconnect(self, user_id: str):
        if user_id in self.active_connections:
            del self.active_connections[user_id]

    async def send_message(self, message: dict, user_id: str):
        if user_id in self.active_connections:
            await self.active_connections[user_id].send_json(message)

manager = ConnectionManager()

# ================= ROUTES =================

@app.post("/register")
def register(user: User):
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute("INSERT INTO users (username, password) VALUES (?, ?)", (user.username, user.password))
        conn.commit()
        return {"message": "User registered successfully"}
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Username already exists")
    finally:
        conn.close()

@app.post("/login")
def login(user: User):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE username=? AND password=?", (user.username, user.password))
    result = cursor.fetchone()
    conn.close()
    if result:
        return {"message": "Login successful"}
    raise HTTPException(status_code=400, detail="Invalid credentials")

@app.get("/contacts/{username}")
def get_contacts(username: str):
    conn = get_db()
    cursor = conn.cursor()
    # Only get contacts belonging to this specific user
    cursor.execute("SELECT contact FROM contacts WHERE owner=?", (username,))
    rows = cursor.fetchall()
    conn.close()
    return [row["contact"] for row in rows]

@app.post("/add_contact")
def add_contact(req: ContactRequest):
    conn = get_db()
    cursor = conn.cursor()
    try:
        # Check if the user they are trying to add actually exists in the app!
        cursor.execute("SELECT * FROM users WHERE username=?", (req.contact,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="User not found.")
            
        # Prevent users from adding themselves
        if req.owner == req.contact:
            raise HTTPException(status_code=400, detail="You cannot add yourself.")

        # Save the friendship to the database
        cursor.execute("INSERT INTO contacts (owner, contact) VALUES (?, ?)", (req.owner, req.contact))
        conn.commit()
        return {"message": f"{req.contact} added to your friends list!"}
    except sqlite3.IntegrityError:
         raise HTTPException(status_code=400, detail="This user is already in your contacts.")
    finally:
        conn.close()

@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await manager.connect(user_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(user_id)

@app.post("/send_message")
async def send_message(message: Message):
    spam_flag = 0
    # display_time = datetime.now().strftime("%I:%M %p") 
    display_time = datetime.now(ZoneInfo("Asia/Kolkata")).strftime("%I:%M %p")
    # Tell the AI to scan the plain text, not the encrypted text
    text_to_scan = message.scan_text if message.scan_text else message.text

    # 1. Phishing Detection
    if detect_phishing(text_to_scan):
        # ---> USE YOUR BLOCKCHAIN CLASS HERE <---
        blockchain.add_block("Phishing", {"username": message.sender, "message": text_to_scan})
        
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO messages (sender, receiver, text, timestamp)
            VALUES (?, ?, ?, ?)
        """, ("SYSTEM", message.receiver, f"🚨 Warning: {message.sender} tried to share a suspicious/harmful link. Message blocked.", display_time))
        conn.commit()
        conn.close()
        raise HTTPException(status_code=403, detail="Suspicious link detected.")

    # 2. Spam Detection
    if detect_spam_ai(text_to_scan):
        spam_flag = 1
        # ---> USE YOUR BLOCKCHAIN CLASS HERE <---
        blockchain.add_block("Spam", {"username": message.sender, "message": text_to_scan})


    # 3. Save Message (Saves the ENCRYPTED message.text)
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO messages (sender, receiver, text, timestamp, spam)
        VALUES (?, ?, ?, ?, ?)
    """, (message.sender, message.receiver, message.text, display_time, spam_flag))
    conn.commit()
    conn.close()

    # 4. Push via WebSocket (Pushes the ENCRYPTED text to receiver)
    await manager.send_message({
        "sender": message.sender,
        "text": message.text,
        "timestamp": display_time,
        "spam": bool(spam_flag)
    }, message.receiver)

    response = {"message": "Message sent", "timestamp": display_time}
    if spam_flag:
        response["warning"] = "The link in this message looks suspicious. Open at your own risk."
    
    return response

@app.get("/messages/{user1}/{user2}")
def get_messages(user1: str, user2: str):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT sender, receiver, text, timestamp, spam
        FROM messages
        WHERE (sender=? AND receiver=?) OR (sender=? AND receiver=?)
        ORDER BY id ASC
    """, (user1, user2, user2, user1))
    rows = cursor.fetchall()
    conn.close()

    return [
        {
            "sender": row["sender"],
            "text": row["text"],
            "timestamp": row["timestamp"],
            "spam": bool(row["spam"])
        } for row in rows
    ]

@app.get("/blockchain")
def get_blockchain():
    # Use your class methods to load and verify!
    chain_data = blockchain.load_chain()
    is_valid = blockchain.verify_chain()
    
    return {
        "length": len(chain_data),
        "chain": chain_data,
        "is_valid": is_valid 
    }
@app.get("/profile/{username}")
def get_profile(username: str):
    identity_payload = f"{username}-SAFECHAT-VERIFIED"
    identity_hash = hashlib.sha256(identity_payload.encode()).hexdigest()
    return {
        "username": username,
        "identity_hash": identity_hash,
        "status": "Verified on Blockchain",
        "clearance": "Level 1 (Standard User)"
    }