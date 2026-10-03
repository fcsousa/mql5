#property strict
#property version   "1.00"
#property description "EA 123 de compra com filtro de médias, Buy Stop, risco percentual e validade parametrizável."

#include <FCSousa/EA123_MA_Buy/Types.mqh>
#include <FCSousa/EA123_MA_Buy/Strategy.mqh>
#include <FCSousa/EA123_MA_Buy/RiskManager.mqh>
#include <FCSousa/EA123_MA_Buy/ExecutionManager.mqh>

input group "Moving Averages"
input int                      InpShortMAPeriod = 9;
input ENUM_MA_METHOD           InpShortMAMethod = MODE_EMA;
input int                      InpLongMAPeriod  = 21;
input ENUM_MA_METHOD           InpLongMAMethod  = MODE_EMA;

input group "Trade"
input double                   InpTargetR        = 1.0;
input double                   InpRiskPercent    = 1.0;
input ENUM_ORDER_VALIDITY_MODE InpValidityMode   = VALIDITY_ONE_CANDLE;
input ulong                    InpMagicNumber    = 1230921;

CBuy123Strategy   g_strategy;
CRiskManager      g_risk_manager;
CExecutionManager g_execution_manager;

ENUM_EA_STATE g_ea_state = EA_STATE_IDLE;

datetime g_last_evaluated_bar_time = 0;

bool ValidateInputs(void)
{
   if(InpShortMAPeriod <= 0)
   {
      Print("INPUT_INVALID | InpShortMAPeriod deve ser > 0.");
      return false;
   }

   if(InpLongMAPeriod <= 0)
   {
      Print("INPUT_INVALID | InpLongMAPeriod deve ser > 0.");
      return false;
   }

   if(InpTargetR <= 0.0)
   {
      Print("INPUT_INVALID | InpTargetR deve ser > 0.");
      return false;
   }

   if(InpRiskPercent <= 0.0 ||
      InpRiskPercent > 100.0)
   {
      Print("INPUT_INVALID | InpRiskPercent deve estar em (0, 100].");
      return false;
   }

   if(InpMagicNumber == 0)
   {
      Print("INPUT_INVALID | InpMagicNumber deve ser diferente de zero.");
      return false;
   }

   return true;
}

void SyncStateFromTerminal(void)
{
   if(g_ea_state == EA_STATE_ERROR)
      return;

   if(g_execution_manager.HasOpenPosition())
   {
      g_ea_state = EA_STATE_POSITION_OPEN;
      return;
   }

   if(g_execution_manager.GetPendingOrderTicket() != 0)
   {
      g_ea_state = EA_STATE_ORDER_PENDING;
      return;
   }

   g_ea_state = EA_STATE_IDLE;
}

void EnterErrorState(const string reason)
{
   g_ea_state = EA_STATE_ERROR;

   PrintFormat(
      "EA_BLOCKED | symbol=%s | reason=%s",
      _Symbol,
      reason
   );
}

bool ShouldCancelOneCandleOrder(
   const ulong order_ticket,
   string &reason
)
{
   reason = "";

   if(!OrderSelect(order_ticket))
   {
      reason = "Não foi possível selecionar a ordem pendente.";
      return false;
   }

   const datetime order_setup_time =
      (datetime)OrderGetInteger(ORDER_TIME_SETUP);

   if(order_setup_time <= 0)
   {
      reason = "ORDER_TIME_SETUP inválido.";
      return false;
   }

   const int setup_bar_shift =
      iBarShift(
         _Symbol,
         (ENUM_TIMEFRAMES)_Period,
         order_setup_time,
         false
      );

   if(setup_bar_shift < 0)
   {
      reason = "Não foi possível localizar candle de criação da ordem.";
      return false;
   }

   const datetime setup_bar_open =
      iTime(
         _Symbol,
         (ENUM_TIMEFRAMES)_Period,
         setup_bar_shift
      );

   const datetime current_bar_open =
      iTime(
         _Symbol,
         (ENUM_TIMEFRAMES)_Period,
         0
      );

   if(setup_bar_open <= 0 ||
      current_bar_open <= 0)
   {
      reason = "Horário de candle inválido.";
      return false;
   }

   return current_bar_open > setup_bar_open;
}

bool ShouldCancelStopBrokenOrder(
   const ulong order_ticket,
   string &reason
)
{
   reason = "";

   if(!OrderSelect(order_ticket))
   {
      reason = "Não foi possível selecionar a ordem pendente.";
      return false;
   }

   const double stop_price =
      OrderGetDouble(ORDER_SL);

   if(stop_price <= 0.0)
   {
      reason = "Stop da ordem pendente inválido.";
      return false;
   }

   MqlTick tick = {};

   ResetLastError();

   if(!SymbolInfoTick(_Symbol, tick))
   {
      reason = StringFormat(
         "SymbolInfoTick falhou. erro=%d",
         GetLastError()
      );
      return false;
   }

   const double reference_price =
      tick.last > 0.0
      ? tick.last
      : tick.bid;

   if(reference_price <= 0.0)
   {
      reason = "Preço de referência inválido.";
      return false;
   }

   return reference_price <= stop_price;
}

void ManagePendingOrder(void)
{
   const ulong order_ticket =
      g_execution_manager.GetPendingOrderTicket();

   if(order_ticket == 0)
   {
      g_ea_state = EA_STATE_IDLE;
      return;
   }

   bool should_cancel = false;
   string cancel_reason = "";
   string validation_error = "";

   if(InpValidityMode == VALIDITY_ONE_CANDLE)
   {
      should_cancel =
         ShouldCancelOneCandleOrder(
            order_ticket,
            validation_error
         );

      if(validation_error != "")
      {
         PrintFormat(
            "PENDING_VALIDITY_WARNING | symbol=%s | ticket=%I64u | %s",
            _Symbol,
            order_ticket,
            validation_error
         );
         return;
      }

      if(should_cancel)
         cancel_reason = "ONE_CANDLE expirado";
   }
   else
   {
      should_cancel =
         ShouldCancelStopBrokenOrder(
            order_ticket,
            validation_error
         );

      if(validation_error != "")
      {
         PrintFormat(
            "PENDING_VALIDITY_WARNING | symbol=%s | ticket=%I64u | %s",
            _Symbol,
            order_ticket,
            validation_error
         );
         return;
      }

      if(should_cancel)
         cancel_reason = "preço atingiu/perdeu o stop antes da entrada";
   }

   if(!should_cancel)
      return;

   ExecutionResult cancel_result = {};

   if(!g_execution_manager.CancelPendingOrder(
      order_ticket,
      cancel_result
   ))
   {
      PrintFormat(
         "ORDER_CANCEL_REJECTED | symbol=%s | ticket=%I64u | retcode=%u | %s",
         _Symbol,
         order_ticket,
         cancel_result.retcode,
         cancel_result.message
      );
      return;
   }

   PrintFormat(
      "ORDER_CANCEL_REQUESTED | symbol=%s | ticket=%I64u | reason=%s",
      _Symbol,
      order_ticket,
      cancel_reason
   );
}

int OnInit(void)
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   string strategy_error = "";

   if(!g_strategy.Initialize(
      _Symbol,
      (ENUM_TIMEFRAMES)_Period,
      InpShortMAPeriod,
      InpShortMAMethod,
      InpLongMAPeriod,
      InpLongMAMethod,
      InpTargetR,
      InpRiskPercent,
      InpValidityMode,
      strategy_error
   ))
   {
      PrintFormat(
         "EA_INIT_FAILED | symbol=%s | %s",
         _Symbol,
         strategy_error
      );
      return INIT_FAILED;
   }

   g_execution_manager.Configure(
      _Symbol,
      InpMagicNumber
   );

   SyncStateFromTerminal();

   g_last_evaluated_bar_time =
      iTime(
         _Symbol,
         (ENUM_TIMEFRAMES)_Period,
         0
      );

   PrintFormat(
      "EA_INITIALIZED | symbol=%s | timeframe=%s | short=%d/%s | long=%d/%s | targetR=%.2f | risk=%.2f%% | validity=%s | state=%d",
      _Symbol,
      EnumToString((ENUM_TIMEFRAMES)_Period),
      InpShortMAPeriod,
      EnumToString(InpShortMAMethod),
      InpLongMAPeriod,
      EnumToString(InpLongMAMethod),
      InpTargetR,
      InpRiskPercent,
      EnumToString(InpValidityMode),
      (int)g_ea_state
   );

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   g_strategy.Release();

   PrintFormat(
      "EA_DEINITIALIZED | symbol=%s | reason=%d",
      _Symbol,
      reason
   );
}

void OnTick(void)
{
   if(g_ea_state == EA_STATE_ERROR)
      return;

   SyncStateFromTerminal();

   if(g_ea_state == EA_STATE_ORDER_PENDING)
   {
      ManagePendingOrder();
      return;
   }

   if(g_ea_state == EA_STATE_POSITION_OPEN)
      return;

   const datetime current_bar_time =
      iTime(
         _Symbol,
         (ENUM_TIMEFRAMES)_Period,
         0
      );

   if(current_bar_time <= 0)
      return;

   if(current_bar_time == g_last_evaluated_bar_time)
      return;

   // Marca a barra antes da avaliação para impedir reenvio no mesmo candle
   // mesmo em caso de rejeição temporária.
   g_last_evaluated_bar_time =
      current_bar_time;

   TradePlan plan = {};
   string strategy_error = "";

   if(!g_strategy.Evaluate(plan, strategy_error))
   {
      if(strategy_error != "")
      {
         PrintFormat(
            "MARKET_DATA_ERROR | symbol=%s | %s",
            _Symbol,
            strategy_error
         );
      }

      return;
   }

   PrintFormat(
      "SIGNAL_CREATED | symbol=%s | id=%s | entry=%.*f | stop=%.*f | target=%.*f",
      _Symbol,
      plan.signal_id,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
      plan.entry_price,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
      plan.stop_price,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
      plan.target_price
   );

   double volume = 0.0;
   double risk_amount = 0.0;
   string risk_error = "";

   if(!g_risk_manager.CalculateVolume(
      _Symbol,
      plan.entry_price,
      plan.stop_price,
      plan.risk_percent,
      volume,
      risk_amount,
      risk_error
   ))
   {
      PrintFormat(
         "RISK_REJECTED | symbol=%s | id=%s | %s",
         _Symbol,
         plan.signal_id,
         risk_error
      );
      return;
   }

   ExecutionResult execution_result = {};

   if(!g_execution_manager.Submit(
      plan,
      volume,
      execution_result
   ))
   {
      PrintFormat(
         "ORDER_REJECTED | symbol=%s | id=%s | retcode=%u | %s",
         _Symbol,
         plan.signal_id,
         execution_result.retcode,
         execution_result.message
      );
      return;
   }

   g_ea_state =
      EA_STATE_ORDER_PENDING;

   PrintFormat(
      "ORDER_SENT | symbol=%s | id=%s | ticket=%I64u | volume=%.8f | risk_amount=%.2f | requested=%.*f | normalized=%.*f",
      _Symbol,
      plan.signal_id,
      execution_result.order_ticket,
      volume,
      risk_amount,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
      execution_result.requested_price,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
      execution_result.normalized_price
   );
}

void OnTradeTransaction(
   const MqlTradeTransaction &transaction,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   g_execution_manager.ProcessTransaction(
      transaction,
      request,
      result
   );

   SyncStateFromTerminal();
}
