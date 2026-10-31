//+------------------------------------------------------------------+
//|                                          MajorsTrendSignalEA.mq5 |
//|  Trades the MajorsTrendSignal arrows so you can measure the real |
//|  win rate, drawdown and profit factor in the Strategy Tester     |
//|  (with real spread). One position per symbol, fixed SL/TP taken  |
//|  from the indicator.                                             |
//+------------------------------------------------------------------+
#property copyright   "georgefrancis81-ai"
#property link        "https://github.com/georgefrancis81-ai/mt5-signal-indicator"
#property version     "1.00"
#property description "Backtest/auto-trade helper for the MajorsTrendSignal indicator."
#property tester_indicator "MajorsTrendSignal.ex5"

#include <Trade\Trade.mqh>

//--- trade settings
input double InpRiskPercent    = 1.0;    // Risk per trade, % of balance (0 = use fixed lots)
input double InpFixedLots      = 0.10;   // Fixed lots (used when risk % = 0)
input ulong  InpMagic          = 20261031; // Magic number
input int    InpMaxSpreadPts   = 30;     // Skip signal if spread > this many points (0 = off)

//--- indicator settings (same meaning and defaults as the indicator)
input int    InpFastEMA        = 9;
input int    InpSlowEMA        = 21;
input int    InpTrendEMA       = 200;
input int    InpTrendSlopeBars = 10;
input int    InpRSIPeriod      = 14;
input double InpRSIBuyMin      = 50.0;
input double InpRSIBuyMax      = 70.0;
input double InpRSISellMin     = 30.0;
input double InpRSISellMax     = 50.0;
input int    InpADXPeriod      = 14;
input double InpADXMin         = 20.0;
input int    InpATRPeriod      = 14;
input double InpSLATRMult      = 1.5;
input double InpRewardRisk     = 2.0;
input bool   InpRequireCandle  = true;
input int    InpCooldownBars   = 5;
input bool   InpUseSession     = true;
input int    InpSessionStart   = 7;
input int    InpSessionEnd     = 20;

CTrade   trade;
int      hSignal = INVALID_HANDLE;
datetime g_lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   hSignal = iCustom(_Symbol, _Period, "MajorsTrendSignal",
                     InpFastEMA, InpSlowEMA, InpTrendEMA, InpTrendSlopeBars,
                     InpRSIPeriod, InpRSIBuyMin, InpRSIBuyMax, InpRSISellMin, InpRSISellMax,
                     InpADXPeriod, InpADXMin, InpATRPeriod, InpSLATRMult, InpRewardRisk,
                     InpRequireCandle, InpCooldownBars, InpUseSession, InpSessionStart, InpSessionEnd,
                     false, false, false, false,   // no alerts from inside the EA
                     false, 0);                    // no stats panel
   if(hSignal == INVALID_HANDLE)
     {
      Print("MajorsTrendSignalEA: cannot load indicator MajorsTrendSignal (compile it in MQL5\\Indicators first). Error ",
            GetLastError());
      return(INIT_FAILED);
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hSignal != INVALID_HANDLE)
      IndicatorRelease(hSignal);
  }

//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
double LotsForRisk(const double slDistance)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lots    = InpFixedLots;

   if(InpRiskPercent > 0.0)
     {
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal <= 0.0 || tickSize <= 0.0 || slDistance <= 0.0)
         return(0.0);
      double lossPerLot = slDistance / tickSize * tickVal;
      double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
      lots = riskMoney / lossPerLot;
     }

   if(step > 0.0)
      lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return(NormalizeDouble(lots, 2));
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- act once per new bar, on the bar that just closed (shift 1)
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == 0 || barTime == g_lastBar)
      return;

   double buy[1], sell[1], sl[1], tp[1];
   if(CopyBuffer(hSignal, 1, 1, 1, buy)  != 1 ||
      CopyBuffer(hSignal, 2, 1, 1, sell) != 1 ||
      CopyBuffer(hSignal, 3, 1, 1, sl)   != 1 ||
      CopyBuffer(hSignal, 4, 1, 1, tp)   != 1)
      return;                       // indicator not ready yet, retry next tick
   g_lastBar = barTime;

   bool isBuy  = buy[0]  != EMPTY_VALUE && buy[0]  != 0.0;
   bool isSell = sell[0] != EMPTY_VALUE && sell[0] != 0.0;
   if(!isBuy && !isSell)
      return;
   if(HasOpenPosition())
      return;

   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPts > 0 && spreadPts > InpMaxSpreadPts)
     {
      PrintFormat("Signal skipped: spread %d > %d points", (int)spreadPts, InpMaxSpreadPts);
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(isBuy)
     {
      if(sl[0] >= bid || tp[0] <= ask)
         return;                    // price already beyond SL/TP since the close
      double lots = LotsForRisk(ask - sl[0]);
      if(lots > 0.0)
         trade.Buy(lots, _Symbol, ask, sl[0], tp[0], "MajorsTrendSignal BUY");
     }
   else
     {
      if(sl[0] <= ask || tp[0] >= bid)
         return;
      double lots = LotsForRisk(sl[0] - bid);
      if(lots > 0.0)
         trade.Sell(lots, _Symbol, bid, sl[0], tp[0], "MajorsTrendSignal SELL");
     }
  }
//+------------------------------------------------------------------+
