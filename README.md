# MT5 Majors Trend Signal

A rule-based buy/sell arrow indicator for MetaTrader 5, tuned for the major forex pairs
(EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD), plus a small Expert Advisor that
trades its signals so you can measure the real results in the Strategy Tester.

> **Honest warning:** no indicator wins 100% of the time. Anything sold as "100% win" is either
> repainting (moving its arrows after the fact) or hiding losses. This indicator is built to
> **never repaint** and to give **fewer, higher-quality** signals, each with a stop loss and take
> profit. Always backtest and demo-trade it before using real money.

## How the signals work

Everything is checked on the **closed** candle, so once an arrow appears it never moves or
disappears.

| Filter | BUY | SELL |
|---|---|---|
| Trend | Close above EMA 200, EMA 21 above EMA 200, EMA 200 rising over 10 bars | Mirror image |
| Trigger | EMA 9 crosses above EMA 21 | EMA 9 crosses below EMA 21 |
| Momentum | RSI(14) between 50 and 70 (not overbought) | RSI between 30 and 50 (not oversold) |
| Trend strength | ADX(14) at least 20 (skip choppy markets) | Same |
| Candle | Bullish close | Bearish close |
| Session | 07:00 to 20:00 broker server time (London + New York) | Same |
| Cooldown | At least 5 bars since the previous signal | Same |

Each signal comes with a suggested **stop loss = 1.5 × ATR(14)** from the entry and
**take profit = 2 × the stop distance** (1:2 reward to risk). Both values are shown in the alert and
in the Data Window (Ctrl+D).

At 1:2 you only need to win more than **33.3%** of trades to break even. A higher win rate is easy
to get by lowering `Take profit = SL distance x this` (for example 1.0), but that does not
automatically mean more profit. Judge the system by **net result and profit factor**, not win rate alone.

**Suggested timeframe:** H1 (also try M30 and H4). Very low timeframes (M1 to M5) produce more
noise and spread eats a bigger share of each trade.

## Install

1. In MT5 open **File → Open Data Folder**.
2. Copy `MQL5/Indicators/MajorsTrendSignal.mq5` into the `MQL5/Indicators/` folder there.
3. Copy `MQL5/Experts/MajorsTrendSignalEA.mq5` into the `MQL5/Experts/` folder there.
4. Open **MetaEditor** (F4), open each file and press **Compile** (F7). Compile the indicator first.
5. Back in MT5, right-click **Indicators** in the Navigator → **Refresh**, then drag
   **MajorsTrendSignal** onto an H1 chart of a major pair.

On the chart you will see the grey EMA 200 line, green up arrows (buy), red down arrows (sell), and
a panel in the top-left with the historical win rate on that chart (see below).

### Alerts

In the indicator inputs you can switch on pop-up, sound, mobile push and e-mail alerts.
Alerts fire once, right after the signal candle closes. For push notifications, enter your MetaQuotes
ID under **Tools → Options → Notifications**.

## Measure the real win rate

### Quick check: the on-chart panel

The panel walks every arrow in the last 3000 bars forward and records whether the stop loss or
take profit was hit first (if both were hit in the same candle it counts as a loss). It ignores
spread and slippage, so treat it as a rough first look and compare pairs and timeframes with it.

### Proper backtest: Strategy Tester

1. Press **Ctrl+R** to open the Strategy Tester.
2. Expert: **MajorsTrendSignalEA**. Symbol: for example EURUSD. Timeframe: H1.
3. Date range: at least the last 2 to 3 years.
4. Modelling: **Every tick based on real ticks** (most accurate) or **Every tick**.
5. Deposit and leverage: what you would really use. Default risk is 1% of balance per trade.
6. Press **Start**. Then read the **Backtest** tab:
   - **Profit Trades (% of total)**: the real win rate including spread.
   - **Profit Factor**: above 1.3 is decent, below 1.0 means it loses money.
   - **Maximal / Relative Drawdown**: the worst losing stretch you would have had to sit through.
7. Repeat for each major pair. Only trade the pairs and timeframes that hold up across several years.

To compare settings, use the **Optimization** option in the tester, but keep it simple (for example
only `InpRewardRisk`, `InpSLATRMult` and `InpADXMin`), and always check the best result on a later
period you did **not** optimise on. Otherwise you are only fitting the past.

The EA opens at most one trade per pair at a time and only uses the indicator's SL and TP. It can
also run on a demo account to forward-test the signals.

## Inputs (indicator)

| Input | Default | Meaning |
|---|---|---|
| Fast / Slow / Trend EMA | 9 / 21 / 200 | Trigger cross and direction filter |
| Trend slope bars | 10 | EMA 200 must rise (buy) or fall (sell) over this many bars, 0 = off |
| RSI period, buy min/max, sell min/max | 14, 50/70, 30/50 | Momentum confirmation |
| ADX period / min | 14 / 20 | Skip weak, sideways markets |
| ATR period / SL multiplier | 14 / 1.5 | Stop loss distance |
| Reward:risk | 2.0 | Take profit distance as a multiple of the stop |
| Require candle | true | Signal candle must close in the trade direction |
| Cooldown bars | 5 | Minimum bars between signals |
| Session filter / start / end | true / 7 / 20 | Broker server hours to allow signals |
| Alerts | pop-up + sound on | Pop-up, sound, push, e-mail |
| Show stats / stats bars | true / 3000 | On-chart win-rate panel |

## Risk

Trading forex with leverage carries a high risk of loss. This code is provided for education and
testing. Past backtest results do not guarantee future results.
