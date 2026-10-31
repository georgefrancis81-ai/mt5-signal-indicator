//+------------------------------------------------------------------+
//|                                            MajorsTrendSignal.mq5 |
//|  Trend-following buy/sell signals for major forex pairs.         |
//|                                                                  |
//|  Rules (all evaluated on CLOSED bars only, so arrows never       |
//|  repaint once printed):                                          |
//|   BUY  = close > EMA(trend) and EMA(slow) > EMA(trend)           |
//|          and EMA(trend) rising over N bars                       |
//|          and EMA(fast) crosses above EMA(slow) on this bar       |
//|          and RSI in [buyMin, buyMax]                             |
//|          and ADX >= adxMin                                       |
//|          and (optional) bullish candle                           |
//|          and (optional) inside trading session                   |
//|          and at least N bars since the previous signal           |
//|   SELL = exact mirror image.                                     |
//|   SL   = entry -/+ ATR * multiplier, TP = SL distance * R:R      |
//+------------------------------------------------------------------+
#property copyright   "georgefrancis81-ai"
#property link        "https://github.com/georgefrancis81-ai/mt5-signal-indicator"
#property version     "1.00"
#property description "Majors Trend Signal: EMA trend filter + EMA cross trigger"
#property description "+ RSI/ADX confirmation, ATR-based SL/TP suggestion."
#property description "Signals are confirmed on bar close and never repaint."
#property description "No indicator can guarantee wins. Backtest before trading live."

#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   5

//--- plot 0: trend EMA line
#property indicator_label1  "Trend EMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDimGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
//--- plot 1: buy arrows
#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2
//--- plot 2: sell arrows
#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2
//--- plot 3/4: SL and TP (hidden on chart, visible in Data Window, read by the EA)
#property indicator_label4  "Stop Loss"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Take Profit"
#property indicator_type5   DRAW_NONE

//--- inputs (keep this order: the companion EA passes them to iCustom in this order)
input int    InpFastEMA        = 9;     // Fast EMA (trigger)
input int    InpSlowEMA        = 21;    // Slow EMA (trigger)
input int    InpTrendEMA       = 200;   // Trend EMA (direction filter)
input int    InpTrendSlopeBars = 10;    // Trend EMA must be rising/falling over N bars (0 = off)
input int    InpRSIPeriod      = 14;    // RSI period
input double InpRSIBuyMin      = 50.0;  // RSI min for BUY
input double InpRSIBuyMax      = 70.0;  // RSI max for BUY (avoid overbought)
input double InpRSISellMin     = 30.0;  // RSI min for SELL (avoid oversold)
input double InpRSISellMax     = 50.0;  // RSI max for SELL
input int    InpADXPeriod      = 14;    // ADX period
input double InpADXMin         = 20.0;  // Minimum ADX (trend strength)
input int    InpATRPeriod      = 14;    // ATR period
input double InpSLATRMult      = 1.5;   // Stop loss = ATR x this
input double InpRewardRisk     = 2.0;   // Take profit = SL distance x this
input bool   InpRequireCandle  = true;  // Require candle in signal direction
input int    InpCooldownBars   = 5;     // Minimum bars between signals
input bool   InpUseSession     = true;  // Only signal inside session hours
input int    InpSessionStart   = 7;     // Session start hour (broker server time)
input int    InpSessionEnd     = 20;    // Session end hour (broker server time)
input bool   InpAlertPopup     = true;  // Pop-up alert
input bool   InpAlertSound     = true;  // Sound alert
input bool   InpAlertPush      = false; // Push notification to MT5 mobile
input bool   InpAlertEmail     = false; // E-mail alert
input bool   InpShowStats      = true;  // Show historical win-rate panel
input int    InpStatsBars      = 3000;  // Bars of history used for the panel

//--- buffers
double TrendBuf[];
double BuyBuf[];
double SellBuf[];
double SLBuf[];
double TPBuf[];
double FastBuf[];
double SlowBuf[];
double RSIBuf[];
double ADXBuf[];
double ATRBuf[];

//--- handles
int hFast  = INVALID_HANDLE;
int hSlow  = INVALID_HANDLE;
int hTrend = INVALID_HANDLE;
int hRSI   = INVALID_HANDLE;
int hADX   = INVALID_HANDLE;
int hATR   = INVALID_HANDLE;

//--- state
int      g_lastSignalBar = -1000000;
datetime g_lastAlertTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpFastEMA < 1 || InpSlowEMA <= InpFastEMA || InpTrendEMA <= InpSlowEMA)
     {
      Print("MajorsTrendSignal: need 1 <= Fast EMA < Slow EMA < Trend EMA");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpSLATRMult <= 0.0 || InpRewardRisk <= 0.0)
     {
      Print("MajorsTrendSignal: SL multiplier and reward:risk must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, TrendBuf, INDICATOR_DATA);
   SetIndexBuffer(1, BuyBuf,   INDICATOR_DATA);
   SetIndexBuffer(2, SellBuf,  INDICATOR_DATA);
   SetIndexBuffer(3, SLBuf,    INDICATOR_DATA);
   SetIndexBuffer(4, TPBuf,    INDICATOR_DATA);
   SetIndexBuffer(5, FastBuf,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, SlowBuf,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, RSIBuf,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, ADXBuf,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, ATRBuf,   INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);   // up arrow
   PlotIndexSetInteger(2, PLOT_ARROW, 234);   // down arrow
   for(int p = 0; p < 5; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpTrendEMA);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("MajorsTrendSignal(%d,%d,%d)", InpFastEMA, InpSlowEMA, InpTrendEMA));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   hFast  = iMA(_Symbol, _Period, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, _Period, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, _Period, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   hADX   = iADX(_Symbol, _Period, InpADXPeriod);
   hATR   = iATR(_Symbol, _Period, InpATRPeriod);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("MajorsTrendSignal: failed to create indicator handles, error ", GetLastError());
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hFast  != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow  != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hTrend != INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hRSI   != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hADX   != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR   != INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
  }

//+------------------------------------------------------------------+
bool InSession(const datetime t)
  {
   if(!InpUseSession)
      return(true);
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(InpSessionStart == InpSessionEnd)
      return(true);
   if(InpSessionStart < InpSessionEnd)
      return(dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
   return(dt.hour >= InpSessionStart || dt.hour < InpSessionEnd); // wraps past midnight
  }

//+------------------------------------------------------------------+
bool CopyAll(const int count)
  {
   if(CopyBuffer(hTrend, 0, 0, count, TrendBuf) != count) return(false);
   if(CopyBuffer(hFast,  0, 0, count, FastBuf)  != count) return(false);
   if(CopyBuffer(hSlow,  0, 0, count, SlowBuf)  != count) return(false);
   if(CopyBuffer(hRSI,   0, 0, count, RSIBuf)   != count) return(false);
   if(CopyBuffer(hADX,   0, 0, count, ADXBuf)   != count) return(false); // buffer 0 = main ADX line
   if(CopyBuffer(hATR,   0, 0, count, ATRBuf)   != count) return(false);
   return(true);
  }

//+------------------------------------------------------------------+
void SendSignalAlert(const bool isBuy, const datetime t, const double entry,
                     const double sl, const double tp)
  {
   string tf  = StringSubstr(EnumToString(_Period), 7);
   string msg = StringFormat("%s %s %s @ %s | SL %s | TP %s | bar %s",
                             _Symbol, tf, isBuy ? "BUY" : "SELL",
                             DoubleToString(entry, _Digits),
                             DoubleToString(sl, _Digits),
                             DoubleToString(tp, _Digits),
                             TimeToString(t, TIME_DATE | TIME_MINUTES));
   if(InpAlertPopup) Alert("MajorsTrendSignal: ", msg);
   if(InpAlertSound && !InpAlertPopup) PlaySound("alert.wav");
   if(InpAlertPush)  SendNotification("MajorsTrendSignal: " + msg);
   if(InpAlertEmail) SendMail("MajorsTrendSignal " + _Symbol + " " + (isBuy ? "BUY" : "SELL"), msg);
  }

//+------------------------------------------------------------------+
//| Walk every printed signal forward bar by bar and see whether SL  |
//| or TP was touched first. If both are inside the same bar we      |
//| count it as a loss (conservative). Spread is ignored here, so    |
//| use the Strategy Tester + EA for the real figure.                |
//+------------------------------------------------------------------+
void UpdateStats(const int rates_total, const double &high[], const double &low[])
  {
   int from = MathMax(0, rates_total - 1 - InpStatsBars);
   int wins = 0, losses = 0, open = 0;

   for(int i = from; i < rates_total - 1; i++)
     {
      bool isBuy  = (BuyBuf[i]  != EMPTY_VALUE);
      bool isSell = (SellBuf[i] != EMPTY_VALUE);
      if(!isBuy && !isSell)
         continue;
      double sl = SLBuf[i], tp = TPBuf[i];
      int result = 0;
      for(int j = i + 1; j < rates_total; j++)
        {
         if(isBuy)
           {
            if(low[j]  <= sl) { result = -1; break; }
            if(high[j] >= tp) { result =  1; break; }
           }
         else
           {
            if(high[j] >= sl) { result = -1; break; }
            if(low[j]  <= tp) { result =  1; break; }
           }
        }
      if(result > 0)      wins++;
      else if(result < 0) losses++;
      else                open++;
     }

   int    closed  = wins + losses;
   double winRate = closed > 0 ? 100.0 * wins / closed : 0.0;
   double netR    = wins * InpRewardRisk - losses;
   double breakEven = 100.0 / (1.0 + InpRewardRisk);

   Comment(StringFormat("MajorsTrendSignal  %s %s  (last %d bars, no spread)\n"
                        "Signals: %d   Wins: %d   Losses: %d   Open: %d\n"
                        "Win rate: %.1f%%   (break-even at 1:%.1f R:R = %.1f%%)\n"
                        "Net result: %+.1f R",
                        _Symbol, StringSubstr(EnumToString(_Period), 7), InpStatsBars,
                        closed + open, wins, losses, open,
                        winRate, InpRewardRisk, breakEven, netR));
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   int warmup = MathMax(InpTrendEMA, MathMax(InpADXPeriod * 2, MathMax(InpRSIPeriod, InpATRPeriod)))
                + InpTrendSlopeBars + 2;
   if(rates_total < warmup + 2)
      return(0);

   if(BarsCalculated(hFast) < rates_total || BarsCalculated(hSlow) < rates_total ||
      BarsCalculated(hTrend) < rates_total || BarsCalculated(hRSI) < rates_total ||
      BarsCalculated(hADX) < rates_total || BarsCalculated(hATR) < rates_total)
      return(0);

   int toCopy = (prev_calculated > 0 && prev_calculated <= rates_total)
                ? rates_total - prev_calculated + 1 : rates_total;
   if(!CopyAll(toCopy))
      return(0);

   int start;
   if(prev_calculated == 0)
     {
      ArrayInitialize(BuyBuf,  EMPTY_VALUE);
      ArrayInitialize(SellBuf, EMPTY_VALUE);
      ArrayInitialize(SLBuf,   EMPTY_VALUE);
      ArrayInitialize(TPBuf,   EMPTY_VALUE);
      g_lastSignalBar = -1000000;
      start = warmup;
     }
   else
      start = prev_calculated - 1;   // first bar that closed since the last call

   //--- the forming bar never carries a signal (this is what prevents repainting)
   int last = rates_total - 1;
   BuyBuf[last] = EMPTY_VALUE;
   SellBuf[last] = EMPTY_VALUE;
   SLBuf[last] = EMPTY_VALUE;
   TPBuf[last] = EMPTY_VALUE;

   bool newClosedBar = false;

   for(int i = start; i <= rates_total - 2; i++)
     {
      newClosedBar = true;
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;
      SLBuf[i]   = EMPTY_VALUE;
      TPBuf[i]   = EMPTY_VALUE;

      if(i - g_lastSignalBar < InpCooldownBars)
         continue;
      if(!InSession(time[i]))
         continue;

      double atr = ATRBuf[i];
      if(atr <= 0.0 || ADXBuf[i] < InpADXMin)
         continue;

      bool crossUp   = FastBuf[i - 1] <= SlowBuf[i - 1] && FastBuf[i] > SlowBuf[i];
      bool crossDown = FastBuf[i - 1] >= SlowBuf[i - 1] && FastBuf[i] < SlowBuf[i];

      bool trendUp   = close[i] > TrendBuf[i] && SlowBuf[i] > TrendBuf[i] &&
                       (InpTrendSlopeBars <= 0 || TrendBuf[i] > TrendBuf[i - InpTrendSlopeBars]);
      bool trendDown = close[i] < TrendBuf[i] && SlowBuf[i] < TrendBuf[i] &&
                       (InpTrendSlopeBars <= 0 || TrendBuf[i] < TrendBuf[i - InpTrendSlopeBars]);

      bool rsiBuy  = RSIBuf[i] >= InpRSIBuyMin  && RSIBuf[i] <= InpRSIBuyMax;
      bool rsiSell = RSIBuf[i] >= InpRSISellMin && RSIBuf[i] <= InpRSISellMax;

      bool candleUp   = !InpRequireCandle || close[i] > open[i];
      bool candleDown = !InpRequireCandle || close[i] < open[i];

      double slDist = atr * InpSLATRMult;
      double entry  = close[i];

      if(crossUp && trendUp && rsiBuy && candleUp)
        {
         BuyBuf[i] = low[i] - atr * 0.5;
         SLBuf[i]  = NormalizeDouble(entry - slDist, _Digits);
         TPBuf[i]  = NormalizeDouble(entry + slDist * InpRewardRisk, _Digits);
         g_lastSignalBar = i;
        }
      else if(crossDown && trendDown && rsiSell && candleDown)
        {
         SellBuf[i] = high[i] + atr * 0.5;
         SLBuf[i]   = NormalizeDouble(entry + slDist, _Digits);
         TPBuf[i]   = NormalizeDouble(entry - slDist * InpRewardRisk, _Digits);
         g_lastSignalBar = i;
        }

      //--- alert only for the bar that has just closed, and only once
      if(prev_calculated > 0 && i == rates_total - 2 && time[i] != g_lastAlertTime &&
         (BuyBuf[i] != EMPTY_VALUE || SellBuf[i] != EMPTY_VALUE))
        {
         g_lastAlertTime = time[i];
         SendSignalAlert(BuyBuf[i] != EMPTY_VALUE, time[i], entry, SLBuf[i], TPBuf[i]);
        }
     }

   if(InpShowStats && newClosedBar && !MQLInfoInteger(MQL_TESTER))
      UpdateStats(rates_total, high, low);

   return(rates_total);
  }
//+------------------------------------------------------------------+
