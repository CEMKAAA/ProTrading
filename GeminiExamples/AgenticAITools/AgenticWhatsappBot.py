"""
Agentic WhatsApp Chatbot for Company
====================================
This chatbot uses the same architecture as chatBotThatActsLikeYouOllama.ipynb 
and AlterEgoOllama.ipynb but adapted for WhatsApp integration.

Uses:
- Ollama (llama3.2) for LLM
- Flask for webhook handling
- Twilio for WhatsApp API
- pypdf for PDF knowledge extraction (RAG placeholder)
- Pushover for notifications
"""

import os
import json
import requests
import threading
from dotenv import load_dotenv
from flask import Flask, request
from twilio.twiml.messaging_response import MessagingResponse
from twilio.rest import Client
from openai import OpenAI
from pypdf import PdfReader
from datetime import datetime

# ============================================================================
# CONFIGURATION
# ============================================================================

# Load environment variables
env_path = r"C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\.env"
load_dotenv(env_path)

# Ollama configuration
ollama = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
MODEL_NAME = "llama3.2"

# Twilio configuration
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN")
TWILIO_WHATSAPP_NUMBER = os.getenv("TWILIO_WHATSAPP_NUMBER")  # Format: whatsapp:+14155238886

# Pushover configuration (for notifications)
PUSHOVER_USER = os.getenv("PUSHOVER_USER")
PUSHOVER_TOKEN = os.getenv("PUSHOVER_TOKEN")
PUSHOVER_URL = "https://api.pushover.net/1/messages.json"

# Company configuration
COMPANY_NAME = "LİBAL MAKİNA"
COMPANY_EMAIL = "info@libalmakina.com"
COMPANY_PHONE = "+90 XXX XXX XXXX"

# Flask app
app = Flask(__name__)

# Conversation history storage (in production, use Redis or database)
conversation_histories = {}

# ============================================================================
# KNOWLEDGE BASE - PDF EXTRACTION
# ============================================================================

def load_knowledge_base():
    """Load knowledge from PDF file using pypdf"""
    try:
        pdf_path = os.path.join(os.path.dirname(__file__), "resources", "cemBerk.pdf")
        reader = PdfReader(pdf_path)
        knowledge = ""
        
        for page in reader.pages:
            text = page.extract_text()
            if text:
                knowledge += text
        
        return knowledge
    except Exception as e:
        print(f"Error loading PDF: {e}")
        return ""

def load_summary():
    """Load summary text file"""
    try:
        summary_path = os.path.join(os.path.dirname(__file__), "resources", "me.txt")
        with open(summary_path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        print(f"Error loading summary: {e}")
        return ""

# Load knowledge base at startup
KNOWLEDGE_BASE = load_knowledge_base()
SUMMARY = load_summary()

# ============================================================================
# NOTIFICATION SYSTEM
# ============================================================================

def push_notification(message):
    """Send push notification via Pushover"""
    print(f"[NOTIFICATION] {message}")
    
    if PUSHOVER_USER and PUSHOVER_TOKEN:
        try:
            payload = {
                "user": PUSHOVER_USER,
                "token": PUSHOVER_TOKEN,
                "message": message,
                "title": f"{COMPANY_NAME} WhatsApp Bot"
            }
            requests.post(PUSHOVER_URL, data=payload)
        except Exception as e:
            print(f"Error sending push notification: {e}")

# ============================================================================
# TOOL FUNCTIONS
# ============================================================================

def record_customer_inquiry(phone_number, inquiry_type, details="Not provided"):
    """Record customer inquiry for follow-up"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    push_notification(f"📋 New Inquiry\nPhone: {phone_number}\nType: {inquiry_type}\nDetails: {details}\nTime: {timestamp}")
    return {"recorded": "ok", "message": "Your inquiry has been recorded. Our team will contact you soon."}

def schedule_callback(phone_number, preferred_time, name="Not provided"):
    """Schedule a callback request"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    push_notification(f"📞 Callback Request\nName: {name}\nPhone: {phone_number}\nPreferred Time: {preferred_time}\nRequested at: {timestamp}")
    return {"scheduled": "ok", "message": f"Callback scheduled for {preferred_time}. We'll call you back!"}

def get_business_hours():
    """Return business hours information"""
    return {
        "hours": {
            "monday_friday": "09:00 - 18:00",
            "saturday": "09:00 - 14:00",
            "sunday": "Closed"
        },
        "message": "We're open Monday-Friday 9AM-6PM, Saturday 9AM-2PM. Closed on Sundays."
    }

def get_contact_info():
    """Return company contact information"""
    return {
        "company": COMPANY_NAME,
        "email": COMPANY_EMAIL,
        "phone": COMPANY_PHONE,
        "location": "İzmir, Türkiye",
        "message": f"You can reach us at {COMPANY_EMAIL} or call {COMPANY_PHONE}"
    }

def record_unknown_question(question, phone_number):
    """Record questions that couldn't be answered"""
    push_notification(f"❓ Unknown Question\nFrom: {phone_number}\nQuestion: {question}")
    return {"recorded": "ok"}

def request_human_agent(phone_number, reason="General inquiry"):
    """Request transfer to human agent"""
    push_notification(f"🧑‍💼 Human Agent Requested\nPhone: {phone_number}\nReason: {reason}")
    return {"requested": "ok", "message": "A human agent will contact you shortly. Thank you for your patience!"}

def get_service_info(service_type):
    """Get information about company services"""
    # This is a placeholder - in production, fetch from database
    services = {
        "general": "We provide industrial machinery solutions and AI engineering services.",
        "machinery": "Our machinery solutions include custom industrial equipment and automation systems.",
        "ai": "We offer AI engineering services including computer vision, NLP, and predictive maintenance.",
        "support": "24/7 technical support available for all our products and services."
    }
    return {"info": services.get(service_type.lower(), services["general"])}

# ============================================================================
# TOOL DEFINITIONS (JSON Schema for LLM)
# ============================================================================

tools = [
    {
        "type": "function",
        "function": {
            "name": "record_customer_inquiry",
            "description": "Record a customer inquiry when they express interest in products/services or want to be contacted",
            "parameters": {
                "type": "object",
                "properties": {
                    "phone_number": {
                        "type": "string",
                        "description": "Customer's phone number"
                    },
                    "inquiry_type": {
                        "type": "string",
                        "description": "Type of inquiry: product, service, pricing, support, or other"
                    },
                    "details": {
                        "type": "string",
                        "description": "Additional details about the inquiry"
                    }
                },
                "required": ["phone_number", "inquiry_type"],
                "additionalProperties": False
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "schedule_callback",
            "description": "Schedule a callback when customer wants to be called back at a specific time",
            "parameters": {
                "type": "object",
                "properties": {
                    "phone_number": {
                        "type": "string",
                        "description": "Customer's phone number for callback"
                    },
                    "preferred_time": {
                        "type": "string",
                        "description": "Customer's preferred callback time"
                    },
                    "name": {
                        "type": "string",
                        "description": "Customer's name if provided"
                    }
                },
                "required": ["phone_number", "preferred_time"],
                "additionalProperties": False
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_business_hours",
            "description": "Get the company's business hours when customer asks about working hours or when the company is open",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
                "additionalProperties": False
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_contact_info",
            "description": "Get company contact information when customer asks for email, phone, or how to reach the company",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
                "additionalProperties": False
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "record_unknown_question",
            "description": "Record any question that cannot be answered from available knowledge",
            "parameters": {
                "type": "object",
                "properties": {
                    "question": {
                        "type": "string",
                        "description": "The question that couldn't be answered"
                    },
                    "phone_number": {
                        "type": "string",
                        "description": "Customer's phone number"
                    }
                },
                "required": ["question", "phone_number"],
                "additionalProperties": False
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "request_human_agent",
            "description": "Transfer to human agent when customer explicitly requests to speak with a person or has complex issues",
            "parameters": {
                "type": "object",
                "properties": {
                    "phone_number": {
                        "type": "string",
                        "description": "Customer's phone number"
                    },
                    "reason": {
                        "type": "string",
                        "description": "Reason for requesting human agent"
                    }
                },
                "required": ["phone_number"],
                "additionalProperties": False
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_service_info",
            "description": "Get information about company services: general, machinery, ai, or support",
            "parameters": {
                "type": "object",
                "properties": {
                    "service_type": {
                        "type": "string",
                        "description": "Type of service: general, machinery, ai, or support"
                    }
                },
                "required": ["service_type"],
                "additionalProperties": False
            }
        }
    }
]

# ============================================================================
# TOOL HANDLER
# ============================================================================

def handle_tool_calls(tool_calls, phone_number):
    """Handle tool calls from LLM response"""
    results = []
    
    for tool_call in tool_calls:
        tool_name = tool_call.function.name
        arguments = json.loads(tool_call.function.arguments)
        
        print(f"[TOOL CALLED] {tool_name} with args: {arguments}")
        
        # Add phone_number to arguments if needed
        if "phone_number" in [p for p in arguments.keys()] or tool_name in ["record_customer_inquiry", "schedule_callback", "record_unknown_question", "request_human_agent"]:
            if "phone_number" not in arguments:
                arguments["phone_number"] = phone_number
        
        # Get the function and call it
        tool_function = globals().get(tool_name)
        if tool_function:
            result = tool_function(**arguments)
        else:
            result = {"error": f"Tool {tool_name} not found"}
        
        results.append({
            "role": "tool",
            "content": json.dumps(result),
            "tool_call_id": tool_call.id
        })
    
    return results

# ============================================================================
# SYSTEM PROMPT
# ============================================================================

def get_system_prompt():
    """Generate system prompt with knowledge base"""
    
    system_prompt = f"""You are a friendly and professional WhatsApp customer service assistant for {COMPANY_NAME}.
Your role is to help customers with their inquiries about our products, services, and company information.

## Your Responsibilities:
1. Answer customer questions professionally and helpfully
2. Use available tools to record inquiries, schedule callbacks, and get information
3. If you cannot answer a question, use the record_unknown_question tool
4. Guide customers to contact us or schedule callbacks when appropriate
5. Be conversational but professional - this is WhatsApp, so keep responses concise

## Available Tools:
- record_customer_inquiry: When customer wants to be contacted or shows interest
- schedule_callback: When customer wants a callback at specific time
- get_business_hours: When asked about working hours
- get_contact_info: When asked for contact details
- record_unknown_question: When you can't answer something
- request_human_agent: When customer wants to speak with a person
- get_service_info: When asked about our services

## Company Knowledge Base:
{KNOWLEDGE_BASE}

## Additional Context:
{SUMMARY}

## Guidelines:
- Keep responses concise (WhatsApp style)
- Use emojis sparingly but appropriately 
- Always be helpful and guide to solutions
- If unsure, offer to connect with human agent
- Respond in the same language the customer uses

Remember: You represent {COMPANY_NAME}. Be professional, helpful, and friendly!"""

    return system_prompt

# ============================================================================
# CHAT FUNCTION
# ============================================================================

def chat(message, phone_number):
    """Process incoming message and generate response using Ollama"""
    
    # Get or create conversation history for this user
    if phone_number not in conversation_histories:
        conversation_histories[phone_number] = []
    
    history = conversation_histories[phone_number]
    
    # Build messages array
    messages = [
        {"role": "system", "content": get_system_prompt()}
    ] + history + [
        {"role": "user", "content": message}
    ]
    
    # Agentic loop - keep processing until done
    done = False
    max_iterations = 5  # Prevent infinite loops
    iteration = 0
    
    while not done and iteration < max_iterations:
        iteration += 1
        
        try:
            response = ollama.chat.completions.create(
                model=MODEL_NAME,
                messages=messages,
                tools=tools
            )
            
            finish_reason = response.choices[0].finish_reason
            
            if finish_reason == "tool_calls":
                # LLM wants to call tools
                assistant_message = response.choices[0].message
                tool_calls = assistant_message.tool_calls
                
                # Handle tool calls
                tool_results = handle_tool_calls(tool_calls, phone_number)
                
                # Add to messages for next iteration
                messages.append(assistant_message)
                messages.extend(tool_results)
            else:
                # LLM is done, get final response
                done = True
                
        except Exception as e:
            print(f"Error in chat: {e}")
            return "I apologize, but I'm having technical difficulties. Please try again or contact us directly."
    
    # Get the final response
    final_response = response.choices[0].message.content
    
    # Update conversation history (keep last 10 exchanges)
    history.append({"role": "user", "content": message})
    history.append({"role": "assistant", "content": final_response})
    conversation_histories[phone_number] = history[-20:]  # Keep last 20 messages
    
    return final_response

# ============================================================================
# TWILIO MESSAGE SENDER
# ============================================================================

def send_whatsapp_message(to_number, message_body):
    """Send a WhatsApp message using Twilio REST API"""
    if not TWILIO_ACCOUNT_SID or not TWILIO_AUTH_TOKEN:
        print("[ERROR] Twilio credentials not configured!")
        return False
    
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        
        message = client.messages.create(
            body=message_body,
            from_=TWILIO_WHATSAPP_NUMBER,
            to=to_number
        )
        
        print(f"[SENT] Message SID: {message.sid}")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to send message: {e}")
        return False

def process_message_async(incoming_msg, from_number):
    """Process message in background thread and send response via Twilio API"""
    try:
        # Generate response using our agentic chat
        response_text = chat(incoming_msg, from_number)
        
        print(f"[OUTGOING] To: {from_number}, Response: {response_text}")
        
        # Send response via Twilio REST API
        send_whatsapp_message(from_number, response_text)
        
    except Exception as e:
        print(f"[ERROR] Async processing failed: {e}")
        # Send error message to user
        send_whatsapp_message(from_number, "Üzgünüm, bir hata oluştu. Lütfen tekrar deneyin.")

# ============================================================================
# FLASK WEBHOOK ENDPOINTS
# ============================================================================

@app.route("/webhook", methods=["POST"])
def webhook():
    """Handle incoming WhatsApp messages via Twilio webhook"""
    
    # Get message details from Twilio
    incoming_msg = request.values.get("Body", "").strip()
    from_number = request.values.get("From", "")
    
    print(f"[INCOMING] From: {from_number}, Message: {incoming_msg}")
    
    # Process message asynchronously to avoid Twilio timeout
    thread = threading.Thread(
        target=process_message_async,
        args=(incoming_msg, from_number)
    )
    thread.start()
    
    # Return empty response immediately (Twilio expects 200 OK)
    # The actual response will be sent via Twilio REST API
    return "", 200

@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return {"status": "healthy", "model": MODEL_NAME, "company": COMPANY_NAME}

@app.route("/send", methods=["POST"])
def send_message():
    """Endpoint to proactively send messages (for notifications, follow-ups, etc.)"""
    
    if not TWILIO_ACCOUNT_SID or not TWILIO_AUTH_TOKEN:
        return {"error": "Twilio credentials not configured"}, 500
    
    data = request.json
    to_number = data.get("to")
    message_body = data.get("message")
    
    if not to_number or not message_body:
        return {"error": "Missing 'to' or 'message' in request"}, 400
    
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        
        message = client.messages.create(
            body=message_body,
            from_=TWILIO_WHATSAPP_NUMBER,
            to=f"whatsapp:{to_number}" if not to_number.startswith("whatsapp:") else to_number
        )
        
        return {"success": True, "message_sid": message.sid}
    except Exception as e:
        return {"error": str(e)}, 500

# ============================================================================
# LOCAL TESTING (without Twilio)
# ============================================================================

def test_chat():
    """Test the chat function locally without WhatsApp"""
    print(f"\n{'='*60}")
    print(f"  {COMPANY_NAME} WhatsApp Bot - Local Test Mode")
    print(f"{'='*60}")
    print("Type 'quit' to exit\n")
    
    test_phone = "whatsapp:+901234567890"
    
    while True:
        user_input = input("You: ").strip()
        
        if user_input.lower() in ["quit", "exit", "q"]:
            print("Goodbye!")
            break
        
        if not user_input:
            continue
        
        response = chat(user_input, test_phone)
        print(f"Bot: {response}\n")

# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "test":
        # Run in test mode (local chat without WhatsApp)
        test_chat()
    else:
        # Run Flask server for WhatsApp webhook
        print(f"\n{'='*60}")
        print(f"  {COMPANY_NAME} WhatsApp Bot - Server Mode")
        print(f"{'='*60}")
        print(f"Model: {MODEL_NAME}")
        print(f"Webhook URL: http://localhost:5000/webhook")
        print(f"Health Check: http://localhost:5000/health")
        print(f"{'='*60}\n")
        
        # Note: In production, use gunicorn or similar WSGI server
        # gunicorn -w 4 -b 0.0.0.0:5000 AgenticWhatsappBot:app
        app.run(host="0.0.0.0", port=5000, debug=True)

