"""
ProTrading Dashboard - FastAPI Application
Enterprise-level trading dashboard with backtesting capabilities
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import logging
import os

from .api.routes import router as api_router
from .api.websocket import websocket_router
from .models.database import init_db
from .services.ml_auto_retrain import AutoRetrainService
from .services.portfolio_risk_service import PortfolioRiskGovernorService
from .services.workbench_copilot_worker import WorkbenchCopilotWorkerService
from .services.agent_watchdog_service import AgentWatchdogService
from .services.telegram_bridge_service import TelegramBridgeService

# Auto-retrain service singleton
auto_retrain_service = AutoRetrainService()
portfolio_risk_service = PortfolioRiskGovernorService()
workbench_copilot_worker = WorkbenchCopilotWorkerService()
agent_watchdog_service = AgentWatchdogService()
telegram_bridge_service = TelegramBridgeService()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

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
        agent_watchdog_service.start()
        logger.info("Agent watchdog service initialized")
    except Exception:
        logger.exception("Agent watchdog service failed to start")

    # Start Telegram bridge (optional, env-gated)
    try:
        telegram_bridge_service.start()
        logger.info("Telegram bridge service initialized")
    except Exception:
        logger.exception("Telegram bridge service failed to start")

    logger.info("Dashboard started successfully")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup resources on shutdown"""
    telegram_bridge_service.stop()
    agent_watchdog_service.stop()
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
    uvicorn.run(
        "dashboard.backend.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )
