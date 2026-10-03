#property strict
#property version   "1.10"
#property description "EA Trend Pullback v1.1: EMA40/80 regime + pullback isolado EMA21/EMA40 + Engolfo/123."
#property description "Entrada stop, stop estrutural, target em R, risco percentual e filtros de custo/spread."

#include <FCSousa/EMA_Trend_Pullback/Types.mqh>
#include <FCSousa/EMA_Trend_Pullback/Logger.mqh>
#include <FCSousa/EMA_Trend_Pullback/MarketData.mqh>
#include <FCSousa/EMA_Trend_Pullback/Strategy.mqh>
#include <FCSousa/EMA_Trend_Pullback/RiskManager.mqh>
#include <FCSousa/EMA_Trend_Pullback/ExecutionManager.mqh>
#include <FCSousa/EMA_Trend_Pullback/TradingSchedule.mqh>

enum ENUM_PULLBACK_EMA_SELECTION
{
   PULLBACK_EMA_21 = 21,
   PULLBACK_EMA_40 = 40
};

//====================================================================
// Indicadores
//====================================================================
input group "Indicadores"
input int InpEMA21Period = 21;
input int InpEMA40Period = 40;
input int InpEMA80Period = 80;
input int InpATRPeriod   = 14;

//====================================================================
// Trend Pullback
//====================================================================
input group "Trend Pullback"
input ENUM_PULLBACK_EMA_SELECTION InpPullbackEMA = PULLBACK_EMA_21;
input double InpPullbackToleranceATR  = 0.10;
input int    InpEntryBufferTicks      = 1;
input int    InpPendingExpirationBars = 3;

//====================================================================
// Formacoes
//====================================================================
input group "Formacoes"
input bool InpUseEngulfing = true;
input bool InpUse123       = true;

//====================================================================
// Direcao, risco e target
//====================================================================
input group "Direcao, risco e target"
input ENUM_EA_DIRECTION_MODE InpTradeDirection = EA_DIRECTION_BOTH;
input double InpRiskPercent = 1.00;
input double InpTargetR     = 1.50;

//====================================================================
// Slope opcional
//====================================================================
input group "Slope EMA40/ATR"
input bool   InpUseEMASlopeFilter = false;
input int    InpEMASlopeLookback  = 5;
input double InpMinEMA40SlopeATR  = 0.0;

//====================================================================
// Custos
//====================================================================
input group "Risco total e custos"
input double InpMaxRoundTripCostRiskPercent        = 10.0;
input double InpMaxVolumeLots                      = 10.0;
input double InpEstimatedRoundTripCommissionPerLot = 0.0;
input double InpRoundTripSlippageReservePoints     = 2.0;

//====================================================================
// Stop / spread
//====================================================================
input group "Stop minimo"
input double InpMinStopPointsAbsolute = 10.0;
input double InpMinStopATRMultiple    = 0.50;

input group "Spread"
input double InpMaxSpreadPoints       = 30.0;
input double InpMinStopSpreadMultiple = 3.0;

//====================================================================
// Horarios
//====================================================================
input group "Kill Time 1"
input bool InpKillTime1Enabled     = true;
input int  InpKillTime1StartHour   = 23;
input int  InpKillTime1StartMinute = 0;
input int  InpKillTime1EndHour     = 23;
input int  InpKillTime1EndMinute   = 59;

input group "Kill Time 2"
input bool InpKillTime2Enabled     = true;
input int  InpKillTime2StartHour   = 0;
input int  InpKillTime2StartMinute = 0;
input int  InpKillTime2EndHour     = 0;
input int  InpKillTime2EndMinute   = 59;

input group "Fim de semana"
input bool InpAvoidWeekend       = true;
input int  InpFridayExitHour     = 20;
input int  InpFridayExitMinute   = 0;
input int  InpMondayResumeHour   = 1;
input int  InpMondayResumeMinute = 0;

//====================================================================
// Execucao
//====================================================================
input group "Execucao"
input ulong InpMagicNumber        = 214082;
input ulong InpDeviationPoints    = 20;
input bool  InpLogDetails         = true;
input int   InpSafetyTimerSeconds = 10;

//====================================================================
// Otimizacao
//====================================================================
input group "Otimizacao"
input int    InpOptimizationMinTrades          = 30;
input double InpOptimizationMaxDrawdownPercent = 25.0;

CLogger           g_logger;
CMarketData       g_market_data;
CStrategy         g_strategy;
CRiskManager      g_risk_manager;
CExecutionManager g_execution_manager;
CTradingSchedule  g_schedule;

ENUM_EA_STATE g_state = EA_STATE_IDLE;
datetime g_last_bar_time = 0;
string g_last_signal_id = "";
ulong g_pending_ticket = 0;
ulong g_position_ticket = 0;

SetupMetrics g_metrics[8];

string g_active_signal_id = "";
string g_active_setup = "";
string g_active_pattern = "";
ENUM_SIGNAL_DIRECTION g_active_direction = SIGNAL_NONE;
bool g_active_executed_counted = false;
double g_active_net_profit = 0.0;

bool UsePB21(void)
{
   return InpPullbackEMA == PULLBACK_EMA_21;
}

bool UsePB40(void)
{
   return InpPullbackEMA == PULLBACK_EMA_40;
}

string PullbackLabel(void)
{
   return UsePB21() ? "PB21" : "PB40";
}

int MetricIndex(const string setup_name,
                const string pattern_name,
                const ENUM_SIGNAL_DIRECTION direction)
{
   if(setup_name == "PB21" && pattern_name == "ENG")
      return direction == SIGNAL_BUY ? 0 : 1;

   if(setup_name == "PB21" && pattern_name == "123")
      return direction == SIGNAL_BUY ? 2 : 3;

   if(setup_name == "PB40" && pattern_name == "ENG")
      return direction == SIGNAL_BUY ? 4 : 5;

   if(setup_name == "PB40" && pattern_name == "123")
      return direction == SIGNAL_BUY ? 6 : 7;

   return -1;
}

string MetricLabel(const int index)
{
   switch(index)
   {
      case 0: return "PB21_ENGULF_BUY";
      case 1: return "PB21_ENGULF_SELL";
      case 2: return "PB21_123_BUY";
      case 3: return "PB21_123_SELL";
      case 4: return "PB40_ENGULF_BUY";
      case 5: return "PB40_ENGULF_SELL";
      case 6: return "PB40_123_BUY";
      case 7: return "PB40_123_SELL";
   }

   return "UNKNOWN";
}

bool ValidHourMinute(const int hour, const int minute)
{
   return hour >= 0 && hour <= 23 &&
          minute >= 0 && minute <= 59;
}

bool ValidateInputs(void)
{
   if(InpEMA21Period <= 0 ||
      InpEMA40Period <= InpEMA21Period ||
      InpEMA80Period <= InpEMA40Period)
   {
      Print("Periodos EMA invalidos.");
      return false;
   }

   if(InpPullbackEMA != PULLBACK_EMA_21 &&
      InpPullbackEMA != PULLBACK_EMA_40)
   {
      Print("InpPullbackEMA deve ser EMA21 ou EMA40.");
      return false;
   }

   if(InpPullbackToleranceATR < 0.0 ||
      !MathIsValidNumber(InpPullbackToleranceATR))
   {
      Print("InpPullbackToleranceATR invalido.");
      return false;
   }

   if(InpEntryBufferTicks < 0)
   {
      Print("InpEntryBufferTicks nao pode ser negativo.");
      return false;
   }

   if(InpPendingExpirationBars < 1 ||
      InpPendingExpirationBars > 100)
   {
      Print("InpPendingExpirationBars deve estar entre 1 e 100.");
      return false;
   }

   if(!InpUseEngulfing && !InpUse123)
   {
      Print("Habilite Engolfo e/ou 123.");
      return false;
   }

   if(InpRiskPercent <= 0.0 || InpRiskPercent > 10.0)
   {
      Print("InpRiskPercent deve estar entre 0 e 10.");
      return false;
   }

   if(InpTargetR <= 0.0 || InpTargetR > 20.0)
   {
      Print("InpTargetR invalido.");
      return false;
   }

   if(InpATRPeriod <= 0 ||
      InpEMASlopeLookback <= 0 ||
      InpMinEMA40SlopeATR < 0.0)
   {
      Print("ATR/slope invalido.");
      return false;
   }

   if(InpMaxRoundTripCostRiskPercent < 0.0 ||
      InpMaxVolumeLots <= 0.0 ||
      InpEstimatedRoundTripCommissionPerLot < 0.0 ||
      InpRoundTripSlippageReservePoints < 0.0)
   {
      Print("Parametros de custo/volume invalidos.");
      return false;
   }

   if(InpMinStopPointsAbsolute < 0.0 ||
      InpMinStopATRMultiple < 0.0 ||
      InpMaxSpreadPoints < 0.0 ||
      InpMinStopSpreadMultiple < 0.0)
   {
      Print("Parametros de stop/spread invalidos.");
      return false;
   }

   if(InpMagicNumber == 0 ||
      InpSafetyTimerSeconds < 1 ||
      InpSafetyTimerSeconds > 60)
   {
      Print("Execucao invalida.");
      return false;
   }

   if(!ValidHourMinute(InpKillTime1StartHour, InpKillTime1StartMinute) ||
      !ValidHourMinute(InpKillTime1EndHour, InpKillTime1EndMinute) ||
      !ValidHourMinute(InpKillTime2StartHour, InpKillTime2StartMinute) ||
      !ValidHourMinute(InpKillTime2EndHour, InpKillTime2EndMinute) ||
      !ValidHourMinute(InpFridayExitHour, InpFridayExitMinute) ||
      !ValidHourMinute(InpMondayResumeHour, InpMondayResumeMinute))
   {
      Print("Horario invalido.");
      return false;
   }

   return true;
}

datetime BrokerTime(void)
{
   datetime value = TimeTradeServer();

   if(value <= 0)
      value = TimeCurrent();

   return value;
}

bool EvaluateSlope(const MarketSnapshot &snapshot,
                   const TechnicalSignal &signal,
                   string &detail)
{
   detail = "";

   if(!InpUseEMASlopeFilter)
      return true;

   double ema40_past = 0.0;
   string error = "";

   if(!g_market_data.LoadEMA40PastValue(
         InpEMASlopeLookback,
         ema40_past,
         error))
   {
      detail = error;
      return false;
   }

   const double denominator =
      InpEMASlopeLookback * snapshot.atr_1;

   if(denominator <= 0.0)
   {
      detail = "Denominador slope invalido.";
      return false;
   }

   const double slope =
      (snapshot.ema40_1 - ema40_past) / denominator;

   bool accepted = false;

   if(signal.direction == SIGNAL_BUY)
      accepted = slope > InpMinEMA40SlopeATR;
   else if(signal.direction == SIGNAL_SELL)
      accepted = slope < -InpMinEMA40SlopeATR;

   detail = StringFormat(
      "slope=%.10f limite=%.10f accepted=%s",
      slope,
      InpMinEMA40SlopeATR,
      accepted ? "true" : "false"
   );

   return accepted;
}

void Reconcile(void)
{
   g_state =
      g_execution_manager.DetectState(
         g_pending_ticket,
         g_position_ticket
      );
}

void ClearActiveContext(void)
{
   g_active_signal_id = "";
   g_active_setup = "";
   g_active_pattern = "";
   g_active_direction = SIGNAL_NONE;
   g_active_executed_counted = false;
   g_active_net_profit = 0.0;
}

void ProcessSafety(void)
{
   const datetime now = BrokerTime();

   if(g_schedule.ShouldForceWeekendFlat(now))
   {
      string message = "";
      g_execution_manager.CancelAllPendingOrders(message);
      Reconcile();
      return;
   }

   string reason = "";

   if(g_schedule.IsKillTime(now, reason) &&
      g_state == EA_STATE_ORDER_PENDING)
   {
      string message = "";
      g_execution_manager.CancelAllPendingOrders(message);

      g_logger.Info(
         "CANCEL_KILL_TIME",
         _Symbol,
         g_active_signal_id,
         reason + " " + message
      );

      Reconcile();
   }

   string weekend_reason = "";

   if(g_schedule.IsWeekendBlocked(now, weekend_reason) &&
      g_state == EA_STATE_ORDER_PENDING)
   {
      string message = "";
      g_execution_manager.CancelAllPendingOrders(message);

      g_logger.Info(
         "CANCEL_WEEKEND",
         _Symbol,
         g_active_signal_id,
         weekend_reason + " " + message
      );

      Reconcile();
   }
}

void ProcessPendingSpreadWatchdog(void)
{
   if(g_state != EA_STATE_ORDER_PENDING)
      return;

   double spread_price = 0.0;
   double spread_points = 0.0;
   string error = "";

   if(!g_execution_manager.GetCurrentSpread(
         spread_price,
         spread_points,
         error))
   {
      // Falha temporaria de dados nao autoriza cancelamento.
      g_logger.Warning(
         "SPREAD_DATA_INVALID",
         _Symbol,
         g_active_signal_id,
         error
      );
      return;
   }

   if(InpMaxSpreadPoints > 0.0 &&
      spread_points > InpMaxSpreadPoints + 1e-9)
   {
      string message = "";
      g_execution_manager.CancelAllPendingOrders(message);

      const int idx =
         MetricIndex(
            g_active_setup,
            g_active_pattern,
            g_active_direction
         );

      if(idx >= 0)
      {
         g_metrics[idx].rejected_spread++;
         g_metrics[idx].pending_not_filled++;
      }

      g_logger.Warning(
         "PENDING_CANCEL_SPREAD",
         _Symbol,
         g_active_signal_id,
         StringFormat(
            "spread=%.2f max=%.2f %s",
            spread_points,
            InpMaxSpreadPoints,
            message
         )
      );

      ClearActiveContext();
      Reconcile();
   }
}

void ProcessIdle(void)
{
   if(g_execution_manager.HasAnyTradingActivityForSymbol())
   {
      Reconcile();
      return;
   }

   MarketSnapshot snapshot = {};
   string error = "";

   if(!g_market_data.LoadSnapshot(snapshot, error))
   {
      g_logger.Warning(
         "MARKET_DATA_ERROR",
         _Symbol,
         "",
         error
      );
      return;
   }

   TechnicalSignal signal = {};

   if(!g_strategy.DetectSignal(snapshot, signal, error))
      return;

   if(signal.signal_id == g_last_signal_id)
      return;

   g_last_signal_id = signal.signal_id;

   const int idx =
      MetricIndex(
         signal.setup_name,
         signal.pattern_name,
         signal.direction
      );

   if(idx >= 0)
      g_metrics[idx].signals++;

   string slope_detail = "";

   if(!EvaluateSlope(snapshot, signal, slope_detail))
   {
      if(idx >= 0)
         g_metrics[idx].rejected_regime++;

      g_logger.Info(
         "SIGNAL_REJECTED_SLOPE",
         _Symbol,
         signal.signal_id,
         slope_detail
      );
      return;
   }

   TradePlan plan = {};

   if(!g_strategy.BuildTradePlan(
         snapshot,
         signal,
         plan,
         error))
   {
      g_logger.Warning(
         "PLAN_REJECTED",
         _Symbol,
         signal.signal_id,
         error
      );
      return;
   }

   const datetime now = BrokerTime();
   string time_reason = "";

   if(g_schedule.IsWeekendBlocked(now, time_reason) ||
      g_schedule.IsKillTime(now, time_reason))
   {
      if(idx >= 0)
         g_metrics[idx].rejected_time++;

      g_logger.Info(
         "ENTRY_BLOCKED_BY_TIME",
         _Symbol,
         signal.signal_id,
         time_reason
      );
      return;
   }

   string validation_error = "";

   if(!g_execution_manager.ValidatePlan(
         plan,
         snapshot.spread_points,
         validation_error))
   {
      if(idx >= 0)
      {
         if(StringFind(validation_error, "Spread") >= 0)
            g_metrics[idx].rejected_spread++;
         else
            g_metrics[idx].rejected_stop++;
      }

      g_logger.Info(
         "ORDER_PREPARATION_REJECTED",
         _Symbol,
         signal.signal_id,
         validation_error
      );
      return;
   }

   RiskResult risk = {};

   if(!g_risk_manager.Calculate(
         _Symbol,
         plan,
         snapshot.spread_points,
         risk))
   {
      if(idx >= 0 &&
         StringFind(risk.message, "Custo") >= 0)
      {
         g_metrics[idx].rejected_cost++;
      }

      g_logger.Info(
         "RISK_REJECTED",
         _Symbol,
         signal.signal_id,
         risk.message
      );
      return;
   }

   ExecutionResult execution = {};

   if(!g_execution_manager.Submit(
         plan,
         risk,
         execution))
   {
      if(idx >= 0)
      {
         if(StringFind(execution.message, "Spread") >= 0)
            g_metrics[idx].rejected_spread++;
         else if(StringFind(execution.message, "Stop") >= 0)
            g_metrics[idx].rejected_stop++;
      }

      g_logger.Error(
         "ORDER_REJECTED",
         _Symbol,
         signal.signal_id,
         execution.message
      );
      return;
   }

   g_active_signal_id = signal.signal_id;
   g_active_setup = signal.setup_name;
   g_active_pattern = signal.pattern_name;
   g_active_direction = signal.direction;
   g_active_executed_counted = false;
   g_active_net_profit = 0.0;

   g_state = EA_STATE_ORDER_PENDING;
   g_pending_ticket = execution.order_ticket;

   g_logger.Info(
      "ORDER_PLACED",
      _Symbol,
      signal.signal_id,
      StringFormat(
         "bucket=%s ticket=%I64u volume=%.2f entry=%.*f SL=%.*f TP=%.*f expiration=%s cost/risk=%.2f%%",
         idx >= 0 ? MetricLabel(idx) : "UNKNOWN",
         execution.order_ticket,
         risk.volume,
         _Digits,
         execution.normalized_entry_price,
         _Digits,
         execution.normalized_stop_price,
         _Digits,
         execution.normalized_target_price,
         TimeToString(plan.expiration, TIME_DATE|TIME_MINUTES),
         risk.round_trip_cost_risk_percent
      )
   );
}

void ProcessNewBar(void)
{
   Reconcile();

   if(g_state == EA_STATE_IDLE)
      ProcessIdle();
}

int OnInit(void)
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_logger.Configure(InpLogDetails);

   string error = "";

   if(!g_market_data.Initialize(
         _Symbol,
         (ENUM_TIMEFRAMES)_Period,
         InpEMA21Period,
         InpEMA40Period,
         InpEMA80Period,
         InpATRPeriod,
         error))
   {
      g_logger.Error(
         "MARKET_DATA_INIT_ERROR",
         _Symbol,
         "",
         error
      );
      return INIT_FAILED;
   }

   g_strategy.Configure(
      UsePB21(),
      UsePB40(),
      InpUseEngulfing,
      InpUse123,
      false,
      InpPullbackToleranceATR,
      InpEntryBufferTicks,
      InpPendingExpirationBars,
      InpTargetR,
      InpRiskPercent,
      InpTradeDirection
   );

   g_risk_manager.Configure(
      InpMaxRoundTripCostRiskPercent,
      InpMaxVolumeLots,
      InpEstimatedRoundTripCommissionPerLot,
      InpRoundTripSlippageReservePoints
   );

   g_execution_manager.Configure(
      _Symbol,
      InpMagicNumber,
      InpDeviationPoints,
      InpMaxSpreadPoints,
      InpMinStopSpreadMultiple,
      InpMinStopPointsAbsolute,
      InpMinStopATRMultiple
   );

   g_schedule.Configure(
      InpKillTime1Enabled,
      InpKillTime1StartHour,
      InpKillTime1StartMinute,
      InpKillTime1EndHour,
      InpKillTime1EndMinute,
      InpKillTime2Enabled,
      InpKillTime2StartHour,
      InpKillTime2StartMinute,
      InpKillTime2EndHour,
      InpKillTime2EndMinute,
      InpAvoidWeekend,
      InpFridayExitHour,
      InpFridayExitMinute,
      InpMondayResumeHour,
      InpMondayResumeMinute
   );

   for(int i = 0; i < 8; i++)
      ZeroMemory(g_metrics[i]);

   g_last_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(g_last_bar_time <= 0)
      return INIT_FAILED;

   Reconcile();

   if(!EventSetTimer(InpSafetyTimerSeconds))
   {
      g_logger.Error(
         "TIMER_ERROR",
         _Symbol,
         "",
         StringFormat("erro=%d", GetLastError())
      );
      return INIT_FAILED;
   }

   g_logger.Info(
      "EA_INITIALIZED",
      _Symbol,
      "",
      StringFormat(
         "version=1.10 TF=%s pullback=%s ENG=%s 123=%s tolerance=%.2fATR buffer=%dticks expiration=%dbars target=%.2fR risk=%.2f%% cost/risk=%.2f%% slope=%s",
         EnumToString((ENUM_TIMEFRAMES)_Period),
         PullbackLabel(),
         InpUseEngulfing ? "ON" : "OFF",
         InpUse123 ? "ON" : "OFF",
         InpPullbackToleranceATR,
         InpEntryBufferTicks,
         InpPendingExpirationBars,
         InpTargetR,
         InpRiskPercent,
         InpMaxRoundTripCostRiskPercent,
         InpUseEMASlopeFilter ? "ON" : "OFF"
      )
   );

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   for(int i = 0; i < 8; i++)
   {
      g_logger.Info(
         "SETUP_METRICS_FINAL",
         _Symbol,
         "",
         StringFormat(
            "bucket=%s signals=%I64u rejected_regime=%I64u rejected_cost=%I64u rejected_spread=%I64u rejected_stop=%I64u rejected_time=%I64u pending_not_filled=%I64u executed=%I64u wins=%I64u losses=%I64u net_profit=%.2f",
            MetricLabel(i),
            g_metrics[i].signals,
            g_metrics[i].rejected_regime,
            g_metrics[i].rejected_cost,
            g_metrics[i].rejected_spread,
            g_metrics[i].rejected_stop,
            g_metrics[i].rejected_time,
            g_metrics[i].pending_not_filled,
            g_metrics[i].executed,
            g_metrics[i].wins,
            g_metrics[i].losses,
            g_metrics[i].net_profit
         )
      );
   }

   g_market_data.Release();

   g_logger.Info(
      "EA_DEINITIALIZED",
      _Symbol,
      "",
      StringFormat("reason=%d", reason)
   );
}

void OnTick(void)
{
   ProcessSafety();
   ProcessPendingSpreadWatchdog();

   const datetime current_bar =
      iTime(_Symbol, PERIOD_CURRENT, 0);

   if(current_bar <= 0 ||
      current_bar == g_last_bar_time)
   {
      return;
   }

   g_last_bar_time = current_bar;
   ProcessNewBar();
}

void OnTimer(void)
{
   Reconcile();
   ProcessSafety();
   ProcessPendingSpreadWatchdog();
}

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(transaction.type == TRADE_TRANSACTION_DEAL_ADD &&
      transaction.deal > 0 &&
      HistoryDealSelect(transaction.deal))
   {
      if(HistoryDealGetString(transaction.deal, DEAL_SYMBOL) == _Symbol &&
         (ulong)HistoryDealGetInteger(transaction.deal, DEAL_MAGIC) == InpMagicNumber)
      {
         const ENUM_DEAL_ENTRY entry =
            (ENUM_DEAL_ENTRY)HistoryDealGetInteger(
               transaction.deal,
               DEAL_ENTRY
            );

         const int idx =
            MetricIndex(
               g_active_setup,
               g_active_pattern,
               g_active_direction
            );

         if((entry == DEAL_ENTRY_IN ||
             entry == DEAL_ENTRY_INOUT) &&
            !g_active_executed_counted)
         {
            g_active_executed_counted = true;

            if(idx >= 0)
               g_metrics[idx].executed++;

            g_logger.Info(
               "DEAL_EXECUTED",
               _Symbol,
               g_active_signal_id,
               StringFormat(
                  "deal=%I64u bucket=%s",
                  transaction.deal,
                  idx >= 0 ? MetricLabel(idx) : "UNKNOWN"
               )
            );
         }

         g_active_net_profit +=
            HistoryDealGetDouble(transaction.deal, DEAL_PROFIT) +
            HistoryDealGetDouble(transaction.deal, DEAL_COMMISSION) +
            HistoryDealGetDouble(transaction.deal, DEAL_FEE) +
            HistoryDealGetDouble(transaction.deal, DEAL_SWAP);
      }
   }

   const ENUM_EA_STATE old_state = g_state;
   Reconcile();

   if(old_state == EA_STATE_ORDER_PENDING &&
      g_state == EA_STATE_IDLE &&
      !g_active_executed_counted &&
      g_active_signal_id != "")
   {
      const int idx =
         MetricIndex(
            g_active_setup,
            g_active_pattern,
            g_active_direction
         );

      if(idx >= 0)
         g_metrics[idx].pending_not_filled++;

      g_logger.Info(
         "PENDING_NOT_FILLED",
         _Symbol,
         g_active_signal_id,
         "Ordem encerrou sem fill."
      );

      ClearActiveContext();
   }

   if(old_state == EA_STATE_POSITION_OPEN &&
      g_state == EA_STATE_IDLE &&
      g_active_signal_id != "")
   {
      const int idx =
         MetricIndex(
            g_active_setup,
            g_active_pattern,
            g_active_direction
         );

      if(idx >= 0)
      {
         g_metrics[idx].net_profit += g_active_net_profit;

         if(g_active_net_profit > 1e-8)
            g_metrics[idx].wins++;
         else if(g_active_net_profit < -1e-8)
            g_metrics[idx].losses++;
      }

      g_logger.Info(
         "TRADE_RESULT",
         _Symbol,
         g_active_signal_id,
         StringFormat(
            "bucket=%s net_profit=%.2f",
            idx >= 0 ? MetricLabel(idx) : "UNKNOWN",
            g_active_net_profit
         )
      );

      ClearActiveContext();
   }
}

double OnTester(void)
{
   const double trades = TesterStatistics(STAT_TRADES);
   const double profit = TesterStatistics(STAT_PROFIT);

   double profit_factor =
      TesterStatistics(STAT_PROFIT_FACTOR);

   double recovery_factor =
      TesterStatistics(STAT_RECOVERY_FACTOR);

   double sharpe =
      TesterStatistics(STAT_SHARPE_RATIO);

   double drawdown =
      TesterStatistics(STAT_EQUITY_DDREL_PERCENT);

   if(!MathIsValidNumber(trades) || trades < 0.0)
      return -1.0e12;

   if(InpOptimizationMinTrades > 0 &&
      trades < InpOptimizationMinTrades)
   {
      return -1.0e9 + trades;
   }

   if(!MathIsValidNumber(profit_factor) ||
      profit_factor < 0.0)
   {
      profit_factor = 0.0;
   }

   if(!MathIsValidNumber(recovery_factor))
      recovery_factor = 0.0;

   if(!MathIsValidNumber(sharpe))
      sharpe = 0.0;

   if(!MathIsValidNumber(drawdown) ||
      drawdown < 0.0)
   {
      drawdown = 100.0;
   }

   profit_factor = MathMin(profit_factor, 10.0);

   recovery_factor =
      MathMax(
         -10.0,
         MathMin(recovery_factor, 10.0)
      );

   sharpe =
      MathMax(
         -5.0,
         MathMin(sharpe, 5.0)
      );

   drawdown = MathMin(drawdown, 100.0);

   double score =
      profit_factor * 35.0 +
      recovery_factor * 25.0 +
      sharpe * 20.0 +
      MathLog(1.0 + trades) * 5.0 -
      drawdown * 2.0;

   if(profit <= 0.0)
      score -= 200.0;

   if(InpOptimizationMaxDrawdownPercent > 0.0 &&
      drawdown > InpOptimizationMaxDrawdownPercent)
   {
      score -=
         (drawdown -
          InpOptimizationMaxDrawdownPercent) * 10.0;
   }

   return score;
}
