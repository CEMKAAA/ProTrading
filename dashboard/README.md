# ProTrading Dashboard

Enterprise-level trading dashboard for the ProTradingSystem with comprehensive backtesting capabilities.

## Features

- **Real-time Live Trading Monitor**: Track your trading bot's performance in real-time
- **Advanced Backtesting Engine**: Test your ICT strategy with configurable parameters
- **Performance Analytics**: Detailed metrics including Sharpe ratio, Sortino ratio, max drawdown
- **Trade Visualization**: Interactive equity curves and trade history tables
- **Configuration Management**: Save and load backtest configurations with presets

## Architecture

```
dashboard/
├── backend/                 # FastAPI Backend
│   ├── api/                # REST API routes
│   ├── core/               # Business logic
│   ├── models/             # Database models
│   └── services/           # Background services
├── frontend/               # React + TypeScript Frontend
│   ├── src/
│   │   ├── components/     # Reusable UI components
│   │   ├── pages/          # Page components
│   │   ├── services/       # API client
│   │   └── store/          # Zustand state management
└── docker-compose.yml      # Docker orchestration
```

## Quick Start

### Using Docker (Recommended)

```bash
# Build and start all services
docker-compose up --build

# Access the dashboard
# Frontend: http://localhost:3000
# Backend API: http://localhost:8000/api/docs
```

### Development Mode

```bash
# Using Docker with hot reload
docker-compose -f docker-compose.dev.yml up

# Or run services separately:

# Backend (Terminal 1)
cd backend
pip install -r requirements.txt
uvicorn dashboard.backend.main:app --reload --port 8000

# Frontend (Terminal 2)
cd frontend
npm install
npm run dev
```

## Configuration

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

Key configuration options:
- `DATABASE_URL`: Database connection string
- `VITE_API_URL`: Backend API URL for frontend
- `LOG_LEVEL`: Logging verbosity

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/health` | GET | Health check |
| `/api/v1/configs` | GET/POST | Backtest configurations |
| `/api/v1/backtests` | GET/POST | Backtest results |
| `/api/v1/backtests/{id}` | GET | Single backtest detail |
| `/api/v1/live/status` | GET | Live trading status |
| `/ws/backtest/{id}` | WS | Backtest progress updates |

## Backtest Parameters

All trading strategy parameters are configurable:

### Risk Management
- Risk per trade percentage
- Maximum spread filter
- Daily loss/trade limits

### ICT Strategy Settings
- FVG (Fair Value Gap) detection
- Order Block identification
- Liquidity sweep detection
- Displacement requirements

### Session Times
- Opening Range Breakout (ORB)
- Asian session
- London session
- New York session

### Trailing Stop
- ATR-based trailing
- Breakeven automation

## Technology Stack

**Backend:**
- FastAPI (Python 3.11)
- SQLAlchemy + SQLite
- Pydantic validation
- WebSocket support

**Frontend:**
- React 18
- TypeScript
- TailwindCSS
- Zustand (state management)
- React Query (data fetching)
- Recharts (visualization)

## License

Proprietary - All rights reserved.
