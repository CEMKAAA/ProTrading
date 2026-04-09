"""
WebSocket endpoints for real-time updates
"""

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from typing import List, Dict, Any
import asyncio
import json
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

websocket_router = APIRouter()


class ConnectionManager:
    """Manages WebSocket connections for real-time updates"""

    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self.backtest_subscribers: Dict[int, List[WebSocket]] = {}
        self.mt4la_subscribers: Dict[WebSocket, Dict[str, Any]] = {}
        self._loop: asyncio.AbstractEventLoop | None = None

    async def connect(self, websocket: WebSocket):
        """Accept a new WebSocket connection"""
        await websocket.accept()
        if self._loop is None:
            try:
                self._loop = asyncio.get_running_loop()
            except Exception:
                self._loop = None
        self.active_connections.append(websocket)
        logger.info(f"WebSocket connected. Total connections: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        """Remove a WebSocket connection"""
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

        # Remove from all subscriptions
        for result_id in list(self.backtest_subscribers.keys()):
            if websocket in self.backtest_subscribers[result_id]:
                self.backtest_subscribers[result_id].remove(websocket)
                if not self.backtest_subscribers[result_id]:
                    del self.backtest_subscribers[result_id]
        if websocket in self.mt4la_subscribers:
            self.mt4la_subscribers.pop(websocket, None)

        logger.info(f"WebSocket disconnected. Total connections: {len(self.active_connections)}")

    async def send_personal_message(self, message: Dict[str, Any], websocket: WebSocket):
        """Send a message to a specific connection"""
        try:
            await websocket.send_json(message)
        except Exception as e:
            logger.error(f"Error sending message: {e}")
            self.disconnect(websocket)

    async def broadcast(self, message: Dict[str, Any]):
        """Broadcast a message to all connected clients"""
        disconnected = []
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception as e:
                logger.error(f"Error broadcasting to connection: {e}")
                disconnected.append(connection)

        # Clean up disconnected clients
        for conn in disconnected:
            self.disconnect(conn)

    def subscribe_to_backtest(self, result_id: int, websocket: WebSocket):
        """Subscribe to updates for a specific backtest"""
        if result_id not in self.backtest_subscribers:
            self.backtest_subscribers[result_id] = []
        if websocket not in self.backtest_subscribers[result_id]:
            self.backtest_subscribers[result_id].append(websocket)
            logger.info(f"Subscribed to backtest {result_id}")

    async def send_backtest_update(self, result_id: int, message: Dict[str, Any]):
        """Send update to all subscribers of a specific backtest"""
        if result_id not in self.backtest_subscribers:
            return

        disconnected = []
        for websocket in self.backtest_subscribers[result_id]:
            try:
                await websocket.send_json(message)
            except Exception as e:
                logger.error(f"Error sending backtest update: {e}")
                disconnected.append(websocket)

        for conn in disconnected:
            self.disconnect(conn)

    def subscribe_mt4la(self, websocket: WebSocket, chart_group: str = "all", instance_key: str = "all"):
        cg = str(chart_group or "all").strip().lower() or "all"
        ik = str(instance_key or "all").strip().lower() or "all"
        self.mt4la_subscribers[websocket] = {"chart_group": cg, "instance_key": ik}

    def _matches_mt4la_filter(self, event: Dict[str, Any], sub: Dict[str, Any]) -> bool:
        ev = event if isinstance(event, dict) else {}
        cg = str((sub or {}).get("chart_group") or "all").strip().lower()
        ik = str((sub or {}).get("instance_key") or "all").strip().lower()
        if cg not in {"", "all"}:
            ev_group = str(ev.get("terminal_group") or "").strip().lower()
            if ev_group != cg:
                return False
        if ik not in {"", "all"}:
            ev_ik = str(ev.get("instance_key") or "").strip().lower()
            if ev_ik != ik:
                return False
        return True

    async def send_mt4la_event(self, event: Dict[str, Any]):
        if not self.mt4la_subscribers:
            return
        payload = {
            "type": "mt4la_alert_event",
            "event": dict(event or {}),
            "timestamp": datetime.utcnow().isoformat(),
        }
        disconnected: List[WebSocket] = []
        for websocket, sub in list(self.mt4la_subscribers.items()):
            if not self._matches_mt4la_filter(payload.get("event") or {}, sub):
                continue
            try:
                await websocket.send_json(payload)
            except Exception as e:
                logger.error(f"Error sending mt4la event: {e}")
                disconnected.append(websocket)
        for conn in disconnected:
            self.disconnect(conn)

    def publish_mt4la_event_from_thread(self, event: Dict[str, Any]) -> None:
        loop = self._loop
        if loop is None:
            return
        try:
            asyncio.run_coroutine_threadsafe(self.send_mt4la_event(event), loop)
        except Exception as e:
            logger.error(f"Failed to schedule mt4la event from thread: {e}")


# Global connection manager
manager = ConnectionManager()


@websocket_router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Main WebSocket endpoint for general updates"""
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_json()

            # Handle different message types
            message_type = data.get("type")

            if message_type == "ping":
                await manager.send_personal_message(
                    {"type": "pong", "timestamp": datetime.utcnow().isoformat()},
                    websocket
                )

            elif message_type == "subscribe_backtest":
                result_id = data.get("result_id")
                if result_id:
                    manager.subscribe_to_backtest(result_id, websocket)
                    await manager.send_personal_message(
                        {"type": "subscribed", "result_id": result_id},
                        websocket
                    )

            elif message_type == "unsubscribe_backtest":
                result_id = data.get("result_id")
                if result_id and result_id in manager.backtest_subscribers:
                    if websocket in manager.backtest_subscribers[result_id]:
                        manager.backtest_subscribers[result_id].remove(websocket)

    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        manager.disconnect(websocket)


@websocket_router.websocket("/ws/backtest/{result_id}")
async def backtest_websocket(websocket: WebSocket, result_id: int):
    """WebSocket endpoint for specific backtest updates"""
    await manager.connect(websocket)
    manager.subscribe_to_backtest(result_id, websocket)

    try:
        while True:
            data = await websocket.receive_json()

            if data.get("type") == "ping":
                await manager.send_personal_message(
                    {"type": "pong", "timestamp": datetime.utcnow().isoformat()},
                    websocket
                )

    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"Backtest WebSocket error: {e}")
        manager.disconnect(websocket)


@websocket_router.websocket("/ws/live")
async def live_trading_websocket(websocket: WebSocket):
    """WebSocket endpoint for live trading updates"""
    await manager.connect(websocket)

    try:
        # Start sending live updates
        while True:
            # Check for incoming messages
            try:
                data = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=1.0
                )

                if data.get("type") == "ping":
                    await manager.send_personal_message(
                        {"type": "pong", "timestamp": datetime.utcnow().isoformat()},
                        websocket
                    )

            except asyncio.TimeoutError:
                # No message received, continue sending updates
                pass

            # Send live status update every second
            await manager.send_personal_message(
                {
                    "type": "live_update",
                    "timestamp": datetime.utcnow().isoformat(),
                    # Add more live data here when integrated with MT5
                },
                websocket
            )

            await asyncio.sleep(1)

    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"Live trading WebSocket error: {e}")
        manager.disconnect(websocket)


@websocket_router.websocket("/ws/mt4-log-automation")
async def mt4_log_automation_websocket(websocket: WebSocket):
    """WebSocket endpoint for MT4/MT5 log automation alert stream."""
    await manager.connect(websocket)
    manager.subscribe_mt4la(websocket, chart_group="all", instance_key="all")
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = str((data or {}).get("type") or "").strip().lower()
            if msg_type == "ping":
                await manager.send_personal_message(
                    {"type": "pong", "timestamp": datetime.utcnow().isoformat()},
                    websocket,
                )
                continue
            if msg_type == "set_filter":
                chart_group = str((data or {}).get("chart_group") or "all")
                instance_key = str((data or {}).get("instance_key") or "all")
                manager.subscribe_mt4la(websocket, chart_group=chart_group, instance_key=instance_key)
                await manager.send_personal_message(
                    {
                        "type": "filter_applied",
                        "chart_group": str(chart_group).strip().lower() or "all",
                        "instance_key": str(instance_key).strip().lower() or "all",
                        "timestamp": datetime.utcnow().isoformat(),
                    },
                    websocket,
                )
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"MT4 log automation WebSocket error: {e}")
        manager.disconnect(websocket)


# Helper functions for sending updates from services

async def send_backtest_progress(result_id: int, progress: float, message: str):
    """Send backtest progress update to subscribers"""
    await manager.send_backtest_update(result_id, {
        "type": "backtest_progress",
        "result_id": result_id,
        "progress": progress,
        "message": message,
        "timestamp": datetime.utcnow().isoformat()
    })


async def send_backtest_completed(result_id: int, status: str, summary: Dict[str, Any]):
    """Send backtest completion notification"""
    await manager.send_backtest_update(result_id, {
        "type": "backtest_completed",
        "result_id": result_id,
        "status": status,
        "summary": summary,
        "timestamp": datetime.utcnow().isoformat()
    })


async def send_trade_notification(trade_data: Dict[str, Any]):
    """Broadcast a trade notification to all connected clients"""
    await manager.broadcast({
        "type": "trade_notification",
        "data": trade_data,
        "timestamp": datetime.utcnow().isoformat()
    })


async def send_live_status_update(status_data: Dict[str, Any]):
    """Broadcast live status update"""
    await manager.broadcast({
        "type": "live_status",
        "data": status_data,
        "timestamp": datetime.utcnow().isoformat()
    })


def publish_mt4la_alert_event(event_data: Dict[str, Any]):
    """Thread-safe publish helper for MT4/MT5 log automation alert events."""
    manager.publish_mt4la_event_from_thread(dict(event_data or {}))
