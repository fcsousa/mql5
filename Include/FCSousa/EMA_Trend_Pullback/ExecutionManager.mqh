#ifndef __EMA_TREND_PULLBACK_EXECUTION_MANAGER_MQH__
#define __EMA_TREND_PULLBACK_EXECUTION_MANAGER_MQH__

#include <FCSousa/EMA_Trend_Pullback/Types.mqh>

class CExecutionManager
{
private:
   string m_symbol;
   ulong m_magic;
   ulong m_deviation_points;
   double m_max_spread_points;
   double m_min_stop_spread_multiple;
   double m_min_stop_points_absolute;
   double m_min_stop_atr_multiple;

   double TickSize(void) const
   {
      return SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   }

   double Point(void) const
   {
      return SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   }

   double NormalizeUp(const double price) const
   {
      const double tick_size = TickSize();
      if(tick_size <= 0.0) return 0.0;
      return MathCeil(price / tick_size - 1e-12) * tick_size;
   }

   double NormalizeDown(const double price) const
   {
      const double tick_size = TickSize();
      if(tick_size <= 0.0) return 0.0;
      return MathFloor(price / tick_size + 1e-12) * tick_size;
   }

   bool CurrentTick(MqlTick &tick, string &error) const
   {
      error = "";
      if(!SymbolInfoTick(m_symbol, tick))
      {
         error = StringFormat("SymbolInfoTick falhou. erro=%d", GetLastError());
         return false;
      }

      if(tick.ask <= 0.0 || tick.bid <= 0.0 || tick.ask < tick.bid)
      {
         error = "Tick invalido.";
         return false;
      }

      return true;
   }

public:
   CExecutionManager(void)
   {
      m_symbol = "";
      m_magic = 0;
      m_deviation_points = 20;
      m_max_spread_points = 30.0;
      m_min_stop_spread_multiple = 3.0;
      m_min_stop_points_absolute = 10.0;
      m_min_stop_atr_multiple = 0.50;
   }

   void Configure(const string symbol,
                  const ulong magic,
                  const ulong deviation_points,
                  const double max_spread_points,
                  const double min_stop_spread_multiple,
                  const double min_stop_points_absolute,
                  const double min_stop_atr_multiple)
   {
      m_symbol = symbol;
      m_magic = magic;
      m_deviation_points = deviation_points;
      m_max_spread_points = max_spread_points;
      m_min_stop_spread_multiple = min_stop_spread_multiple;
      m_min_stop_points_absolute = min_stop_points_absolute;
      m_min_stop_atr_multiple = min_stop_atr_multiple;
   }

   bool GetCurrentSpread(double &spread_price,
                         double &spread_points,
                         string &error) const
   {
      spread_price = 0.0;
      spread_points = 0.0;

      MqlTick tick = {};
      if(!CurrentTick(tick, error))
         return false;

      const double point = Point();
      if(point <= 0.0)
      {
         error = "SYMBOL_POINT invalido.";
         return false;
      }

      spread_price = tick.ask - tick.bid;
      spread_points = spread_price / point;
      return true;
   }

   bool HasAnyTradingActivityForSymbol(void) const
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const string symbol = PositionGetSymbol(i);
         if(symbol == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
            return true;
      }

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
            return true;
      }

      return false;
   }

   bool ValidatePlan(const TradePlan &plan,
                     const double current_spread_points,
                     string &error) const
   {
      error = "";

      const double point = Point();
      if(point <= 0.0)
      {
         error = "Point invalido.";
         return false;
      }

      if(m_max_spread_points > 0.0 &&
         current_spread_points > m_max_spread_points + 1e-9)
      {
         error = StringFormat("Spread elevado %.2f > %.2f",
                              current_spread_points,
                              m_max_spread_points);
         return false;
      }

      const double stop_points =
         MathAbs(plan.technical_entry_price -
                 plan.technical_stop_price) / point;

      const double min_stop_points =
         MathMax(
            m_min_stop_points_absolute,
            plan.atr_value / point * m_min_stop_atr_multiple
         );

      if(stop_points + 1e-9 < min_stop_points)
      {
         error = StringFormat("Stop abaixo do minimo %.2f < %.2f",
                              stop_points, min_stop_points);
         return false;
      }

      if(m_min_stop_spread_multiple > 0.0 &&
         current_spread_points > 0.0 &&
         stop_points / current_spread_points + 1e-9 <
         m_min_stop_spread_multiple)
      {
         error = StringFormat("Stop/spread inseguro %.2fx < %.2fx",
                              stop_points / current_spread_points,
                              m_min_stop_spread_multiple);
         return false;
      }

      const int stops_level =
         (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

      if(stops_level > 0 && stop_points + 1e-9 < stops_level)
      {
         error = StringFormat("Stop abaixo do broker stop level %.2f < %d",
                              stop_points, stops_level);
         return false;
      }

      return true;
   }

   bool Submit(const TradePlan &plan,
               const RiskResult &risk,
               ExecutionResult &result)
   {
      result.success = false;
      result.retcode = 0;
      result.order_ticket = 0;
      result.message = "";

      double spread_price = 0.0;
      double spread_points = 0.0;
      string spread_error = "";

      if(!GetCurrentSpread(spread_price, spread_points, spread_error))
      {
         result.message = spread_error;
         return false;
      }

      string validation_error = "";
      if(!ValidatePlan(plan, spread_points, validation_error))
      {
         result.message = validation_error;
         return false;
      }

      double entry = 0.0;
      double stop = 0.0;
      double target = 0.0;

      if(plan.direction == SIGNAL_BUY)
      {
         entry = NormalizeUp(plan.technical_entry_price);
         stop = NormalizeDown(plan.technical_stop_price);
         target = NormalizeDown(risk.target_price);
      }
      else
      {
         entry = NormalizeDown(plan.technical_entry_price);
         stop = NormalizeUp(plan.technical_stop_price);
         target = NormalizeUp(risk.target_price);
      }

      if(entry <= 0.0 || stop <= 0.0 || target <= 0.0)
      {
         result.message = "Preco normalizado invalido.";
         return false;
      }

      MqlTradeRequest request = {};
      MqlTradeCheckResult check = {};
      MqlTradeResult send_result = {};

      request.action = TRADE_ACTION_PENDING;
      request.magic = m_magic;
      request.symbol = m_symbol;
      request.volume = risk.volume;
      request.price = entry;
      request.sl = stop;
      request.tp = target;
      request.deviation = m_deviation_points;
      request.type = plan.order_type;
      request.type_time = ORDER_TIME_SPECIFIED;
      request.expiration = plan.expiration;
      request.type_filling = ORDER_FILLING_RETURN;
      request.comment = StringSubstr(plan.signal_id, 0, 31);

      ResetLastError();

      if(!OrderCheck(request, check))
      {
         result.message =
            StringFormat("OrderCheck falhou localmente. erro=%d comment=%s",
                         GetLastError(), check.comment);
         return false;
      }

      if(check.retcode != TRADE_RETCODE_DONE)
      {
         result.retcode = check.retcode;
         result.message =
            StringFormat("OrderCheck rejeitado. retcode=%u comment=%s",
                         check.retcode, check.comment);
         return false;
      }

      ResetLastError();

      if(!OrderSend(request, send_result))
      {
         result.message =
            StringFormat("OrderSend falhou localmente. erro=%d",
                         GetLastError());
         return false;
      }

      if(send_result.retcode != TRADE_RETCODE_DONE &&
         send_result.retcode != TRADE_RETCODE_PLACED)
      {
         result.retcode = send_result.retcode;
         result.message =
            StringFormat("OrderSend rejeitado. retcode=%u comment=%s",
                         send_result.retcode,
                         send_result.comment);
         return false;
      }

      result.success = true;
      result.retcode = send_result.retcode;
      result.order_ticket = send_result.order;
      result.requested_price = request.price;
      result.normalized_entry_price = entry;
      result.normalized_stop_price = stop;
      result.normalized_target_price = target;
      result.message = send_result.comment;
      return true;
   }

   bool CancelAllPendingOrders(string &message)
   {
      int cancelled = 0;

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) != m_symbol ||
            (ulong)OrderGetInteger(ORDER_MAGIC) != m_magic)
            continue;

         MqlTradeRequest request = {};
         MqlTradeResult result = {};

         request.action = TRADE_ACTION_REMOVE;
         request.order = ticket;
         request.symbol = m_symbol;
         request.magic = m_magic;

         if(OrderSend(request, result) &&
            (result.retcode == TRADE_RETCODE_DONE ||
             result.retcode == TRADE_RETCODE_PLACED))
         {
            cancelled++;
         }
      }

      message = StringFormat("%d ordem(ns) pendente(s) cancelada(s).",
                             cancelled);
      return true;
   }

   ENUM_EA_STATE DetectState(ulong &pending_ticket,
                             ulong &position_ticket) const
   {
      pending_ticket = 0;
      position_ticket = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const string symbol = PositionGetSymbol(i);
         if(symbol == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
         {
            position_ticket =
               (ulong)PositionGetInteger(POSITION_TICKET);
            return EA_STATE_POSITION_OPEN;
         }
      }

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
         {
            pending_ticket = ticket;
            return EA_STATE_ORDER_PENDING;
         }
      }

      return EA_STATE_IDLE;
   }
};

#endif
