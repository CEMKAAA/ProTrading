# Options Edge Phase 5: Position Sizing, Trade Journal, Early Close & Backtest Enhancements

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add position sizing calculator, options trade journal, early close visualization, and expose hidden backtest parameters to make the Options Edge module production-ready for semi-automated trading.

**Architecture:** Four additions to the existing Options Edge module. All use the existing SQLAlchemy models, FastAPI routes, and Flask/Jinja2 frontend. New DB table for trade journal. Position sizing is a pure calculation (no DB). Early close params are already in the backtest engine (`take_profit_frac`, `stop_loss_credit_mult`) but hidden from UI. Backtest detail page gets equity curve chart + trade log table.

**Tech Stack:** Python 3.12, FastAPI, Flask/Jinja2, SQLAlchemy, Bootstrap 5, Chart.js (CDN)

---

## Task 1: Position Sizing Calculator

Adds a calculator card to the scan detail page. User enters account balance + risk per trade %, system calculates max contracts for each built trade.

**Files:**
- Modify: `dashboard/backend/api/routes.py` (add `/options-edge/position-size` endpoint)
- Modify: `dashboard/backend/models/schemas.py` (add request/response schemas)
- Modify: `dashboard/frontend/templates/options_edge_scan_detail.html` (add calculator card)
- Modify: `dashboard/frontend/app.py` (add Flask proxy route)
- Test: `tests/test_options_edge_position_sizing.py`

### Step 1: Write failing test

```python
# tests/test_options_edge_position_sizing.py
def test_position_sizing_basic():
    """Account $10,000, risk 2% = $200 max loss per trade.
    Trade max_loss=$315 -> floor(200/315)=0 contracts (skip).
    Trade max_loss=$150 -> floor(200/150)=1 contract."""
    from dashboard.backend.api.routes import _calculate_position_size
    result = _calculate_position_size(
        account_balance=10_000.0,
        risk_pct=2.0,
        max_loss_per_contract=315.0,
        commission_per_leg=0.65,
        legs_count=2,
    )
    assert result["max_contracts"] == 0  # 200/315 = 0.63 -> floor = 0
    assert result["skip_reason"] == "max_loss_exceeds_risk_budget"

def test_position_sizing_multiple_contracts():
    result = _calculate_position_size(
        account_balance=50_000.0,
        risk_pct=2.0,
        max_loss_per_contract=315.0,
        commission_per_leg=0.65,
        legs_count=2,
    )
    # risk_budget = 1000, total_cost_per_contract = 315 + (0.65*2*2) = 317.60
    # floor(1000 / 317.60) = 3
    assert result["max_contracts"] == 3
    assert result["total_risk_usd"] > 0

def test_position_sizing_zero_balance():
    result = _calculate_position_size(
        account_balance=0.0,
        risk_pct=2.0,
        max_loss_per_contract=315.0,
    )
    assert result["max_contracts"] == 0
```

### Step 2: Run test, verify FAIL

```bash
python -m pytest tests/test_options_edge_position_sizing.py -v
```
Expected: ImportError (`_calculate_position_size` not found)

### Step 3: Implement position sizing function

Add to `routes.py` (near top, as a utility):

```python
def _calculate_position_size(
    account_balance: float,
    risk_pct: float,
    max_loss_per_contract: float,
    commission_per_leg: float = 0.65,
    legs_count: int = 2,
    max_contracts_cap: int = 50,
) -> dict:
    """Calculate how many contracts to trade given account + risk tolerance."""
    if account_balance <= 0 or risk_pct <= 0 or max_loss_per_contract <= 0:
        return {"max_contracts": 0, "risk_budget_usd": 0, "total_risk_usd": 0,
                "skip_reason": "invalid_inputs"}

    risk_budget = account_balance * (risk_pct / 100.0)
    round_trip_commission = commission_per_leg * legs_count * 2  # open + close
    total_cost_per_contract = max_loss_per_contract + round_trip_commission
    max_contracts = min(max_contracts_cap, int(risk_budget / total_cost_per_contract))

    if max_contracts <= 0:
        return {"max_contracts": 0, "risk_budget_usd": round(risk_budget, 2),
                "total_risk_usd": 0, "skip_reason": "max_loss_exceeds_risk_budget"}

    total_risk = max_contracts * total_cost_per_contract
    return {
        "max_contracts": max_contracts,
        "risk_budget_usd": round(risk_budget, 2),
        "total_risk_usd": round(total_risk, 2),
        "risk_per_contract_usd": round(total_cost_per_contract, 2),
        "remaining_budget_usd": round(risk_budget - total_risk, 2),
        "account_risk_pct": round((total_risk / account_balance) * 100, 2),
        "skip_reason": None,
    }
```

### Step 4: Add FastAPI endpoint

```python
@router.post("/options-edge/position-size")
async def options_edge_position_size(request: Request):
    body = await request.json()
    account = _safe_float(body.get("account_balance"), 10000.0)
    risk_pct = _safe_float(body.get("risk_pct"), 2.0)
    trades = body.get("trades", [])  # list of {max_loss, legs_count, symbol, structure_type}

    results = []
    for t in trades:
        r = _calculate_position_size(
            account_balance=account,
            risk_pct=risk_pct,
            max_loss_per_contract=_safe_float(t.get("max_loss"), 0),
            commission_per_leg=_safe_float(body.get("commission_per_leg"), 0.65),
            legs_count=int(t.get("legs_count", 2)),
        )
        r["symbol"] = t.get("symbol", "")
        r["structure_type"] = t.get("structure_type", "")
        results.append(r)

    total_risk = sum(r["total_risk_usd"] for r in results)
    return JSONResponse({"ok": True, "sizing": results,
                         "portfolio_total_risk_usd": round(total_risk, 2),
                         "portfolio_risk_pct": round((total_risk / max(account, 1)) * 100, 2)})
```

### Step 5: Add calculator UI to scan detail template

Add a collapsible card after the "Built Trade Candidates" table in `options_edge_scan_detail.html`:

```html
<div class="card mt-4">
    <div class="card-header">
        <i class="bi bi-calculator me-2"></i>Position Sizing Calculator
    </div>
    <div class="card-body">
        <div class="row g-3 mb-3">
            <div class="col-4">
                <label class="form-label">Account Balance ($)</label>
                <input type="number" class="form-control" id="psAccountBalance" value="10000" min="0">
            </div>
            <div class="col-4">
                <label class="form-label">Risk Per Trade (%)</label>
                <input type="number" class="form-control" id="psRiskPct" value="2.0" min="0.1" max="10" step="0.1">
            </div>
            <div class="col-4">
                <label class="form-label">Commission/Leg ($)</label>
                <input type="number" class="form-control" id="psCommission" value="0.65" min="0" step="0.01">
            </div>
        </div>
        <button class="btn btn-primary mb-3" onclick="calculatePositionSizes()">
            <i class="bi bi-calculator me-1"></i>Calculate
        </button>
        <div id="psResults" style="display:none;">
            <div class="alert alert-info mb-3">
                <strong>Portfolio Risk:</strong> <span id="psPortfolioRisk"></span>
            </div>
            <table class="table table-sm table-striped">
                <thead><tr><th>Symbol</th><th>Structure</th><th>Max Loss</th><th>Contracts</th><th>Total Risk</th><th>Status</th></tr></thead>
                <tbody id="psTableBody"></tbody>
            </table>
        </div>
    </div>
</div>
```

JavaScript (inline at bottom of template):
```javascript
function calculatePositionSizes() {
    const account = parseFloat(document.getElementById('psAccountBalance').value) || 0;
    const riskPct = parseFloat(document.getElementById('psRiskPct').value) || 2;
    const commission = parseFloat(document.getElementById('psCommission').value) || 0.65;
    const trades = {{ trades|tojson }};

    fetch('/api/options-edge/position-size', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
            account_balance: account, risk_pct: riskPct,
            commission_per_leg: commission,
            trades: trades.map(t => ({
                symbol: t.symbol, structure_type: t.structure_type,
                max_loss: t.max_loss || 0, legs_count: (t.legs || []).length || 2
            }))
        })
    })
    .then(r => r.json())
    .then(data => {
        document.getElementById('psResults').style.display = 'block';
        document.getElementById('psPortfolioRisk').textContent =
            `$${data.portfolio_total_risk_usd} (${data.portfolio_risk_pct}% of account)`;
        const tbody = document.getElementById('psTableBody');
        tbody.innerHTML = '';
        data.sizing.forEach(s => {
            const row = `<tr>
                <td><strong>${s.symbol}</strong></td>
                <td>${s.structure_type}</td>
                <td>$${(s.risk_per_contract_usd || 0).toFixed(2)}</td>
                <td><strong>${s.max_contracts}</strong></td>
                <td>$${s.total_risk_usd.toFixed(2)}</td>
                <td>${s.skip_reason ? '<span class="badge bg-danger">SKIP: '+s.skip_reason+'</span>' : '<span class="badge bg-success">OK</span>'}</td>
            </tr>`;
            tbody.innerHTML += row;
        });
    });
}
```

### Step 6: Add Flask proxy route

```python
@app.route('/api/options-edge/position-size', methods=['POST'])
def options_edge_position_size_proxy():
    import json
    data = request.get_json(force=True)
    res = api_request('POST', '/options-edge/position-size', json=data, return_error=True, timeout_sec=10)
    return jsonify(res[0] if isinstance(res, tuple) else res)
```

### Step 7: Run tests, verify PASS

```bash
python -m pytest tests/test_options_edge_position_sizing.py -v
```

---

## Task 2: Options Trade Journal

Adds a DB table and UI for tracking trade outcomes. User clicks "Track This Trade" on scan detail, system records it. User later logs exit (manual entry of profit/loss).

**Files:**
- Modify: `dashboard/backend/models/database.py` (add `OptionsEdgeTradeJournalModel`)
- Modify: `dashboard/backend/models/database.py:_run_migrations()` (table auto-creation)
- Modify: `dashboard/backend/api/routes.py` (CRUD endpoints)
- Create: `dashboard/frontend/templates/options_edge_journal.html`
- Modify: `dashboard/frontend/templates/options_edge_scan_detail.html` (add Track button)
- Modify: `dashboard/frontend/templates/base.html` (add Journal nav link)
- Modify: `dashboard/frontend/app.py` (Flask routes)
- Test: `tests/test_options_edge_journal.py`

### Step 1: Write failing test

```python
# tests/test_options_edge_journal.py
def test_journal_create_and_retrieve():
    """Create a journal entry from a trade candidate, then list it."""
    # ... uses TestClient, creates scan+trade, then POSTs to journal endpoint
    # Asserts: entry created with status='OPEN', has scan_id, symbol, etc.

def test_journal_close_trade():
    """Close an open journal entry with actual P&L."""
    # POSTs close with exit_credit, actual_pnl
    # Asserts: status='CLOSED', actual_pnl recorded, closed_at set

def test_journal_stats():
    """Check aggregate stats (win rate, total P&L, avg hold days)."""
    # GETs /options-edge/journal/stats
    # Asserts: correct aggregation
```

### Step 2: Add DB model

```python
class OptionsEdgeTradeJournalModel(Base):
    """Tracks options trades from scan -> entry -> exit."""
    __tablename__ = "options_trade_journal"

    id = Column(Integer, primary_key=True, index=True)
    journal_id = Column(String(64), unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    closed_at = Column(DateTime, nullable=True)
    status = Column(String(20), default="OPEN")  # OPEN, CLOSED, EXPIRED, CANCELLED

    # Source reference
    scan_id = Column(String(64), nullable=True)
    trade_candidate_id = Column(Integer, nullable=True)

    # Trade details (copied from trade candidate at time of tracking)
    symbol = Column(String(20), nullable=False)
    structure_type = Column(String(40), nullable=False)
    legs_json = Column(JSON, nullable=True)
    entry_credit = Column(Float, nullable=True)  # net credit received
    max_profit = Column(Float, nullable=True)
    max_loss = Column(Float, nullable=True)
    pop_est = Column(Float, nullable=True)
    expiry_date = Column(String(20), nullable=True)
    dte_at_entry = Column(Integer, nullable=True)

    # Position sizing (from calculator)
    contracts = Column(Integer, default=1)
    account_balance_at_entry = Column(Float, nullable=True)
    risk_pct_at_entry = Column(Float, nullable=True)

    # Exit details (filled when closing)
    exit_credit = Column(Float, nullable=True)     # credit to close (buy back)
    actual_pnl = Column(Float, nullable=True)       # per contract
    actual_pnl_total = Column(Float, nullable=True) # total (contracts * pnl)
    exit_reason = Column(String(40), nullable=True)  # profit_target, stop_loss, expiry, manual
    hold_days = Column(Integer, nullable=True)

    # User notes
    notes = Column(Text, nullable=True)
```

### Step 3: Add API endpoints

- `POST /options-edge/journal/track` - create entry from trade candidate
- `POST /options-edge/journal/{journal_id}/close` - close with exit details
- `GET /options-edge/journal` - list all (filter by status)
- `GET /options-edge/journal/stats` - aggregate stats
- `DELETE /options-edge/journal/{journal_id}` - cancel/delete

### Step 4: Add journal page template

New page `/options-edge/journal` showing:
- Summary cards: total trades, open, closed, win rate, total P&L
- Open trades table (symbol, structure, entry credit, contracts, DTE remaining, notes, Close button)
- Closed trades table (symbol, result, P&L, hold days, exit reason)

### Step 5: Add "Track This Trade" button to scan detail

Each trade row gets a button that POSTs to journal/track with the trade candidate data.

### Step 6: Run full test suite

```bash
python -m pytest tests/test_options_edge_journal.py tests/test_options_edge_phase21.py tests/test_options_edge_live_route.py tests/test_options_edge_phase3_backtest.py tests/test_options_edge_llm_reporter.py -v
```

---

## Task 3: Expose Hidden Backtest Parameters + Early Close Controls

The backtest engine already supports `take_profit_frac` (0.50 = close at 50% of max profit) and `stop_loss_credit_mult` (1.75x credit = stop loss). These are hidden in the UI. Expose them plus add equity curve chart.

**Files:**
- Modify: `dashboard/frontend/templates/options_edge.html` (add advanced backtest params)
- Modify: `dashboard/frontend/app.py` (read new form fields)
- Modify: `dashboard/frontend/templates/options_edge_backtest_detail.html` (equity curve chart + trade log)
- Test: manual verification (existing backtest tests cover the engine)

### Step 1: Add early close + advanced params to backtest form

In `options_edge.html`, add a collapsible "Advanced Backtest Settings" section inside the backtest form:

```html
<details>
    <summary class="text-primary" style="cursor:pointer;">Advanced Backtest Settings</summary>
    <div class="row g-2 mt-2">
        <div class="col-4">
            <label class="form-label">Take Profit %</label>
            <input class="form-control" name="take_profit_frac" value="0.50" step="0.05" type="number">
            <small class="text-muted">Close at this fraction of max profit (0.50 = 50%)</small>
        </div>
        <div class="col-4">
            <label class="form-label">Stop Loss Mult</label>
            <input class="form-control" name="stop_loss_credit_mult" value="1.75" step="0.25" type="number">
            <small class="text-muted">Stop at N × credit received</small>
        </div>
        <div class="col-4">
            <label class="form-label">Max Contracts/Trade</label>
            <input class="form-control" name="max_contracts_per_trade" value="3" type="number">
        </div>
        <div class="col-4">
            <label class="form-label">Commission/Leg ($)</label>
            <input class="form-control" name="commission_per_leg" value="0.65" step="0.01" type="number">
        </div>
        <div class="col-4">
            <label class="form-label">Slippage %</label>
            <input class="form-control" name="slippage_pct" value="0.01" step="0.005" type="number">
        </div>
        <div class="col-4">
            <label class="form-label">Spread %</label>
            <input class="form-control" name="spread_pct" value="0.005" step="0.001" type="number">
        </div>
    </div>
</details>
```

### Step 2: Update Flask handler to read new params

In `app.py` options_edge_run_backtest route, add:
```python
payload["take_profit_frac"] = float(request.form.get("take_profit_frac", 0.50))
payload["stop_loss_credit_mult"] = float(request.form.get("stop_loss_credit_mult", 1.75))
payload["max_contracts_per_trade"] = int(request.form.get("max_contracts_per_trade", 3))
payload["commission_per_leg"] = float(request.form.get("commission_per_leg", 0.65))
payload["slippage_pct"] = float(request.form.get("slippage_pct", 0.01))
payload["spread_pct"] = float(request.form.get("spread_pct", 0.005))
```

### Step 3: Add equity curve chart + trade log to backtest detail

In `options_edge_backtest_detail.html`, add:

1. **Chart.js equity curve** (after the core metrics card):
```html
<div class="card mb-4">
    <div class="card-header"><i class="bi bi-graph-up me-2"></i>Equity Curve</div>
    <div class="card-body">
        <canvas id="equityCurveChart" height="250"></canvas>
    </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script>
const eq = {{ (run.equity_curve or [])|tojson }};
if (eq.length > 0) {
    new Chart(document.getElementById('equityCurveChart'), {
        type: 'line',
        data: {
            labels: eq.map(e => e.i),
            datasets: [{
                label: 'Equity ($)',
                data: eq.map(e => e.equity),
                borderColor: eq[eq.length-1].equity >= eq[0].equity ? '#198754' : '#dc3545',
                fill: false, tension: 0.1, pointRadius: 2
            }]
        },
        options: { responsive: true, plugins: { legend: { display: false } } }
    });
}
</script>
```

2. **Trade log table** (after equity curve):
```html
<div class="card mb-4">
    <div class="card-header"><i class="bi bi-journal-text me-2"></i>Trade Log ({{ (run.trade_log or [])|length }})</div>
    <div class="card-body p-0">
        <div class="table-responsive" style="max-height: 400px; overflow-y: auto;">
            <table class="table table-sm table-hover mb-0">
                <thead><tr><th>#</th><th>Symbol</th><th>Type</th><th>Qty</th><th>POP</th><th>Win</th><th>Gross</th><th>Costs</th><th>Net</th><th>Equity</th></tr></thead>
                <tbody>
                {% for t in (run.trade_log or []) %}
                <tr class="{% if t.win %}table-success{% else %}table-danger{% endif %}">
                    <td>{{ t.i }}</td>
                    <td><strong>{{ t.symbol }}</strong></td>
                    <td>{{ t.structure_type }}</td>
                    <td>{{ t.qty }}</td>
                    <td>{{ "%.1f"|format((t.pop_est or 0)*100) }}%</td>
                    <td>{% if t.win %}<i class="bi bi-check-circle text-success"></i>{% else %}<i class="bi bi-x-circle text-danger"></i>{% endif %}</td>
                    <td>${{ "%.2f"|format(t.gross_pnl or 0) }}</td>
                    <td class="text-muted">${{ "%.2f"|format(t.costs or 0) }}</td>
                    <td class="{% if (t.net_pnl or 0) >= 0 %}text-success{% else %}text-danger{% endif %}">${{ "%.2f"|format(t.net_pnl or 0) }}</td>
                    <td>${{ "%.2f"|format(t.equity_after or 0) }}</td>
                </tr>
                {% endfor %}
                </tbody>
            </table>
        </div>
    </div>
</div>
```

### Step 4: Pass equity_curve + trade_log to template

In `routes.py` backtest run response, ensure `equity_curve` and `trade_log` are stored in `OptionsEdgeBacktestRunModel`. Currently only `metrics_json` is stored.

Add columns to DB model:
```python
equity_curve_json = Column(JSON, nullable=True)
trade_log_json = Column(JSON, nullable=True)
```

And in the route that creates the backtest run, save them:
```python
db_run.equity_curve_json = _json_safe(result.get("equity_curve", []))
db_run.trade_log_json = _json_safe(result.get("trade_log", []))
```

### Step 5: Run existing backtest tests

```bash
python -m pytest tests/test_options_edge_phase3_backtest.py -v
```

---

## Task 4: Wire Backtest Detail Data to Frontend

The Flask route for backtest detail needs to pass equity_curve and trade_log to the template.

**Files:**
- Modify: `dashboard/frontend/app.py` (backtest detail route)
- Modify: `dashboard/backend/api/routes.py` (backtest detail response)

### Step 1: Update backend response

In the GET `/options-edge/backtest/{run_id}` route, include equity_curve and trade_log from stored JSON columns.

### Step 2: Update Flask route

Pass `equity_curve` and `trade_log` from the backend response to the template context.

### Step 3: Run full test suite

```bash
python -m pytest tests/test_options_edge_phase21.py tests/test_options_edge_live_route.py tests/test_options_edge_phase3_backtest.py tests/test_options_edge_llm_reporter.py tests/test_options_edge_position_sizing.py tests/test_options_edge_journal.py -v
```

Expected: ALL PASS

---

## Implementation Order

1. **Task 1** (Position Sizing) - standalone, no DB changes
2. **Task 3** (Early Close + Backtest UI) - DB migration + UI
3. **Task 4** (Wire Data to Frontend) - depends on Task 3
4. **Task 2** (Trade Journal) - new DB table + CRUD + UI page

## Testing Strategy

- Unit tests for position sizing math (pure function)
- Integration tests for journal CRUD (TestClient + in-memory DB)
- Existing backtest tests validate engine behavior unchanged
- Manual UI verification for Chart.js rendering
