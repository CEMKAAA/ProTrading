using System;
using System.Globalization;
using cAlgo.API;

namespace cAlgo.Robots
{
    [Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public class DrawRiskRectangleCTraderTool : Robot
    {
        private const string Build = "2026-07-10.risk-rectangle-tool";
        private const string Prefix = "CTR_RISK_RECT_";
        private const string RectName = Prefix + "BOX";
        private const string TextName = Prefix + "LABEL";
        private const string DashName = Prefix + "DASH";

        [Parameter("Lots", DefaultValue = 0.10, MinValue = 0.0)]
        public double Lots { get; set; }

        [Parameter("Auto Create Rectangle", DefaultValue = true)]
        public bool AutoCreateRectangle { get; set; }

        [Parameter("Initial Bars Wide", DefaultValue = 80, MinValue = 5)]
        public int InitialBarsWide { get; set; }

        [Parameter("Initial Height Pips", DefaultValue = 100.0, MinValue = 1.0)]
        public double InitialHeightPips { get; set; }

        [Parameter("Update Ms", DefaultValue = 250, MinValue = 100)]
        public int UpdateMilliseconds { get; set; }

        [Parameter("Show Debug", DefaultValue = true)]
        public bool ShowDebug { get; set; }

        [Parameter("Keep Objects On Stop", DefaultValue = false)]
        public bool KeepObjectsOnStop { get; set; }

        private ChartRectangle _rectangle;
        private StackPanel _panel;
        private TextBox _lotBox;
        private TextBlock _statusText;
        private double _runtimeLots;

        protected override void OnStart()
        {
            _runtimeLots = ClampLots(Lots);
            CreateControls();

            if (AutoCreateRectangle)
                EnsureRectangle();

            Timer.Start(TimeSpan.FromMilliseconds(Math.Max(100, UpdateMilliseconds)));
            UpdateDisplay("start");
        }

        protected override void OnTimer()
        {
            UpdateDisplay("timer");
        }

        protected override void OnStop()
        {
            if (!KeepObjectsOnStop)
            {
                Chart.RemoveObject(RectName);
                Chart.RemoveObject(TextName);
                Chart.RemoveObject(DashName);
            }

            if (_panel != null)
                Chart.RemoveControl(_panel);
        }

        private void CreateControls()
        {
            _panel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = 8,
                BackgroundColor = Color.FromArgb(180, 10, 14, 22)
            };

            _panel.AddChild(new TextBlock
            {
                Text = "Risk Rect Lot",
                ForegroundColor = Color.White,
                Margin = 4,
                FontSize = 12
            });

            _lotBox = new TextBox
            {
                Text = _runtimeLots.ToString("0.##", CultureInfo.InvariantCulture),
                Width = 70,
                Margin = 4
            };
            _panel.AddChild(_lotBox);

            var apply = new Button
            {
                Text = "Apply",
                Width = 58,
                Margin = 4,
                BackgroundColor = Color.DodgerBlue,
                ForegroundColor = Color.White
            };
            apply.Click += args => ApplyLotFromBox();
            _panel.AddChild(apply);

            var reset = new Button
            {
                Text = "Reset Box",
                Width = 82,
                Margin = 4,
                BackgroundColor = Color.SlateGray,
                ForegroundColor = Color.White
            };
            reset.Click += args =>
            {
                ResetRectangle();
                UpdateDisplay("reset");
            };
            _panel.AddChild(reset);

            _statusText = new TextBlock
            {
                Text = "-",
                ForegroundColor = Color.LightSkyBlue,
                Margin = 4,
                FontSize = 12
            };
            _panel.AddChild(_statusText);

            Chart.AddControl(_panel);
        }

        private void ApplyLotFromBox()
        {
            if (_lotBox == null)
                return;

            var raw = (_lotBox.Text ?? string.Empty).Trim().Replace(',', '.');
            if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) || parsed <= 0)
                parsed = _runtimeLots;

            _runtimeLots = ClampLots(parsed);
            _lotBox.Text = _runtimeLots.ToString("0.##", CultureInfo.InvariantCulture);
            UpdateDisplay("apply_lot");
        }

        private double ClampLots(double lots)
        {
            if (lots <= 0)
                lots = 0.01;
            return Math.Round(lots, 4);
        }

        private void EnsureRectangle()
        {
            _rectangle = Chart.FindObject(RectName) as ChartRectangle;
            if (_rectangle == null)
                ResetRectangle();
        }

        private void ResetRectangle()
        {
            Chart.RemoveObject(RectName);

            var bars = Bars.Count;
            var rightIndex = Math.Max(0, bars - 5);
            var leftIndex = Math.Max(0, rightIndex - Math.Max(5, InitialBarsWide));
            var mid = Symbol.Bid > 0 ? Symbol.Bid : Bars.ClosePrices.LastValue;
            var halfHeight = Math.Max(Symbol.PipSize, InitialHeightPips * Symbol.PipSize * 0.5);
            var top = mid + halfHeight;
            var bottom = mid - halfHeight;

            _rectangle = Chart.DrawRectangle(RectName, leftIndex, top, rightIndex, bottom, Color.DodgerBlue);
            _rectangle.IsInteractive = true;
            _rectangle.IsFilled = false;
            _rectangle.Thickness = 2;
        }

        private void UpdateDisplay(string reason)
        {
            EnsureRectangle();
            if (_rectangle == null)
                return;

            var top = Math.Max(_rectangle.Y1, _rectangle.Y2);
            var bottom = Math.Min(_rectangle.Y1, _rectangle.Y2);
            var height = Math.Abs(top - bottom);
            var pips = Symbol.PipSize > 0 ? height / Symbol.PipSize : 0.0;
            var volume = Symbol.QuantityToVolumeInUnits(_runtimeLots);
            volume = Symbol.NormalizeVolumeInUnits(volume, RoundingMode.ToNearest);
            var money = pips > 0 && volume > 0 ? Symbol.AmountRisked(volume, pips) : 0.0;
            var onePip = volume > 0 ? Symbol.AmountRisked(volume, 1.0) : 0.0;
            var points = Symbol.TickSize > 0 ? height / Symbol.TickSize : 0.0;

            var text =
                $"{SymbolName} {TimeFrame} | Lot {_runtimeLots:0.####} | Vol {volume:0}\n" +
                $"Height {height:0.#####} | {pips:0.0} pips | {points:0.0} ticks\n" +
                $"Approx PnL/Risk: {money:0.00} {Account.Asset.Name}\n" +
                $"1 pip value: {onePip:0.00} {Account.Asset.Name}";

            if (ShowDebug)
            {
                text += $"\nPipSize {Symbol.PipSize:0.########} | TickSize {Symbol.TickSize:0.########}";
                text += $"\nBid {Symbol.Bid:0.#####} Ask {Symbol.Ask:0.#####} | {Build}";
            }

            Chart.DrawStaticText(DashName, text, VerticalAlignment.Top, HorizontalAlignment.Left, Color.LightSkyBlue);

            var labelIndex = Math.Max(0, Bars.Count - 1);
            Chart.RemoveObject(TextName);
            Chart.DrawText(TextName, $"{money:0.00} {Account.Asset.Name} | {pips:0.0} pips", labelIndex, top, Color.LimeGreen);

            if (_statusText != null)
                _statusText.Text = $"{money:0.00} {Account.Asset.Name} / {pips:0.0} pips";
        }
    }
}
