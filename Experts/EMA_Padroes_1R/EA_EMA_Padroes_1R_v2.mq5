//+------------------------------------------------------------------+
//|                                  EA_EMA_Padroes_1R_v2.mq5       |
//| EMA21/40/80 + 123, PFR ou Engolfo completo + alvo 1R            |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "EA modular EMA21/40/80 com padroes 123, PFR e Engolfo completo."
#property description "Ordem Stop, risco percentual sobre saldo, alvo 1R e confirmacao por transacao."

#include <EMA_Padroes_1R/Types.mqh>
#include <EMA_Padroes_1R/Logger.mqh>
#include <EMA_Padroes_1R/MarketData.mqh>
#include <EMA_Padroes_1R/Strategy.mqh>
#include <EMA_Padroes_1R/RiskManager.mqh>
#include <EMA_Padroes_1R/ExecutionManager.mqh>

input group "Indicadores"
input int      InpEMA21Period       = 21;
input int      InpEMA40Period       = 40;
input int      InpEMA80Period       = 80;

input group "Formacoes"
input bool     InpUse123            = true;
input bool     InpUsePFR            = true;
input bool     InpUseEngulfing      = true;

input group "Risco"
input double   InpRiskPercent       = 1.00;

input group "Execucao"
input ulong    InpMagicNumber       = 214080;
input ulong    InpDeviationPoints   = 20;
input bool     InpLogDetails        = true;

CLogger           g_logger;
CMarketData       g_market_data;
CStrategy         g_strategy;
CRiskManager      g_risk_manager;
CExecutionManager g_execution_manager;

ENUM_EA_STATE g_ea_state = EA_STATE_IDLE;
datetime      g_last_bar_time = 0;
ulong         g_pending_order_ticket = 0;
ulong         g_position_ticket = 0;
string        g_last_processed_signal_id = "";

bool ValidateInputs(void)
  {
   if(InpEMA21Period <= 0 ||
      InpEMA40Period <= InpEMA21Period ||
      InpEMA80Period <= InpEMA40Period)
     {
      Print(
         "Periodos invalidos: use EMA21 > 0, EMA40 > EMA21 e EMA80 > EMA40."
      );
      return false;
     }

   if(InpRiskPercent <= 0.0 || InpRiskPercent > 10.0)
     {
      Print("InpRiskPercent deve estar entre 0 e 10 por cento.");
      return false;
     }

   if(!InpUse123 && !InpUsePFR && !InpUseEngulfing)
     {
      Print("Habilite pelo menos uma formacao operacional.");
      return false;
     }

   if(InpMagicNumber == 0)
     {
      Print("InpMagicNumber deve ser maior que zero.");
      return false;
     }

   return true;
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

int OnInit(void)
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_logger.Configure(InpLogDetails);

   string market_error = "";
   if(!g_market_data.Initialize(
         _Symbol,
         (ENUM_TIMEFRAMES)_Period,
         InpEMA21Period,
         InpEMA40Period,
         InpEMA80Period,
         market_error
      ))
     {
      g_logger.Error(
         "MARKET_DATA_ERROR",
         _Symbol,
         "",
         market_error
      );

      return INIT_FAILED;
     }

   g_strategy.Configure(
      InpUse123,
      InpUsePFR,
      InpUseEngulfing,
      InpRiskPercent
   );

   g_execution_manager.Configure(
      _Symbol,
      InpMagicNumber,
      InpDeviationPoints,
      InpLogDetails
   );

   g_last_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(g_last_bar_time <= 0)
     {
      g_market_data.Release();
      return INIT_FAILED;
     }

   OperationResult cancellation_result = {};
   if(!g_execution_manager.CancelExpiredPendingOrders(
         g_last_bar_time,
         cancellation_result
      ))
     {
      g_logger.Warning(
         "ORDER_CANCEL_REJECTED",
         _Symbol,
         "",
         cancellation_result.message
      );
     }

   if(!ReconcileState())
     {
      g_market_data.Release();
      return INIT_FAILED;
     }

   ResetLastError();
   if(!EventSetTimer(1))
     {
      g_logger.Error(
         "TIMER_ERROR",
         _Symbol,
         "",
         StringFormat("EventSetTimer falhou. erro=%d", GetLastError())
      );
      g_market_data.Release();
      return INIT_FAILED;
     }

   g_logger.Info(
      "EA_INITIALIZED",
      _Symbol,
      "",
      StringFormat(
         "estado=%d magic=%I64u timeframe=%s",
         (int)g_ea_state,
         InpMagicNumber,
         EnumToString((ENUM_TIMEFRAMES)_Period)
      )
   );

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
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
      g_logger.Warning(
         "MARKET_DATA_ERROR",
         _Symbol,
         "",
         market_error
      );
      return;
     }

   TradePlan plan = {};
   string strategy_error = "";

   if(!g_strategy.Evaluate(snapshot, plan, strategy_error))
     {
      if(strategy_error != "")
        {
         g_logger.Warning(
            "SIGNAL_REJECTED",
            _Symbol,
            "",
            strategy_error
         );
        }
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
         "padrao=%s entrada_tecnica=%.*f stop_tecnico=%.*f alvo_tecnico=%.*f",
         plan.pattern_name,
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

   if(!g_execution_manager.Prepare(
         plan,
         prepared,
         preparation_result
      ))
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
         "ticket=%I64u volume=%.8f risco_financeiro=%.2f perda_estimada=%.2f entrada_tecnica=%.*f entrada_enviada=%.*f SL=%.*f TP=%.*f",
         execution_result.order_ticket,
         risk_result.volume,
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
   if(g_ea_state == EA_STATE_ERROR)
      return;

   ReconcileState();
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_execution_manager.ProcessTransaction(
      transaction,
      request,
      result
   );

   if(g_ea_state != EA_STATE_ERROR)
      ReconcileState();
  }
//+------------------------------------------------------------------+
