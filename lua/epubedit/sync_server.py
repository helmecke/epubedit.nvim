#!/usr/bin/env python3
"""
EpubEdit Browser Sync Server
Extends Python's http.server with Server-Sent Events for live reload.
"""

import http.server
import socketserver
import json
import threading
import queue
import sys
from pathlib import Path
from urllib.parse import urlparse, unquote

# Queue for broadcasting reload events to SSE clients
reload_queue = queue.Queue()
sse_clients = []
sse_clients_lock = threading.Lock()


class SyncHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler with SSE support and HTML injection"""

    def __init__(self, *args, directory=None, **kwargs):
        self.sync_client_script = self._load_sync_client()
        super().__init__(*args, directory=directory, **kwargs)

    def _load_sync_client(self):
        script_path = Path(__file__).parent / "sync_client.js"
        try:
            with open(script_path, "r") as f:
                return f.read()
        except FileNotFoundError:
            return """
(function() {
    const eventSource = new EventSource('/__epubedit_sync__');
    eventSource.onmessage = function(e) {
        if (e.data === 'reload') {
            console.log('[EpubEdit] Reloading page...');
            window.location.reload();
        }
    };
    eventSource.onerror = function() {
        console.log('[EpubEdit] Sync connection lost, reconnecting...');
    };
    console.log('[EpubEdit] Browser sync active');
})();
"""

    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = unquote(parsed_path.path)

        if path == "/__epubedit_sync__":
            self.handle_sse()
        elif path == "/__epubedit_sync_client__.js":
            self.serve_sync_client_js()
        else:
            self.serve_with_injection()

    def do_POST(self):
        parsed_path = urlparse(self.path)
        path = unquote(parsed_path.path)

        if path == "/__epubedit_reload__":
            self.handle_reload_trigger()
        else:
            self.send_error(404, "Not Found")

    def serve_sync_client_js(self):
        """Serve the sync client JavaScript as an external file"""
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(self.sync_client_script.encode("utf-8"))

    def handle_sse(self):
        """Server-Sent Events endpoint for browser clients"""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        client_queue = queue.Queue()

        with sse_clients_lock:
            sse_clients.append(client_queue)

        try:
            self.wfile.write(b": connected\n\n")
            self.wfile.flush()

            while True:
                try:
                    message = client_queue.get(timeout=30)
                    data = f"data: {message}\n\n".encode("utf-8")
                    self.wfile.write(data)
                    self.wfile.flush()
                except queue.Empty:
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with sse_clients_lock:
                if client_queue in sse_clients:
                    sse_clients.remove(client_queue)

    def handle_reload_trigger(self):
        """Handle POST request to trigger reload"""
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length > 0:
                body = self.rfile.read(content_length)
                data = json.loads(body.decode("utf-8"))
                filepath = data.get("file", "")
            else:
                filepath = ""

            with sse_clients_lock:
                for client_queue in sse_clients:
                    try:
                        client_queue.put_nowait("reload")
                    except queue.Full:
                        pass

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            response = json.dumps({"status": "ok", "clients": len(sse_clients)})
            self.wfile.write(response.encode("utf-8"))
        except Exception as e:
            self.send_error(500, f"Internal Server Error: {str(e)}")

    def serve_with_injection(self):
        """Serve file with sync client injection for HTML files"""
        path = self.translate_path(self.path)

        try:
            with open(path, "rb") as f:
                content = f.read()

            is_html = path.lower().endswith((".html", ".xhtml", ".htm"))

            if is_html:
                try:
                    html_content = content.decode("utf-8")

                    # Use external script to avoid XHTML strict parsing issues
                    inject_script = '<script src="/__epubedit_sync_client__.js"></script>'

                    if "</body>" in html_content:
                        html_content = html_content.replace(
                            "</body>", f"{inject_script}</body>", 1
                        )
                    elif "</html>" in html_content:
                        html_content = html_content.replace(
                            "</html>", f"{inject_script}</html>", 1
                        )
                    else:
                        html_content += inject_script

                    content = html_content.encode("utf-8")
                except (UnicodeDecodeError, AttributeError):
                    pass

            self.send_response(200)
            if is_html:
                # Serve XHTML as application/xhtml+xml for proper namespace support (epub:type, etc.)
                self.send_header("Content-Type", "application/xhtml+xml; charset=utf-8")
            else:
                self.guess_type(path)
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        except FileNotFoundError:
            self.send_error(404, "File not found")
        except Exception as e:
            self.send_error(500, f"Internal Server Error: {str(e)}")

    def log_message(self, format, *args):
        pass


def run_server(port, directory):
    """Start the sync-enabled HTTP server"""
    handler = lambda *args, **kwargs: SyncHTTPRequestHandler(
        *args, directory=directory, **kwargs
    )

    # Use ThreadingTCPServer to handle multiple connections simultaneously
    # This is essential for SSE which keeps a long-lived connection open
    class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
        daemon_threads = True
        allow_reuse_address = True

    with ThreadedTCPServer(("127.0.0.1", port), handler) as httpd:
        print(f"EpubEdit sync server running on port {port}", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped", flush=True)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: sync_server.py <port> <directory>", file=sys.stderr)
        sys.exit(1)

    port = int(sys.argv[1])
    directory = sys.argv[2]

    run_server(port, directory)
