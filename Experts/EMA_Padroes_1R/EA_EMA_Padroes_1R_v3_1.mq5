//+------------------------------------------------------------------+
//|                                  EA_EMA_Padroes_1R_v3_1.mq5       |
//| EMA21/40/80 + 123, PFR ou Engolfo + risco percentual            |
//| Versao 3.10: horarios, rollover, weekend, spread e alvo em R    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.10"
#property description "EA modular EMA21/40/80 com padroes 123, PFR e Engolfo completo."
#property description "Inclui prioridade de padroes, direcao, alvo em R, kill times, rollover, weekend e filtros de spread."

#include <EMA_Padroes_1R/Types.mqh>
#include <EMA_Padroes_1R/Logger.mqh>
#include <EMA_Padroes_1R/MarketData.mqh>
#include <EMA_Padroes_1R/Strategy.mqh>
#include <EMA_Padroes_1R/RiskManager.mqh>
#include <EMA_Padroes_1R/ExecutionManager.mqh>
#include <EMA_Padroes_1R/TradingSchedule.mqh>

//====================================================================
// Indicadores
//====================================================================
input group "Indicadores"
input int      InpEMA21Period       = 21;    // EMA de gatilho
input int      InpEMA40Period       = 40;    // EMA de contexto intermediaria
input int      InpEMA80Period       = 80;    // EMA de contexto longa
input bool     InpShowEMAs          = true;  // Exibir EMAs no grafico

//====================================================================
// Formacoes e prioridade
// Quando mais de um padrao ocorrer no mesmo candle, somente o primeiro
// padrao valido da ordem abaixo sera usado para entrada, stop e log.
//====================================================================
input group "Formacoes e prioridade"
input bool            InpUse123             = true;
input bool            InpUsePFR             = true;
input bool            InpUseEngulfing       = true;
input ENUM_EA_PATTERN InpPatternPriority1   = EA_PATTERN_123;
input ENUM_EA_PATTERN InpPatternPriority2   = EA_PATTERN_PFR;
input ENUM_EA_PATTERN InpPatternPriority3   = EA_PATTERN_ENGULFING;

//====================================================================
// Direcao, risco e alvo
//====================================================================
input group "Direcao, risco e alvo"
input ENUM_EA_DIRECTION_MODE InpTradeDirection = EA_DIRECTION_BOTH;
input double                 InpRiskPercent    = 1.00;  // % do saldo
input double                 InpTargetR        = 1.00;  // alvo = risco x R

//====================================================================
// Filtros de spread
// Pontos usam SYMBOL_POINT. Exemplo EURUSD com 5 digitos: 10 pontos = 1 pip.
// InpMinStopSpreadMultiple=3 exige stop operacional >= 3 x spread atual.
// Use zero para desabilitar qualquer um dos filtros.
//====================================================================
input group "Filtros de spread"
input double InpMaxSpreadPoints       = 30.0;
input double InpMinStopSpreadMultiple = 3.0;

//====================================================================
// Kill Time 1 - horario do servidor da corretora
// Padrao: bloqueia entradas das 23:00 ate 23:59.
//====================================================================
input group "Kill Time 1 - horario do servidor"
input bool InpKillTime1Enabled     = true;
input int  InpKillTime1StartHour   = 23;
input int  InpKillTime1StartMinute = 0;
input int  InpKillTime1EndHour     = 23;
input int  InpKillTime1EndMinute   = 59;

//====================================================================
// Kill Time 2 - horario do servidor da corretora
// Padrao: bloqueia entradas das 00:00 ate 00:59.
//====================================================================
input group "Kill Time 2 - horario do servidor"
input bool InpKillTime2Enabled     = true;
input int  InpKillTime2StartHour   = 0;
input int  InpKillTime2StartMinute = 0;
input int  InpKillTime2EndHour     = 0;
input int  InpKillTime2EndMinute   = 59;

//====================================================================
// Protecao de rollover
// Cancela ordens pendentes do EA antes do horario configurado e bloqueia
// novas entradas durante a janela preventiva.
//====================================================================
input group "Protecao de rollover - horario do servidor"
input bool InpCancelBeforeRollover      = true;
input int  InpRolloverHour              = 0;
input int  InpRolloverMinute            = 0;
input int  InpRolloverCancelLeadMinutes = 15;

//====================================================================
// Protecao de fim de semana
// Na sexta, a partir do horario configurado, cancela pendentes e envia
// posicoes deste Magic Number para fechamento. Entradas permanecem
// bloqueadas ate o horario de retomada de segunda-feira.
//====================================================================
input group "Protecao de fim de semana - horario do servidor"
input bool InpAvoidWeekend       = true;
input int  InpFridayExitHour     = 20;
input int  InpFridayExitMinute   = 0;
input int  InpMondayResumeHour   = 1;
input int  InpMondayResumeMinute = 0;

//====================================================================
// Execucao
//====================================================================
input group "Execucao"
input ulong InpMagicNumber     = 214080;
input ulong InpDeviationPoints = 20;
input bool  InpLogDetails      = true;
input int   InpSafetyTimerSeconds = 10; // watchdog de horario/seguranca

CLogger           g_logger;
CMarketData       g_market_data;
CStrategy         g_strategy;
CRiskManager      g_risk_manager;
CExecutionManager g_execution_manager;
CTradingSchedule  g_trading_schedule;

ENUM_EA_STATE g_ea_state = EA_STATE_IDLE;
datetime      g_last_bar_time = 0;
datetime      g_last_safety_minute = 0;
datetime      g_last_spread_check_second = 0;
ulong         g_pending_order_ticket = 0;
ulong         g_position_ticket = 0;
string        g_last_processed_signal_id = "";

int           g_visual_indicator_handle = INVALID_HANDLE;
string        g_visual_indicator_short_name = "";

// Retorna true somente no modo visual do Strategy Tester.
bool IsTesterVisualMode(void)
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      return false;

   return (bool)MQLInfoInteger(MQL_VISUAL_MODE);
  }

string DirectionToString(const ENUM_SIGNAL_DIRECTION direction)
  {
   if(direction == SIGNAL_BUY)
      return "COMPRA";

   if(direction == SIGNAL_SELL)
      return "VENDA";

   return "SEM_DIRECAO";
  }

bool IsValidHourMinute(const int hour, const int minute)
  {
   return(
      hour >= 0 && hour <= 23 &&
      minute >= 0 && minute <= 59
   );
  }

// Retorna o horario estimado do servidor da corretora. No tester ou em
// indisponibilidade temporaria, utiliza TimeCurrent como fallback seguro.
datetime GetBrokerServerTime(void)
  {
   datetime server_time = TimeTradeServer();
   if(server_time <= 0)
      server_time = TimeCurrent();

   return server_time;
  }

bool ValidateInputs(void)
  {
   if(InpEMA21Period <= 0 ||
      InpEMA40Period <= InpEMA21Period ||
      InpEMA80Period <= InpEMA40Period)
     {
      Print("Periodos invalidos: use EMA21 > 0, EMA40 > EMA21 e EMA80 > EMA40.");
      return false;
     }

   if(InpRiskPercent <= 0.0 || InpRiskPercent > 10.0)
     {
      Print("InpRiskPercent deve estar entre 0 e 10 por cento.");
      return false;
     }

   if(InpTargetR <= 0.0 || InpTargetR > 20.0)
     {
      Print("InpTargetR deve ser maior que zero e menor ou igual a 20.");
      return false;
     }

   if(InpMaxSpreadPoints < 0.0 || InpMinStopSpreadMultiple < 0.0)
     {
      Print("Filtros de spread nao podem ser negativos.");
      return false;
     }

   if(!InpUse123 && !InpUsePFR && !InpUseEngulfing)
     {
      Print("Habilite pelo menos uma formacao operacional.");
      return false;
     }

   if(InpPatternPriority1 == InpPatternPriority2 ||
      InpPatternPriority1 == InpPatternPriority3 ||
      InpPatternPriority2 == InpPatternPriority3)
     {
      Print("As tres prioridades de padrao devem ser diferentes.");
      return false;
     }

   if(InpMagicNumber == 0)
     {
      Print("InpMagicNumber deve ser maior que zero.");
      return false;
     }

   if(InpSafetyTimerSeconds < 1 || InpSafetyTimerSeconds > 60)
     {
      Print("InpSafetyTimerSeconds deve estar entre 1 e 60 segundos.");
      return false;
     }

   if(!IsValidHourMinute(InpKillTime1StartHour, InpKillTime1StartMinute) ||
      !IsValidHourMinute(InpKillTime1EndHour, InpKillTime1EndMinute) ||
      !IsValidHourMinute(InpKillTime2StartHour, InpKillTime2StartMinute) ||
      !IsValidHourMinute(InpKillTime2EndHour, InpKillTime2EndMinute) ||
      !IsValidHourMinute(InpRolloverHour, InpRolloverMinute) ||
      !IsValidHourMinute(InpFridayExitHour, InpFridayExitMinute) ||
      !IsValidHourMinute(InpMondayResumeHour, InpMondayResumeMinute))
     {
      Print("Existe horario invalido nos filtros operacionais.");
      return false;
     }

   if(InpRolloverCancelLeadMinutes < 0 ||
      InpRolloverCancelLeadMinutes > 360)
     {
      Print("InpRolloverCancelLeadMinutes deve estar entre 0 e 360.");
      return false;
     }

   return true;
  }

bool InitializeVisualIndicator(string &error)
  {
   error = "";

   if(!InpShowEMAs)
      return true;

   const bool is_tester = (bool)MQLInfoInteger(MQL_TESTER);
   if(is_tester && !IsTesterVisualMode())
      return true;

   g_visual_indicator_short_name = StringFormat(
      "EMA 21/40/80 (%d,%d,%d)",
      InpEMA21Period,
      InpEMA40Period,
      InpEMA80Period
   );

   ResetLastError();
   g_visual_indicator_handle = iCustom(
      _Symbol,
      PERIOD_CURRENT,
      "EMA_21_40_80_Visual_v3_1",
      InpEMA21Period,
      InpEMA40Period,
      InpEMA80Period
   );

   if(g_visual_indicator_handle == INVALID_HANDLE)
     {
      error = StringFormat(
         "Falha ao criar indicador visual das EMAs. erro=%d",
         GetLastError()
      );
      return false;
     }

   // No tester visual, o indicador e adicionado automaticamente.
   if(is_tester)
      return true;

   ResetLastError();
   if(!ChartIndicatorAdd(0, 0, g_visual_indicator_handle))
     {
      error = StringFormat(
         "ChartIndicatorAdd falhou para as EMAs. erro=%d",
         GetLastError()
      );

      IndicatorRelease(g_visual_indicator_handle);
      g_visual_indicator_handle = INVALID_HANDLE;
      return false;
     }

   return true;
  }

void ReleaseVisualIndicator(void)
  {
   if(g_visual_indicator_short_name != "")
      ChartIndicatorDelete(0, 0, g_visual_indicator_short_name);

   if(g_visual_indicator_handle != INVALID_HANDLE)
     {
      IndicatorRelease(g_visual_indicator_handle);
      g_visual_indicator_handle = INVALID_HANDLE;
     }

   g_visual_indicator_short_name = "";
  }

void EnterErrorState(const string reason)
  {
   g_ea_state = EA_STATE_ERROR;
   g_logger.Error("EA_BLOCKED", _Symbol, "", reason);
  }

bool ReconcileState(void)
  {
   ENUM_EA_STATE recovered_state = EA_STATE_IDLE;
   ulong pending_ticket = 0;
   ulong position_ticket = 0;
   string error = "";

   if(!g_execution_manager.RecoverState(
         recovered_state,
         pending_ticket,
         position_ticket,
         error
      ))
     {
      EnterErrorState(error);
      return false;
     }

   g_ea_state = recovered_state;
   g_pending_order_ticket = pending_ticket;
   g_position_ticket = position_ticket;
   return true;
  }

// Executa protecoes independentes do sinal: rollover e fim de semana.
// O controle por minuto evita repeticao excessiva de ordens e logs.
void ProcessSafetyControls(const bool force_execution)
  {
   const datetime server_time = GetBrokerServerTime();
   if(server_time <= 0)
      return;

   const datetime minute_stamp = (datetime)(
      (long)server_time - ((long)server_time % 60)
   );

   if(!force_execution && minute_stamp == g_last_safety_minute)
      return;

   g_last_safety_minute = minute_stamp;

   if(g_trading_schedule.ShouldCancelPendingForRollover(server_time))
     {
      OperationResult cancel_result = {};
      if(!g_execution_manager.CancelAllPendingOrders(cancel_result))
        {
         g_logger.Warning(
            "ROLLOVER_CANCEL_REJECTED",
            _Symbol,
            "",
            cancel_result.message
         );
        }
      else if(StringFind(cancel_result.message, "0 ordem") != 0)
        {
         g_logger.Info(
            "ROLLOVER_ORDERS_CANCELLED",
            _Symbol,
            "",
            cancel_result.message
         );
        }
     }

   if(g_trading_schedule.ShouldForceWeekendFlat(server_time))
     {
      OperationResult cancel_result = {};
      if(!g_execution_manager.CancelAllPendingOrders(cancel_result))
        {
         g_logger.Warning(
            "WEEKEND_CANCEL_REJECTED",
            _Symbol,
            "",
            cancel_result.message
         );
        }
      else if(StringFind(cancel_result.message, "0 ordem") != 0)
        {
         g_logger.Info(
            "WEEKEND_ORDERS_CANCELLED",
            _Symbol,
            "",
            cancel_result.message
         );
        }

      OperationResult close_result = {};
      if(!g_execution_manager.CloseAllOwnPositions(
            "WEEKEND_EXIT",
            close_result
         ))
        {
         g_logger.Warning(
            "WEEKEND_CLOSE_REJECTED",
            _Symbol,
            "",
            close_result.message
         );
        }
      else if(StringFind(close_result.message, "0 posicao") != 0)
        {
         g_logger.Info(
            "WEEKEND_POSITION_CLOSE_SENT",
            _Symbol,
            "",
            close_result.message
         );
        }
     }

   // Em estado fatal, as acoes protetivas continuam permitidas, mas o EA
   // permanece bloqueado ate reinicializacao manual.
   if(g_ea_state != EA_STATE_ERROR)
      ReconcileState();
  }

// Enquanto existe ordem pendente, revalida o spread uma vez por segundo.
// Isso reduz o risco de a ordem permanecer ativa durante alargamento de spread.
void ProcessPendingSpreadProtection(void)
  {
   if(g_ea_state != EA_STATE_ORDER_PENDING)
      return;

   const datetime server_time = GetBrokerServerTime();
   if(server_time <= 0 || server_time == g_last_spread_check_second)
      return;

   g_last_spread_check_second = server_time;

   OperationResult spread_result = {};
   if(!g_execution_manager.CancelPendingOrdersWithUnsafeSpread(spread_result))
     {
      g_logger.Warning(
         "SPREAD_PROTECTION_ERROR",
         _Symbol,
         "",
         spread_result.message
      );
      return;
     }

   if(StringFind(spread_result.message, "Nenhuma") != 0)
     {
      g_logger.Info(
         "ORDER_CANCELLED_BY_SPREAD",
         _Symbol,
         "",
         spread_result.message
      );
     }

   if(g_ea_state != EA_STATE_ERROR)
      ReconcileState();
  }

int OnInit(void)
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_logger.Configure(InpLogDetails);

   g_trading_schedule.Configure(
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
      InpCancelBeforeRollover,
      InpRolloverHour,
      InpRolloverMinute,
      InpRolloverCancelLeadMinutes,
      InpAvoidWeekend,
      InpFridayExitHour,
      InpFridayExitMinute,
      InpMondayResumeHour,
      InpMondayResumeMinute
   );

   string market_error = "";
   const bool is_tester = (bool)MQLInfoInteger(MQL_TESTER);

   // Oculta os handles internos para evitar tres EMAs com a cor padrao.
   if(is_tester)
      TesterHideIndicators(true);

   const bool market_initialized = g_market_data.Initialize(
      _Symbol,
      (ENUM_TIMEFRAMES)_Period,
      InpEMA21Period,
      InpEMA40Period,
      InpEMA80Period,
      market_error
   );

   if(is_tester)
      TesterHideIndicators(false);

   if(!market_initialized)
     {
      g_logger.Error("MARKET_DATA_ERROR", _Symbol, "", market_error);
      return INIT_FAILED;
     }

   string visual_error = "";
   if(!InitializeVisualIndicator(visual_error))
     {
      g_logger.Warning(
         "VISUAL_INDICATOR_ERROR",
         _Symbol,
         "",
         visual_error
      );
     }

   g_strategy.Configure(
      InpUse123,
      InpUsePFR,
      InpUseEngulfing,
      InpPatternPriority1,
      InpPatternPriority2,
      InpPatternPriority3,
      InpTradeDirection,
      InpTargetR,
      InpRiskPercent
   );

   g_execution_manager.Configure(
      _Symbol,
      InpMagicNumber,
      InpDeviationPoints,
      InpLogDetails,
      InpMaxSpreadPoints,
      InpMinStopSpreadMultiple
   );

   g_last_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(g_last_bar_time <= 0)
     {
      ReleaseVisualIndicator();
      g_market_data.Release();
      return INIT_FAILED;
     }

   OperationResult expiration_result = {};
   if(!g_execution_manager.CancelExpiredPendingOrders(
         g_last_bar_time,
         expiration_result
      ))
     {
      g_logger.Warning(
         "ORDER_CANCEL_REJECTED",
         _Symbol,
         "",
         expiration_result.message
      );
     }

   if(!ReconcileState())
     {
      ReleaseVisualIndicator();
      g_market_data.Release();
      return INIT_FAILED;
     }

   ProcessSafetyControls(true);

   ResetLastError();
   if(!EventSetTimer(InpSafetyTimerSeconds))
     {
      g_logger.Error(
         "TIMER_ERROR",
         _Symbol,
         "",
         StringFormat("EventSetTimer(%d) falhou. erro=%d", InpSafetyTimerSeconds, GetLastError())
      );
      ReleaseVisualIndicator();
      g_market_data.Release();
      return INIT_FAILED;
     }

   g_logger.Info(
      "EA_INITIALIZED",
      _Symbol,
      "",
      StringFormat(
         "estado=%d magic=%I64u timeframe=%s alvo=%.2fR max_spread=%.2f stop_spread=%.2fx",
         (int)g_ea_state,
         InpMagicNumber,
         EnumToString((ENUM_TIMEFRAMES)_Period),
         InpTargetR,
         InpMaxSpreadPoints,
         InpMinStopSpreadMultiple
      )
   );

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ReleaseVisualIndicator();
   g_market_data.Release();

   g_logger.Info(
      "EA_DEINITIALIZED",
      _Symbol,
      "",
      StringFormat("motivo=%d", reason)
   );
  }

void ProcessIdleState(void)
  {
   string schedule_reason = "";
   if(g_trading_schedule.IsEntryBlocked(GetBrokerServerTime(), schedule_reason))
     {
      g_logger.Info(
         "ENTRY_BLOCKED_BY_TIME",
         _Symbol,
         "",
         schedule_reason
      );
      return;
     }

   if(g_execution_manager.HasAnyTradingActivityForSymbol())
     {
      g_logger.Info(
         "SYMBOL_BUSY",
         _Symbol,
         "",
         "Existe ordem ou posicao no simbolo; nova entrada bloqueada."
      );
      return;
     }

   MarketSnapshot snapshot = {};
   string market_error = "";

   if(!g_market_data.LoadSnapshot(snapshot, market_error))
     {
      g_logger.Warning("MARKET_DATA_ERROR", _Symbol, "", market_error);
      return;
     }

   TradePlan plan = {};
   string strategy_error = "";

   if(!g_strategy.Evaluate(snapshot, plan, strategy_error))
     {
      if(strategy_error != "")
         g_logger.Warning("SIGNAL_REJECTED", _Symbol, "", strategy_error);
      return;
     }

   if(plan.signal_id == g_last_processed_signal_id)
      return;

   g_last_processed_signal_id = plan.signal_id;

   g_logger.Info(
      "SIGNAL_CREATED",
      _Symbol,
      plan.signal_id,
      StringFormat(
         "direcao=%s padrao=%s alvo=%.2fR entrada_tecnica=%.*f stop_tecnico=%.*f alvo_tecnico=%.*f",
         DirectionToString(plan.direction),
         plan.pattern_name,
         plan.target_r,
         _Digits,
         plan.technical_entry_price,
         _Digits,
         plan.technical_stop_price,
         _Digits,
         plan.technical_target_price
      )
   );

   PreparedOrder prepared = {};
   OperationResult preparation_result = {};

   if(!g_execution_manager.Prepare(plan, prepared, preparation_result))
     {
      g_logger.Warning(
         "ORDER_PREPARATION_REJECTED",
         _Symbol,
         plan.signal_id,
         preparation_result.message
      );
      return;
     }

   RiskResult risk_result = {};
   if(!g_risk_manager.Calculate(
         _Symbol,
         prepared,
         plan.risk_percent,
         risk_result
      ))
     {
      g_logger.Warning(
         "RISK_REJECTED",
         _Symbol,
         plan.signal_id,
         risk_result.message
      );
      return;
     }

   ExecutionResult execution_result = {};
   if(!g_execution_manager.Submit(
         prepared,
         risk_result.volume,
         execution_result
      ))
     {
      g_logger.Error(
         "ORDER_REJECTED",
         _Symbol,
         plan.signal_id,
         execution_result.message
      );

      ReconcileState();
      return;
     }

   g_ea_state = EA_STATE_ORDER_PENDING;
   g_pending_order_ticket = execution_result.order_ticket;

   g_logger.Info(
      "ORDER_PLACED",
      _Symbol,
      plan.signal_id,
      StringFormat(
         "direcao=%s padrao=%s ticket=%I64u volume=%.8f alvo=%.2fR spread=%.2fpts stop_spread=%.2fx risco_financeiro=%.2f perda_estimada=%.2f entrada_tecnica=%.*f entrada_enviada=%.*f SL=%.*f TP=%.*f",
         DirectionToString(plan.direction),
         plan.pattern_name,
         execution_result.order_ticket,
         risk_result.volume,
         prepared.target_r,
         prepared.spread_points,
         prepared.stop_spread_ratio,
         risk_result.risk_money,
         risk_result.estimated_loss,
         _Digits,
         execution_result.technical_entry_price,
         _Digits,
         execution_result.submitted_entry_price,
         _Digits,
         execution_result.submitted_stop_price,
         _Digits,
         execution_result.submitted_target_price
      )
   );
  }

void ProcessNewBar(const datetime current_bar_time)
  {
   if(g_ea_state == EA_STATE_ERROR)
      return;

   OperationResult cancellation_result = {};
   if(!g_execution_manager.CancelExpiredPendingOrders(
         current_bar_time,
         cancellation_result
      ))
     {
      g_logger.Error(
         "ORDER_CANCEL_REJECTED",
         _Symbol,
         "",
         cancellation_result.message
      );

      ReconcileState();
      return;
     }

   if(cancellation_result.message != "Nenhuma ordem vencida.")
     {
      g_logger.Info(
         "ORDER_CANCELLED",
         _Symbol,
         "",
         cancellation_result.message
      );
     }

   if(!ReconcileState())
      return;

   switch(g_ea_state)
     {
      case EA_STATE_IDLE:
         ProcessIdleState();
         break;

      case EA_STATE_ORDER_PENDING:
      case EA_STATE_POSITION_OPEN:
      case EA_STATE_ERROR:
         break;

      default:
         EnterErrorState("Estado do EA desconhecido.");
         break;
     }
  }

void OnTick(void)
  {
   ProcessPendingSpreadProtection();
   ProcessSafetyControls(false);

   const datetime current_bar_time = iTime(
      _Symbol,
      PERIOD_CURRENT,
      0
   );

   if(current_bar_time <= 0 || current_bar_time == g_last_bar_time)
      return;

   g_last_bar_time = current_bar_time;
   ProcessNewBar(current_bar_time);
  }

void OnTimer(void)
  {
   ProcessPendingSpreadProtection();
   ProcessSafetyControls(false);

   if(g_ea_state != EA_STATE_ERROR)
      ReconcileState();
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_execution_manager.ProcessTransaction(transaction, request, result);

   // A transacao pode alterar ordem, negocio ou posicao. Em operacao normal,
   // o estado e reconstruido a partir do ambiente real. Estado fatal nao e
   // liberado automaticamente; requer reinicializacao consciente do EA.
   if(g_ea_state != EA_STATE_ERROR)
      ReconcileState();
  }
//+------------------------------------------------------------------+
