#ifndef FCSOUSA_EA123_MA_BUY_EXECUTION_MANAGER_MQH
#define FCSOUSA_EA123_MA_BUY_EXECUTION_MANAGER_MQH

#include <FCSousa/EA123_MA_Buy/Types.mqh>

class CExecutionManager
{
private:
   string m_symbol;
   ulong  m_magic_number;
   ulong  m_pending_order_ticket;

   bool IsMatchingCurrentOrder(void) const
   {
      const string order_symbol =
         OrderGetString(ORDER_SYMBOL);

      const ulong order_magic =
         (ulong)OrderGetInteger(ORDER_MAGIC);

      return order_symbol == m_symbol &&
             order_magic == m_magic_number;
   }

public:
   CExecutionManager(void)
   {
      m_symbol               = "";
      m_magic_number         = 0;
      m_pending_order_ticket = 0;
   }

   void Configure(
      const string symbol,
      const ulong magic_number
   )
   {
      m_symbol       = symbol;
      m_magic_number = magic_number;
   }

   bool HasOpenPosition(void) const
   {
      const int total_positions =
         PositionsTotal();

      for(int index = total_positions - 1; index >= 0; --index)
      {
         const string position_symbol =
            PositionGetSymbol(index);

         if(position_symbol == "")
            continue;

         const ulong position_magic =
            (ulong)PositionGetInteger(POSITION_MAGIC);

         if(position_symbol == m_symbol &&
            position_magic == m_magic_number)
         {
            return true;
         }
      }

      return false;
   }

   ulong GetPendingOrderTicket(void)
   {
      const int total_orders =
         OrdersTotal();

      for(int index = total_orders - 1; index >= 0; --index)
      {
         const ulong ticket =
            OrderGetTicket(index);

         if(ticket == 0)
            continue;

         if(!IsMatchingCurrentOrder())
            continue;

         const ENUM_ORDER_TYPE order_type =
            (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         if(order_type == ORDER_TYPE_BUY_STOP)
         {
            m_pending_order_ticket = ticket;
            return ticket;
         }
      }

      m_pending_order_ticket = 0;
      return 0;
   }

   bool HasExposure(void)
   {
      if(HasOpenPosition())
         return true;

      return GetPendingOrderTicket() != 0;
   }

   bool Submit(
      const TradePlan &plan,
      const double volume,
      ExecutionResult &execution_result
   )
   {
      ZeroMemory(execution_result);

      execution_result.success         = false;
      execution_result.requested_price = plan.entry_price;

      if(HasExposure())
      {
         execution_result.message =
            "Já existe ordem pendente ou posição para símbolo/Magic.";
         return false;
      }

      MqlTick tick = {};

      ResetLastError();

      if(!SymbolInfoTick(m_symbol, tick))
      {
         execution_result.message = StringFormat(
            "SymbolInfoTick falhou. erro=%d",
            GetLastError()
         );
         return false;
      }

      const double entry_price =
         NormalizePriceUp(m_symbol, plan.entry_price);

      const double stop_price =
         NormalizePriceDown(m_symbol, plan.stop_price);

      const double target_price =
         NormalizePriceDown(m_symbol, plan.target_price);

      execution_result.normalized_price =
         entry_price;

      if(entry_price <= 0.0 ||
         stop_price <= 0.0 ||
         target_price <= 0.0)
      {
         execution_result.message =
            "Preço normalizado inválido.";
         return false;
      }

      if(tick.ask >= entry_price)
      {
         execution_result.message = StringFormat(
            "Entrada Buy Stop já foi alcançada/perdida. ask=%.*f entry=%.*f",
            (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS),
            tick.ask,
            (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS),
            entry_price
         );
         return false;
      }

      const double point =
         SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      const long stops_level_points =
         SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

      if(point > 0.0 && stops_level_points > 0)
      {
         const double minimum_distance =
            (double)stops_level_points * point;

         if((entry_price - tick.ask) < minimum_distance)
         {
            execution_result.message =
               "Buy Stop viola SYMBOL_TRADE_STOPS_LEVEL em relação ao Ask.";
            return false;
         }

         if((entry_price - stop_price) < minimum_distance)
         {
            execution_result.message =
               "Stop Loss viola SYMBOL_TRADE_STOPS_LEVEL.";
            return false;
         }

         if((target_price - entry_price) < minimum_distance)
         {
            execution_result.message =
               "Take Profit viola SYMBOL_TRADE_STOPS_LEVEL.";
            return false;
         }
      }

      MqlTradeRequest request = {};
      MqlTradeCheckResult check_result = {};
      MqlTradeResult trade_result = {};

      request.action       = TRADE_ACTION_PENDING;
      request.magic        = m_magic_number;
      request.symbol       = m_symbol;
      request.volume       = volume;
      request.price        = entry_price;
      request.sl           = stop_price;
      request.tp           = target_price;
      request.type         = ORDER_TYPE_BUY_STOP;
      request.type_filling = ORDER_FILLING_RETURN;
      request.type_time    = ORDER_TIME_GTC;
      request.comment      = plan.signal_id;

      ResetLastError();

      if(!OrderCheck(request, check_result))
      {
         execution_result.retcode = check_result.retcode;
         execution_result.message = StringFormat(
            "OrderCheck falhou. retcode=%u comment=%s erro=%d",
            check_result.retcode,
            check_result.comment,
            GetLastError()
         );
         return false;
      }

      if(check_result.retcode != 0 &&
         check_result.retcode != TRADE_RETCODE_DONE)
      {
         execution_result.retcode = check_result.retcode;
         execution_result.message = StringFormat(
            "OrderCheck rejeitou. retcode=%u comment=%s",
            check_result.retcode,
            check_result.comment
         );
         return false;
      }

      ResetLastError();

      if(!OrderSend(request, trade_result))
      {
         execution_result.retcode = trade_result.retcode;
         execution_result.message = StringFormat(
            "OrderSend falhou localmente. retcode=%u comment=%s erro=%d",
            trade_result.retcode,
            trade_result.comment,
            GetLastError()
         );
         return false;
      }

      execution_result.retcode        = trade_result.retcode;
      execution_result.order_ticket   = trade_result.order;
      execution_result.deal_ticket    = trade_result.deal;
      execution_result.executed_price = trade_result.price;

      if(!IsAcceptedTradeRetcode(trade_result.retcode))
      {
         execution_result.message = StringFormat(
            "Servidor rejeitou ordem. retcode=%u comment=%s",
            trade_result.retcode,
            trade_result.comment
         );
         return false;
      }

      m_pending_order_ticket =
         trade_result.order;

      execution_result.success = true;
      execution_result.message = trade_result.comment;

      return true;
   }

   bool CancelPendingOrder(
      const ulong order_ticket,
      ExecutionResult &execution_result
   )
   {
      ZeroMemory(execution_result);
      execution_result.success = false;

      if(order_ticket == 0)
      {
         execution_result.message =
            "Ticket de ordem pendente inválido.";
         return false;
      }

      MqlTradeRequest request = {};
      MqlTradeResult trade_result = {};

      request.action = TRADE_ACTION_REMOVE;
      request.order  = order_ticket;
      request.symbol = m_symbol;
      request.magic  = m_magic_number;

      ResetLastError();

      if(!OrderSend(request, trade_result))
      {
         execution_result.retcode = trade_result.retcode;
         execution_result.message = StringFormat(
            "Falha local ao cancelar ordem. retcode=%u comment=%s erro=%d",
            trade_result.retcode,
            trade_result.comment,
            GetLastError()
         );
         return false;
      }

      execution_result.retcode      = trade_result.retcode;
      execution_result.order_ticket = order_ticket;

      if(!IsAcceptedTradeRetcode(trade_result.retcode))
      {
         execution_result.message = StringFormat(
            "Servidor rejeitou cancelamento. retcode=%u comment=%s",
            trade_result.retcode,
            trade_result.comment
         );
         return false;
      }

      execution_result.success = true;
      execution_result.message = trade_result.comment;

      return true;
   }

   void ProcessTransaction(
      const MqlTradeTransaction &transaction,
      const MqlTradeRequest &request,
      const MqlTradeResult &result
   )
   {
      if(transaction.type == TRADE_TRANSACTION_ORDER_ADD &&
         transaction.order > 0)
      {
         if(OrderSelect(transaction.order) &&
            IsMatchingCurrentOrder())
         {
            m_pending_order_ticket =
               transaction.order;

            PrintFormat(
               "ORDER_PLACED | symbol=%s | ticket=%I64u | price=%.*f",
               m_symbol,
               transaction.order,
               (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS),
               OrderGetDouble(ORDER_PRICE_OPEN)
            );
         }
      }

      if(transaction.type == TRADE_TRANSACTION_DEAL_ADD &&
         transaction.deal > 0)
      {
         if(HistoryDealSelect(transaction.deal))
         {
            const string deal_symbol =
               HistoryDealGetString(
                  transaction.deal,
                  DEAL_SYMBOL
               );

            const ulong deal_magic =
               (ulong)HistoryDealGetInteger(
                  transaction.deal,
                  DEAL_MAGIC
               );

            if(deal_symbol == m_symbol &&
               deal_magic == m_magic_number)
            {
               PrintFormat(
                  "DEAL_EXECUTED | symbol=%s | deal=%I64u | price=%.*f",
                  m_symbol,
                  transaction.deal,
                  (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS),
                  HistoryDealGetDouble(
                     transaction.deal,
                     DEAL_PRICE
                  )
               );
            }
         }
      }

      if(transaction.type == TRADE_TRANSACTION_ORDER_DELETE &&
         transaction.order == m_pending_order_ticket)
      {
         m_pending_order_ticket = 0;
      }
   }
};

#endif
