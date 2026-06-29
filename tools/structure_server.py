#!/usr/bin/env python3
"""
PlantUML 结构展示服务器
- 监听 WebSocket 连接
- 接收 PlantUML 代码
- 渲染为 SVG 并推送回客户端
"""

import asyncio
import json
import base64
import zlib
import urllib.request
import websockets
from http.server import HTTPServer, SimpleHTTPRequestHandler
import threading
import os

PLANTUML_SERVER = "http://www.plantuml.com/plantuml/svg/"

def encode_plantuml(puml_text):
    """Encode PlantUML text for URL (PlantUML's special encoding)"""
    # PlantUML uses a custom encoding: deflate + base64 + custom alphabet
    compressed = zlib.compress(puml_text.encode('utf-8'), 9)[2:-4]  # strip header/trailer
    encoded = base64.b64encode(compressed).decode('ascii')
    # Convert to PlantUML's alphabet
    result = ""
    for c in encoded:
        if c == '+':
            result += '-'
        elif c == '/':
            result += '_'
        elif c == '=':
            result += '.'
        else:
            result += c
    return result

def render_plantuml(puml_text):
    """Render PlantUML to SVG using online server"""
    encoded = encode_plantuml(puml_text)
    url = PLANTUML_SERVER + encoded
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read().decode('utf-8')
    except Exception as e:
        return f'<svg><text x="10" y="20">Error: {e}</text></svg>'

# WebSocket 处理
connected_clients = set()

async def ws_handler(websocket, path):
    connected_clients.add(websocket)
    print(f"Client connected: {websocket.remote_address}")
    try:
        async for message in websocket:
            data = json.loads(message)
            if data.get('type') == 'plantuml':
                puml = data.get('content', '')
                svg = render_plantuml(puml)
                await websocket.send(json.dumps({'type': 'svg', 'content': svg}))
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        connected_clients.discard(websocket)
        print(f"Client disconnected")

async def broadcast_update(puml_text):
    """Broadcast PlantUML update to all clients"""
    svg = render_plantuml(puml_text)
    message = json.dumps({'type': 'update', 'content': svg, 'puml': puml_text})
    for client in connected_clients:
        try:
            await client.send(message)
        except:
            pass

# HTTP 端点用于 Vim 推送
class HttpHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, loop=None, **kwargs):
        self.loop = loop
        super().__init__(*args, directory=os.path.dirname(os.path.abspath(__file__)), **kwargs)

    def do_POST(self):
        if self.path == '/update':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            data = json.loads(body)
            puml = data.get('puml', '')
            
            # 广播更新
            if self.loop and connected_clients:
                asyncio.run_coroutine_threadsafe(broadcast_update(puml), self.loop)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok'}).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run_http_server(loop):
    """Run HTTP server in thread"""
    handler = lambda *args: HttpHandler(*args, loop=loop)
    server = HTTPServer(('localhost', 8765), handler)
    print(f"HTTP server running on http://localhost:8765")
    server.serve_forever()

def run_ws_server():
    """Run WebSocket server"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    
    # 启动 HTTP 服务器线程
    http_thread = threading.Thread(target=run_http_server, args=(loop,), daemon=True)
    http_thread.start()
    
    # 启动 WebSocket 服务器
    ws_server = websockets.serve(ws_handler, 'localhost', 8766)
    print(f"WebSocket server running on ws://localhost:8766")
    
    loop.run_until_complete(ws_server)
    loop.run_forever()

if __name__ == '__main__':
    print("Starting PlantUML Structure Server...")
    print("Open http://localhost:8765/structure.html in your browser")
    run_ws_server()