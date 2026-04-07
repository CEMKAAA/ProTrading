"""
ProTrading Dashboard - FastAPI Application
Enterprise-level trading dashboard with backtesting capabilities
"""

import logging
import os
from typing import Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .api.routes import router as api_router
from .api.websocket import websocket_router
from .models.database import init_db
from .services.ml_auto_retrain import AutoRetrainService
from .services.portfolio_risk_service import PortfolioRiskGovernorService
from .services.workbench_copilot_worker import WorkbenchCopilotWorkerService
from .services.agent_live_tick_service import AgentLiveTickService
from .services.agent_watchdog_service import get_agent_watchdog_service
from .services.telegram_bridge_service import TelegramBridgeService
from .services.telegram_user_listener_service import TelegramUserListenerService
from .services.mt4_log_automation_service import MT4LogAutomationService
from .services.youtube_colorflip_service import YouTubeColorFlipService

# Auto-retrain service singleton
auto_retrain_service = AutoRetrainService()
portfolio_risk_service = PortfolioRiskGovernorService()
workbench_copilot_worker = WorkbenchCopilotWorkerService()
agent_watchdog_service: Optional[object] = None
agent_live_tick_service = AgentLiveTickService()
telegram_bridge_service = TelegramBridgeService()
telegram_user_listener_service = TelegramUserListenerService(
    on_message=telegram_bridge_service.ingest_external_channel_message
)


def _on_mt4_indicator_signal(**payload):
    """Forward MT4 indicator signals into execution + unified feed pipeline."""
    try:
        telegram_bridge_service.ingest_mt4_indicator_signal(payload=dict(payload or {}))
    except Exception:
        logger.exception("mt4_indicator_signal_forward_failed")


mt4_log_automation_service = MT4LogAutomationService(on_indicator_signal=_on_mt4_indicator_signal)
youtube_colorflip_service = YouTubeColorFlipService(
    profile="PRIMARY",
    default_url="https://www.youtube.com/watch?v=fFrLWCCUY68",
    default_right_symbol="ETHUSDm",
    default_left_symbol="BTCUSDm",
    default_right_label="ETH",
    default_left_label="BTC",
)
youtube_colorflip_service_forex = YouTubeColorFlipService(
    profile="FOREX",
    default_url="https://www.youtube.com/watch?v=boI9giWyejc",
    default_right_symbol="GBPUSDm",
    default_left_symbol="EURUSDm",
    default_right_label="GBPUSD",
    default_left_label="EURUSD",
)
youtube_colorflip_service_forex2 = YouTubeColorFlipService(
    profile="FOREX2",
    default_url="https://www.youtube.com/watch?v=wsRKTiFqSAk",
    default_right_symbol="AUDUSDm",
    default_left_symbol="USDJPYm",
    default_right_label="AUDUSD",
    default_left_label="USDJPY",
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
# runtime note: notification services are env-gated from dashboard/.env

# Create FastAPI app
app = FastAPI(
    title="ProTrading Dashboard",
    description="Enterprise-level trading dashboard with ICT strategy backtesting",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:5173",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5173",
        "http://localhost:5000",
        "http://127.0.0.1:5000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(api_router, prefix="/api/v1", tags=["API"])
app.include_router(websocket_router, tags=["WebSocket"])

from .api.simulation_routes import router as simulation_router
app.include_router(simulation_router, prefix="/api/v1", tags=["Simulation"])
from .api.trading_simulation_routes import router as trading_simulation_router
app.include_router(trading_simulation_router, prefix="/api/v1", tags=["TradingSimulation"])


@app.on_event("startup")
async def startup_event():
    """Initialize database and other resources on startup"""
    global agent_watchdog_service
    logger.info("Starting ProTrading Dashboard...")

    # Create data directory
    os.makedirs("./dashboard/data", exist_ok=True)

    # Initialize database
    init_db()
    logger.info("Database initialized")

    # Start auto-retrain scheduler
    try:
        auto_retrain_service.start()
        logger.info("Auto-retrain scheduler initialized")
    except Exception:
        logger.exception("Auto-retrain scheduler failed to start")

    # Start portfolio risk governor
    try:
        portfolio_risk_service.start()
        logger.info("Portfolio risk governor initialized")
    except Exception:
        logger.exception("Portfolio risk governor failed to start")

    # Start async copilot worker
    try:
        workbench_copilot_worker.start()
        logger.info("Workbench copilot worker initialized")
    except Exception:
        logger.exception("Workbench copilot worker failed to start")

    # Start deterministic trade watchdog for unified agent
    try:
        agent_watchdog_service = get_agent_watchdog_service()
        agent_watchdog_service.start()
        logger.info("Agent watchdog service initialized")
    except Exception:
        logger.exception("Agent watchdog service failed to start")

    # Start backend-native MT5 live tick relay for trigger execution.
    try:
        agent_live_tick_service.start()
        logger.info("Backend MT5 live tick relay initialized")
    except Exception:
        logger.exception("Backend MT5 live tick relay failed to start")

    # Start Telegram bridge (optional, env-gated)
    try:
        telegram_bridge_service.start()
        logger.info("Telegram bridge service initialized")
    except Exception:
        logger.exception("Telegram bridge service failed to start")
    # Start Telegram user listener (optional, env-gated)
    try:
        telegram_user_listener_service.start()
        logger.info("Telegram user listener service initialized")
    except Exception:
        logger.exception("Telegram user listener service failed to start")
    # Start MT4 log automation listener (optional, env-gated)
    try:
        mt4_log_automation_service.start()
        logger.info("MT4 log automation service initialized")
    except Exception:
        logger.exception("MT4 log automation service failed to start")

    # Start YouTube frame colorflip watcher (optional, env-gated)
    try:
        youtube_colorflip_service.start()
        logger.info("YouTube colorflip service initialized")
    except Exception:
        logger.exception("YouTube colorflip service failed to start")
    try:
        youtube_colorflip_service_forex.start()
        logger.info("YouTube colorflip FOREX service initialized")
    except Exception:
        logger.exception("YouTube colorflip FOREX service failed to start")
    try:
        youtube_colorflip_service_forex2.start()
        logger.info("YouTube colorflip FOREX2 service initialized")
    except Exception:
        logger.exception("YouTube colorflip FOREX2 service failed to start")

    logger.info("Dashboard started successfully")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup resources on shutdown"""
    global agent_watchdog_service
    youtube_colorflip_service_forex2.stop()
    youtube_colorflip_service_forex.stop()
    youtube_colorflip_service.stop()
    mt4_log_automation_service.stop()
    telegram_user_listener_service.stop()
    telegram_bridge_service.stop()
    agent_live_tick_service.stop()
    if agent_watchdog_service is not None:
        agent_watchdog_service.stop()
        agent_watchdog_service = None
    workbench_copilot_worker.stop()
    portfolio_risk_service.stop()
    auto_retrain_service.stop()
    logger.info("Shutting down ProTrading Dashboard...")


@app.get("/")
async def root():
    """Root endpoint - redirect to docs or serve frontend"""
    return {
        "name": "ProTrading Dashboard",
        "version": "1.0.0",
        "docs": "/api/docs",
        "api": "/api/v1"
    }


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


# For production: serve frontend static files
# Uncomment when frontend is built
# frontend_path = os.path.join(os.path.dirname(__file__), "../frontend/dist")
# if os.path.exists(frontend_path):
#     app.mount("/", StaticFiles(directory=frontend_path, html=True), name="frontend")


if __name__ == "__main__":
    import uvicorn
    reload_enabled = str(os.getenv("UVICORN_RELOAD", "0")).strip().lower() in {"1", "true", "yes", "on"}
    uvicorn.run(
        "dashboard.backend.main:app",
        host="0.0.0.0",
        port=8000,
        reload=bool(reload_enabled)
    )
