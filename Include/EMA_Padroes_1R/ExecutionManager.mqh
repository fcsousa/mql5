#ifndef EMA_PADROES_1R_EXECUTION_MANAGER_MQH
#define EMA_PADROES_1R_EXECUTION_MANAGER_MQH

#include <EMA_Padroes_1R/Types.mqh>

class CExecutionManager
  {
private:
   string          m_symbol;
   ulong           m_magic_number;
   ulong           m_deviation_points;
   bool            m_log_details;
   double          m_max_spread_points;
   double          m_min_stop_spread_ratio;
   double          m_min_stop_points_absolute;
   double          m_min_stop_atr_multiple;

   double NormalizePriceUp(const double price,
                           const double tick_size,
                           const int digits)
     {
      const double normalized =
         MathCeil(price / tick_size - 1e-9) * tick_size;

      return NormalizeDouble(normalized, digits);
     }

   double NormalizePriceDown(const double price,
                             const double tick_size,
                             const int digits)
     {
      const double normalized =
         MathFloor(price / tick_size + 1e-9) * tick_size;

      return NormalizeDouble(normalized, digits);
     }

   bool IsPendingOrderType(const ENUM_ORDER_TYPE order_type)
     {
      return(
         order_type == ORDER_TYPE_BUY_LIMIT ||
         order_type == ORDER_TYPE_SELL_LIMIT ||
         order_type == ORDER_TYPE_BUY_STOP ||
         order_type == ORDER_TYPE_SELL_STOP ||
         order_type == ORDER_TYPE_BUY_STOP_LIMIT ||
         order_type == ORDER_TYPE_SELL_STOP_LIMIT
      );
     }

   bool IsCheckRetcodeAccepted(const uint retcode)
     {
      return(
         retcode == 0 ||
         retcode == TRADE_RETCODE_DONE ||
         retcode == TRADE_RETCODE_PLACED
      );
     }

   bool IsPendingSubmitRetcodeAccepted(const uint retcode)
     {
      return(
         retcode == TRADE_RETCODE_DONE ||
         retcode == TRADE_RETCODE_PLACED
      );
     }

   bool IsRemoveRetcodeAccepted(const uint retcode)
     {
      return(retcode == TRADE_RETCODE_DONE);
     }

   bool IsCloseRetcodeAccepted(const uint retcode)
     {
      return(
         retcode == TRADE_RETCODE_DONE ||
         retcode == TRADE_RETCODE_DONE_PARTIAL
      );
     }

   ENUM_ORDER_TYPE_FILLING GetMarketFillingMode(void)
     {
      const long filling_mode = SymbolInfoInteger(
         m_symbol,
         SYMBOL_FILLING_MODE
      );

      if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;

      if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;

      return ORDER_FILLING_RETURN;
     }

   bool IsTradingEnvironmentAllowed(const ENUM_SIGNAL_DIRECTION direction,
                                    string &error)
     {
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        {
         error = "Terminal sem conexao com o servidor de negociacao.";
         return false;
        }

      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
         error = "Negociacao automatica desabilitada no terminal.";
         return false;
        }

      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
         error = "Negociacao desabilitada para o programa MQL5.";
         return false;
        }

      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
         !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
        {
         error = "Conta nao permite negociacao por Expert Advisor.";
         return false;
        }

      const ENUM_SYMBOL_TRADE_MODE trade_mode =
         (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(
            m_symbol,
            SYMBOL_TRADE_MODE
         );

      if(trade_mode == SYMBOL_TRADE_MODE_DISABLED ||
         trade_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
        {
         error = "Simbolo nao permite abertura de novas operacoes.";
         return false;
        }

      if(direction == SIGNAL_BUY &&
         trade_mode == SYMBOL_TRADE_MODE_SHORTONLY)
        {
         error = "Simbolo configurado somente para vendas.";
         return false;
        }

      if(direction == SIGNAL_SELL &&
         trade_mode == SYMBOL_TRADE_MODE_LONGONLY)
        {
         error = "Simbolo configurado somente para compras.";
         return false;
        }

      const long order_mode = SymbolInfoInteger(m_symbol, SYMBOL_ORDER_MODE);
      if((order_mode & SYMBOL_ORDER_STOP) != SYMBOL_ORDER_STOP)
        {
         error = "Simbolo nao aceita ordens Stop pendentes.";
         return false;
        }

      if((order_mode & SYMBOL_ORDER_SL) != SYMBOL_ORDER_SL ||
         (order_mode & SYMBOL_ORDER_TP) != SYMBOL_ORDER_TP)
        {
         error = "Simbolo nao aceita Stop Loss ou Take Profit na ordem.";
         return false;
        }

      error = "";
      return true;
     }

   bool IsCloseEnvironmentAllowed(string &error)
     {
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        {
         error = "Terminal sem conexao com o servidor de negociacao.";
         return false;
        }

      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
         !MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
         error = "Negociacao automatica desabilitada para fechar posicoes.";
         return false;
        }

      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
         !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
        {
         error = "Conta nao permite fechamento por Expert Advisor.";
         return false;
        }

      const ENUM_SYMBOL_TRADE_MODE trade_mode =
         (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(
            m_symbol,
            SYMBOL_TRADE_MODE
         );

      if(trade_mode == SYMBOL_TRADE_MODE_DISABLED)
        {
         error = "Simbolo indisponivel para fechamento.";
         return false;
        }

      error = "";
      return true;
     }

   bool HasSufficientMargin(const PreparedOrder &order,
                            const double volume,
                            string &error)
     {
      const ENUM_ORDER_TYPE market_order_type =
         order.direction == SIGNAL_BUY
         ? ORDER_TYPE_BUY
         : ORDER_TYPE_SELL;

      double required_margin = 0.0;
      ResetLastError();

      if(!OrderCalcMargin(
            market_order_type,
            m_symbol,
            volume,
            order.submitted_entry_price,
            required_margin
         ))
        {
         error = StringFormat(
            "OrderCalcMargin falhou. erro=%d",
            GetLastError()
         );

         return false;
        }

      const double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(required_margin > free_margin)
        {
         error = StringFormat(
            "Margem necessaria %.2f superior a margem livre %.2f.",
            required_margin,
            free_margin
         );

         return false;
        }

      error = "";
      return true;
     }

   int CountOwnPendingOrders(ulong &first_ticket)
     {
      first_ticket = 0;
      int count = 0;

      for(int index = OrdersTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = OrderGetTicket(index);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;

         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic_number)
            continue;

         const ENUM_ORDER_TYPE order_type =
            (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         if(!IsPendingOrderType(order_type))
            continue;

         count++;
         if(first_ticket == 0)
            first_ticket = ticket;
        }

      return count;
     }

   int CountOwnPositions(ulong &first_ticket,
                         bool &all_protected)
     {
      first_ticket = 0;
      all_protected = true;
      int count = 0;

      for(int index = PositionsTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic_number)
            continue;

         count++;
         if(first_ticket == 0)
            first_ticket = ticket;

         const double stop_loss = PositionGetDouble(POSITION_SL);
         const double take_profit = PositionGetDouble(POSITION_TP);

         if(stop_loss <= 0.0 || take_profit <= 0.0)
            all_protected = false;
        }

      return count;
     }

public:
   CExecutionManager(void)
     {
      m_symbol                = "";
      m_magic_number          = 0;
      m_deviation_points      = 0;
      m_log_details           = true;
      m_max_spread_points       = 0.0;
      m_min_stop_spread_ratio   = 0.0;
      m_min_stop_points_absolute = 0.0;
      m_min_stop_atr_multiple    = 0.0;
     }

   void Configure(const string symbol,
                  const ulong magic_number,
                  const ulong deviation_points,
                  const bool log_details,
                  const double max_spread_points,
                  const double min_stop_spread_ratio,
                  const double min_stop_points_absolute,
                  const double min_stop_atr_multiple)
     {
      m_symbol                = symbol;
      m_magic_number          = magic_number;
      m_deviation_points      = deviation_points;
      m_log_details           = log_details;
      m_max_spread_points        = max_spread_points;
      m_min_stop_spread_ratio    = min_stop_spread_ratio;
      m_min_stop_points_absolute = min_stop_points_absolute;
      m_min_stop_atr_multiple    = min_stop_atr_multiple;
     }

   bool Prepare(const TradePlan &plan,
                PreparedOrder &prepared,
                OperationResult &result)
     {
      result.success = false;
      result.code    = 0;
      result.message = "";

      string permission_error = "";
      if(!IsTradingEnvironmentAllowed(plan.direction, permission_error))
        {
         result.message = permission_error;
         return false;
        }

      SpreadSnapshot spread = {};
      if(!LoadSpreadSnapshot(m_symbol, spread))
        {
         result.code = spread.error_code;
         result.message = StringFormat(
            "Spread atual indisponivel. reason=%s erro=%u",
            spread.reason,
            spread.error_code
         );
         return false;
        }

      MqlTick tick = {};
      tick.bid = spread.bid;
      tick.ask = spread.ask;

      double tick_size = SymbolInfoDouble(
         m_symbol,
         SYMBOL_TRADE_TICK_SIZE
      );
      const double point = spread.point;
      const int digits = (int)SymbolInfoInteger(
         m_symbol,
         SYMBOL_DIGITS
      );

      if(tick_size <= 0.0)
         tick_size = point;

      if(tick_size <= 0.0 || point <= 0.0)
        {
         result.message = "Tick size ou point invalido.";
         return false;
        }

      const double spread_price = spread.spread_price;
      const double spread_points = spread.spread_points;

      if(m_max_spread_points > 0.0 &&
         spread_points > m_max_spread_points + 1e-9)
        {
         result.message = StringFormat(
            "Spread elevado: atual=%.2f pontos maximo=%.2f pontos.",
            spread_points,
            m_max_spread_points
         );
         return false;
        }

      const double stops_distance =
         (double)SymbolInfoInteger(
            m_symbol,
            SYMBOL_TRADE_STOPS_LEVEL
         ) * point;

      const double freeze_distance =
         (double)SymbolInfoInteger(
            m_symbol,
            SYMBOL_TRADE_FREEZE_LEVEL
         ) * point;

      const double pending_distance = MathMax(
         tick_size,
         MathMax(stops_distance, freeze_distance)
      );

      prepared.signal_id             = plan.signal_id;
      prepared.pattern_name          = plan.pattern_name;
      prepared.signal_time           = plan.signal_time;
      prepared.direction             = plan.direction;
      prepared.order_type            = plan.order_type;
      prepared.technical_entry_price = plan.technical_entry_price;
      prepared.target_r              = plan.target_r;
      prepared.signal_spread_price   = plan.signal_spread_price;
      prepared.signal_spread_points  = plan.signal_spread_points;
      prepared.spread_price          = spread_price;
      prepared.spread_points         = spread_points;
      prepared.send_spread_price     = spread_price;
      prepared.send_spread_points    = spread_points;
      prepared.stop_spread_ratio     = 0.0;
      prepared.stop_points           = 0.0;
      prepared.atr_value             = plan.atr_value;
      prepared.atr_points            = plan.atr_value / point;
      prepared.minimum_stop_points_required = 0.0;
      prepared.submitted_target_price = 0.0;
      prepared.expiration            = plan.expiration;

      if(plan.direction == SIGNAL_BUY)
        {
         const double entry_candidate = MathMax(
            plan.technical_entry_price,
            tick.ask + pending_distance
         );

         prepared.submitted_entry_price = NormalizePriceUp(
            entry_candidate,
            tick_size,
            digits
         );

         prepared.submitted_stop_price = NormalizePriceDown(
            plan.technical_stop_price,
            tick_size,
            digits
         );

        }
      else if(plan.direction == SIGNAL_SELL)
        {
         const double entry_candidate = MathMin(
            plan.technical_entry_price,
            tick.bid - pending_distance
         );

         prepared.submitted_entry_price = NormalizePriceDown(
            entry_candidate,
            tick_size,
            digits
         );

         prepared.submitted_stop_price = NormalizePriceUp(
            plan.technical_stop_price,
            tick_size,
            digits
         );

        }
      else
        {
         result.message = "Direcao do plano invalida.";
         return false;
        }

      const double risk_distance = MathAbs(
         prepared.submitted_entry_price -
         prepared.submitted_stop_price
      );

      prepared.stop_spread_ratio =
         spread_price > 0.0
         ? risk_distance / spread_price
         : 1.0e100;
      prepared.stop_points = risk_distance / point;

      const double min_by_spread =
         m_min_stop_spread_ratio > 0.0
         ? spread_points * m_min_stop_spread_ratio
         : 0.0;

      const double min_by_atr =
         m_min_stop_atr_multiple > 0.0
         ? prepared.atr_points * m_min_stop_atr_multiple
         : 0.0;

      const double min_by_broker = stops_distance / point;

      prepared.minimum_stop_points_required = MathMax(
         m_min_stop_points_absolute,
         MathMax(min_by_spread, MathMax(min_by_atr, min_by_broker))
      );

      if(prepared.submitted_entry_price <= 0.0 ||
         prepared.submitted_stop_price <= 0.0 ||
         risk_distance <= 0.0)
        {
         result.message = "Entrada ou stop preparados sao invalidos.";
         return false;
        }

      if(prepared.stop_points + 1e-9 < prepared.minimum_stop_points_required)
        {
         result.message = StringFormat(
            "Stop abaixo do minimo: atual=%.2f pts minimo=%.2f pts (abs=%.2f spread=%.2f atr=%.2f broker=%.2f).",
            prepared.stop_points,
            prepared.minimum_stop_points_required,
            m_min_stop_points_absolute,
            min_by_spread,
            min_by_atr,
            min_by_broker
         );
         return false;
        }

      if(plan.direction == SIGNAL_BUY &&
         !(prepared.submitted_stop_price < prepared.submitted_entry_price))
        {
         result.message = "Relacao entrada/stop da compra invalida.";
         return false;
        }

      if(plan.direction == SIGNAL_SELL &&
         !(prepared.submitted_stop_price > prepared.submitted_entry_price))
        {
         result.message = "Relacao entrada/stop da venda invalida.";
         return false;
        }

      result.success = true;
      result.message = "Ordem preparada com sucesso.";
      return true;
     }

   bool GetSpreadSnapshot(SpreadSnapshot &snapshot)
     {
      return LoadSpreadSnapshot(m_symbol, snapshot);
     }

   bool GetCurrentSpread(double &spread_price,
                         double &spread_points,
                         string &error)
     {
      spread_price = 0.0;
      spread_points = 0.0;
      error = "";

      SpreadSnapshot snapshot = {};
      if(!LoadSpreadSnapshot(m_symbol, snapshot))
        {
         error = StringFormat(
            "Spread indisponivel. reason=%s erro=%u",
            snapshot.reason,
            snapshot.error_code
         );
         return false;
        }

      spread_price = snapshot.spread_price;
      spread_points = snapshot.spread_points;
      return true;
     }

   bool RefreshSendSpread(PreparedOrder &prepared,
                          OperationResult &result)
     {
      result.success = false;
      result.code = 0;
      result.message = "";

      string error = "";
      double spread_price = 0.0;
      double spread_points = 0.0;
      if(!GetCurrentSpread(spread_price, spread_points, error))
        {
         result.message = error;
         return false;
        }

      if(m_max_spread_points > 0.0 &&
         spread_points > m_max_spread_points + 1e-9)
        {
         result.message = StringFormat(
            "Spread no envio elevado: atual=%.2f maximo=%.2f pontos.",
            spread_points,
            m_max_spread_points
         );
         return false;
        }

      prepared.spread_price = spread_price;
      prepared.spread_points = spread_points;
      prepared.send_spread_price = spread_price;
      prepared.send_spread_points = spread_points;

      const double risk_distance = MathAbs(
         prepared.submitted_entry_price - prepared.submitted_stop_price
      );
      prepared.stop_spread_ratio =
         spread_price > 0.0
         ? risk_distance / spread_price
         : 1.0e100;

      if(m_min_stop_spread_ratio > 0.0 &&
         prepared.stop_spread_ratio + 1e-9 < m_min_stop_spread_ratio)
        {
         result.message = StringFormat(
            "Stop/spread inseguro no envio: atual=%.2fx minimo=%.2fx.",
            prepared.stop_spread_ratio,
            m_min_stop_spread_ratio
         );
         return false;
        }

      result.success = true;
      result.message = "Spread revalidado no envio.";
      return true;
     }

   bool ValidateTarget(const PreparedOrder &prepared,
                       OperationResult &result)
     {
      result.success = false;
      result.code = 0;
      result.message = "";

      const double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0 || prepared.submitted_target_price <= 0.0)
        {
         result.message = "Target ou point invalido.";
         return false;
        }

      const double reward_distance = MathAbs(
         prepared.submitted_target_price - prepared.submitted_entry_price
      );
      const double stops_distance =
         (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

      if(stops_distance > 0.0 && reward_distance + 1e-12 < stops_distance)
        {
         result.message = StringFormat(
            "TP abaixo do stop level: alvo=%.10f minimo=%.10f",
            reward_distance,
            stops_distance
         );
         return false;
        }

      if(prepared.direction == SIGNAL_BUY &&
         prepared.submitted_target_price <= prepared.submitted_entry_price)
        {
         result.message = "TP da compra deve ficar acima da entrada.";
         return false;
        }

      if(prepared.direction == SIGNAL_SELL &&
         prepared.submitted_target_price >= prepared.submitted_entry_price)
        {
         result.message = "TP da venda deve ficar abaixo da entrada.";
         return false;
        }

      result.success = true;
      result.message = "Target validado.";
      return true;
     }

   bool Submit(PreparedOrder &prepared,
               const double volume,
               ExecutionResult &execution_result)
     {
      execution_result.success                = false;
      execution_result.retcode                = 0;
      execution_result.order_ticket           = 0;
      execution_result.deal_ticket            = 0;
      execution_result.technical_entry_price  =
         prepared.technical_entry_price;
      execution_result.requested_price        =
         prepared.submitted_entry_price;
      execution_result.submitted_entry_price  =
         prepared.submitted_entry_price;
      execution_result.submitted_stop_price   =
         prepared.submitted_stop_price;
      execution_result.submitted_target_price =
         prepared.submitted_target_price;
      execution_result.executed_price         = 0.0;
      execution_result.message                = "";

      if(HasAnyTradingActivityForSymbol())
        {
         execution_result.message =
            "Ja existe ordem ou posicao ativa no simbolo.";
         return false;
        }

      // Ultima leitura imediatamente antes de OrderCheck/OrderSend. Se o
      // spread piorou apos o sizing, aborta em vez de enviar com risco
      // subestimado. Spread menor e seguro e pode ser aceito.
      double current_spread_price = 0.0;
      double current_spread_points = 0.0;
      string current_spread_error = "";
      if(!GetCurrentSpread(
            current_spread_price,
            current_spread_points,
            current_spread_error
         ))
        {
         execution_result.message = current_spread_error;
         return false;
        }

      if(current_spread_points > prepared.send_spread_points + 1e-9)
        {
         execution_result.message = StringFormat(
            "Spread aumentou entre sizing e envio: sizing=%.2fpts envio=%.2fpts; ordem abortada.",
            prepared.send_spread_points,
            current_spread_points
         );
         return false;
        }

      prepared.send_spread_price = current_spread_price;
      prepared.send_spread_points = current_spread_points;

      OperationResult target_result = {};
      if(!ValidateTarget(prepared, target_result))
        {
         execution_result.message = target_result.message;
         return false;
        }

      execution_result.submitted_target_price = prepared.submitted_target_price;

      string margin_error = "";
      if(!HasSufficientMargin(prepared, volume, margin_error))
        {
         execution_result.message = margin_error;
         return false;
        }

      MqlTradeRequest request = {};
      MqlTradeCheckResult check_result = {};
      MqlTradeResult result = {};

      request.action       = TRADE_ACTION_PENDING;
      request.magic        = m_magic_number;
      request.symbol       = m_symbol;
      request.volume       = volume;
      request.price        = prepared.submitted_entry_price;
      execution_result.requested_price = request.price;
      request.sl           = prepared.submitted_stop_price;
      request.tp           = prepared.submitted_target_price;
      request.deviation    = m_deviation_points;
      request.type         = prepared.order_type;
      request.type_filling = ORDER_FILLING_RETURN;
      request.type_time    = ORDER_TIME_GTC;
      request.expiration   = 0;
      request.comment      = prepared.signal_id;

      ResetLastError();
      if(!OrderCheck(request, check_result))
        {
         execution_result.retcode = check_result.retcode;
         execution_result.message = StringFormat(
            "OrderCheck falhou localmente. erro=%d retcode=%u comentario=%s",
            GetLastError(),
            check_result.retcode,
            check_result.comment
         );

         return false;
        }

      if(!IsCheckRetcodeAccepted(check_result.retcode))
        {
         execution_result.retcode = check_result.retcode;
         execution_result.message = StringFormat(
            "OrderCheck rejeitado. retcode=%u comentario=%s",
            check_result.retcode,
            check_result.comment
         );

         return false;
        }

      ResetLastError();
      if(!OrderSend(request, result))
        {
         execution_result.retcode = result.retcode;
         execution_result.message = StringFormat(
            "OrderSend falhou localmente. erro=%d retcode=%u comentario=%s",
            GetLastError(),
            result.retcode,
            result.comment
         );

         return false;
        }

      execution_result.retcode      = result.retcode;
      execution_result.order_ticket = result.order;
      execution_result.deal_ticket  = result.deal;
      execution_result.executed_price = result.price;

      if(!IsPendingSubmitRetcodeAccepted(result.retcode))
        {
         execution_result.message = StringFormat(
            "Ordem rejeitada. retcode=%u comentario=%s",
            result.retcode,
            result.comment
         );

         return false;
        }

      execution_result.success = true;
      execution_result.message = StringFormat(
         "Ordem aceita. ticket=%I64u retcode=%u",
         result.order,
         result.retcode
      );

      return true;
     }

   bool CancelPendingOrder(const ulong order_ticket,
                           OperationResult &operation_result)
     {
      operation_result.success = false;
      operation_result.code    = 0;
      operation_result.message = "";

      if(order_ticket == 0 || !OrderSelect(order_ticket))
        {
         operation_result.message = "Ordem pendente nao encontrada.";
         return false;
        }

      if(OrderGetString(ORDER_SYMBOL) != m_symbol ||
         (ulong)OrderGetInteger(ORDER_MAGIC) != m_magic_number)
        {
         operation_result.message = "Ordem nao pertence a este EA.";
         return false;
        }

      const ENUM_ORDER_TYPE order_type =
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(!IsPendingOrderType(order_type))
        {
         operation_result.message = "Ticket nao representa ordem pendente.";
         return false;
        }

      MqlTradeRequest request = {};
      MqlTradeCheckResult check_result = {};
      MqlTradeResult result = {};

      request.action = TRADE_ACTION_REMOVE;
      request.order  = order_ticket;

      ResetLastError();
      if(!OrderCheck(request, check_result))
        {
         operation_result.code = check_result.retcode;
         operation_result.message = StringFormat(
            "OrderCheck do cancelamento falhou. erro=%d retcode=%u comentario=%s",
            GetLastError(),
            check_result.retcode,
            check_result.comment
         );

         return false;
        }

      if(!IsCheckRetcodeAccepted(check_result.retcode))
        {
         operation_result.code = check_result.retcode;
         operation_result.message = StringFormat(
            "Cancelamento rejeitado no OrderCheck. retcode=%u comentario=%s",
            check_result.retcode,
            check_result.comment
         );

         return false;
        }

      ResetLastError();
      if(!OrderSend(request, result))
        {
         operation_result.code = result.retcode;
         operation_result.message = StringFormat(
            "OrderSend do cancelamento falhou. erro=%d retcode=%u comentario=%s",
            GetLastError(),
            result.retcode,
            result.comment
         );

         return false;
        }

      operation_result.code = result.retcode;
      if(!IsRemoveRetcodeAccepted(result.retcode))
        {
         operation_result.message = StringFormat(
            "Cancelamento rejeitado. retcode=%u comentario=%s",
            result.retcode,
            result.comment
         );

         return false;
        }

      operation_result.success = true;
      operation_result.message = StringFormat(
         "Ordem #%I64u cancelada.",
         order_ticket
      );

      return true;
     }

   bool CancelExpiredPendingOrders(const datetime current_bar_open,
                                   OperationResult &operation_result)
     {
      operation_result.success = true;
      operation_result.code    = 0;
      operation_result.message = "Nenhuma ordem vencida.";

      for(int index = OrdersTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = OrderGetTicket(index);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;

         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic_number)
            continue;

         const ENUM_ORDER_TYPE order_type =
            (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         if(!IsPendingOrderType(order_type))
            continue;

         const datetime setup_time =
            (datetime)OrderGetInteger(ORDER_TIME_SETUP);

         if(setup_time >= current_bar_open)
            continue;

         OperationResult cancel_result = {};
         if(!CancelPendingOrder(ticket, cancel_result))
           {
            operation_result = cancel_result;
            return false;
           }

         operation_result = cancel_result;
        }

      return true;
     }

   bool CancelAllPendingOrders(OperationResult &operation_result)
     {
      operation_result.success = true;
      operation_result.code    = 0;
      operation_result.message = "Nenhuma ordem pendente do EA encontrada.";

      int cancelled_count = 0;

      for(int index = OrdersTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = OrderGetTicket(index);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;

         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic_number)
            continue;

         const ENUM_ORDER_TYPE order_type =
            (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         if(!IsPendingOrderType(order_type))
            continue;

         OperationResult cancel_result = {};
         if(!CancelPendingOrder(ticket, cancel_result))
           {
            operation_result = cancel_result;
            return false;
           }

         cancelled_count++;
        }

      operation_result.message = StringFormat(
         "%d ordem(ns) pendente(s) cancelada(s).",
         cancelled_count
      );
      return true;
     }

   // Revalida ordens pendentes usando o spread corrente. A ordem e
   // cancelada quando o spread excede o maximo ou quando a distancia
   // entrada-stop deixa de respeitar o multiplo minimo configurado.
   bool CancelPendingOrdersWithUnsafeSpread(
      OperationResult &operation_result
   )
     {
      operation_result.success = true;
      operation_result.code    = 0;
      operation_result.message =
         "Nenhuma ordem pendente cancelada por spread.";

      if(m_max_spread_points <= 0.0 &&
         m_min_stop_spread_ratio <= 0.0)
         return true;

      SpreadSnapshot spread = {};
      if(!LoadSpreadSnapshot(m_symbol, spread))
        {
         operation_result.success = false;
         operation_result.code = spread.error_code;
         operation_result.message = StringFormat(
            "Spread indisponivel na protecao de ordem pendente. reason=%s erro=%u",
            spread.reason,
            spread.error_code
         );
         return false;
        }

      const double spread_price = spread.spread_price;
      const double spread_points = spread.spread_points;
      int cancelled_count = 0;

      for(int index = OrdersTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = OrderGetTicket(index);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;

         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic_number)
            continue;

         const ENUM_ORDER_TYPE order_type =
            (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         if(!IsPendingOrderType(order_type))
            continue;

         const double entry_price = OrderGetDouble(ORDER_PRICE_OPEN);
         const double stop_price  = OrderGetDouble(ORDER_SL);
         const double risk_distance = MathAbs(entry_price - stop_price);
         const double stop_spread_ratio =
            spread_price > 0.0
            ? risk_distance / spread_price
            : 1.0e100;

         const bool is_spread_above_maximum =
            m_max_spread_points > 0.0 &&
            spread_points > m_max_spread_points + 1e-9;

         const bool is_stop_ratio_unsafe =
            m_min_stop_spread_ratio > 0.0 &&
            stop_spread_ratio + 1e-9 < m_min_stop_spread_ratio;

         if(!is_spread_above_maximum && !is_stop_ratio_unsafe)
            continue;

         OperationResult cancel_result = {};
         if(!CancelPendingOrder(ticket, cancel_result))
           {
            operation_result = cancel_result;
            return false;
           }

         cancelled_count++;
         operation_result.message = StringFormat(
            "%d ordem(ns) cancelada(s): spread=%.2f pontos, stop/spread=%.2fx, maximo=%.2f, minimo=%.2fx.",
            cancelled_count,
            spread_points,
            stop_spread_ratio,
            m_max_spread_points,
            m_min_stop_spread_ratio
         );
        }

      return true;
     }

   bool ClosePosition(const ulong position_ticket,
                      const string close_reason,
                      OperationResult &operation_result)
     {
      operation_result.success = false;
      operation_result.code    = 0;
      operation_result.message = "";

      string environment_error = "";
      if(!IsCloseEnvironmentAllowed(environment_error))
        {
         operation_result.message = environment_error;
         return false;
        }

      if(position_ticket == 0 || !PositionSelectByTicket(position_ticket))
        {
         operation_result.message = "Posicao nao encontrada para fechamento.";
         return false;
        }

      if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic_number)
        {
         operation_result.message = "Posicao nao pertence a este EA.";
         return false;
        }

      const ENUM_POSITION_TYPE position_type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const double position_volume = PositionGetDouble(POSITION_VOLUME);

      if(position_volume <= 0.0)
        {
         operation_result.message = "Volume da posicao invalido.";
         return false;
        }

      MqlTick tick = {};
      ResetLastError();
      if(!SymbolInfoTick(m_symbol, tick))
        {
         operation_result.code = (uint)GetLastError();
         operation_result.message = StringFormat(
            "SymbolInfoTick falhou no fechamento. erro=%d",
            GetLastError()
         );
         return false;
        }

      MqlTradeRequest request = {};
      MqlTradeCheckResult check_result = {};
      MqlTradeResult result = {};

      request.action       = TRADE_ACTION_DEAL;
      request.magic        = m_magic_number;
      request.position     = position_ticket;
      request.symbol       = m_symbol;
      request.volume       = position_volume;
      request.deviation    = m_deviation_points;
      request.type_filling = GetMarketFillingMode();
      request.comment      = close_reason;

      if(position_type == POSITION_TYPE_BUY)
        {
         request.type  = ORDER_TYPE_SELL;
         request.price = tick.bid;
        }
      else if(position_type == POSITION_TYPE_SELL)
        {
         request.type  = ORDER_TYPE_BUY;
         request.price = tick.ask;
        }
      else
        {
         operation_result.message = "Tipo de posicao desconhecido.";
         return false;
        }

      ResetLastError();
      if(!OrderCheck(request, check_result))
        {
         operation_result.code = check_result.retcode;
         operation_result.message = StringFormat(
            "OrderCheck do fechamento falhou. erro=%d retcode=%u comentario=%s",
            GetLastError(),
            check_result.retcode,
            check_result.comment
         );
         return false;
        }

      if(!IsCheckRetcodeAccepted(check_result.retcode))
        {
         operation_result.code = check_result.retcode;
         operation_result.message = StringFormat(
            "Fechamento rejeitado no OrderCheck. retcode=%u comentario=%s",
            check_result.retcode,
            check_result.comment
         );
         return false;
        }

      ResetLastError();
      if(!OrderSend(request, result))
        {
         operation_result.code = result.retcode;
         operation_result.message = StringFormat(
            "OrderSend do fechamento falhou. erro=%d retcode=%u comentario=%s",
            GetLastError(),
            result.retcode,
            result.comment
         );
         return false;
        }

      operation_result.code = result.retcode;
      if(!IsCloseRetcodeAccepted(result.retcode))
        {
         operation_result.message = StringFormat(
            "Fechamento rejeitado. retcode=%u comentario=%s",
            result.retcode,
            result.comment
         );
         return false;
        }

      operation_result.success = true;
      operation_result.message = StringFormat(
         "Posicao #%I64u enviada para fechamento. retcode=%u",
         position_ticket,
         result.retcode
      );
      return true;
     }

   bool ReducePosition(const ulong position_ticket,
                       const double target_volume,
                       const string reduce_reason,
                       OperationResult &operation_result)
     {
      operation_result.success = false;
      operation_result.code = 0;
      operation_result.message = "";

      if(position_ticket == 0 || !PositionSelectByTicket(position_ticket))
        {
         operation_result.message = "Posicao nao encontrada para reducao.";
         return false;
        }

      if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic_number)
        {
         operation_result.message = "Posicao nao pertence a este EA.";
         return false;
        }

      const double current_volume = PositionGetDouble(POSITION_VOLUME);
      const double volume_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      const double volume_min = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      if(current_volume <= 0.0 || volume_step <= 0.0 || volume_min <= 0.0)
        {
         operation_result.message = "Dados de volume invalidos para reducao.";
         return false;
        }

      if(target_volume <= 0.0 || target_volume + 1e-12 < volume_min)
         return ClosePosition(position_ticket, reduce_reason, operation_result);

      if(target_volume >= current_volume - 1e-12)
        {
         operation_result.success = true;
         operation_result.message = "Reducao desnecessaria; volume ja esta dentro do limite.";
         return true;
        }

      double reduce_volume = current_volume - target_volume;
      reduce_volume = MathFloor(reduce_volume / volume_step + 1e-9) * volume_step;
      reduce_volume = NormalizeDouble(reduce_volume, 8);

      if(reduce_volume + 1e-12 < volume_min)
        {
         operation_result.message = "Volume a reduzir ficou abaixo do lote minimo.";
         return false;
        }

      string environment_error = "";
      if(!IsCloseEnvironmentAllowed(environment_error))
        {
         operation_result.message = environment_error;
         return false;
        }

      const ENUM_POSITION_TYPE position_type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      MqlTick tick = {};
      ResetLastError();
      if(!SymbolInfoTick(m_symbol, tick))
        {
         operation_result.code = (uint)GetLastError();
         operation_result.message = StringFormat(
            "SymbolInfoTick falhou na reducao. erro=%d",
            GetLastError()
         );
         return false;
        }

      MqlTradeRequest request = {};
      MqlTradeCheckResult check_result = {};
      MqlTradeResult result = {};

      request.action       = TRADE_ACTION_DEAL;
      request.magic        = m_magic_number;
      request.position     = position_ticket;
      request.symbol       = m_symbol;
      request.volume       = reduce_volume;
      request.deviation    = m_deviation_points;
      request.type_filling = GetMarketFillingMode();
      request.comment      = reduce_reason;

      if(position_type == POSITION_TYPE_BUY)
        {
         request.type = ORDER_TYPE_SELL;
         request.price = tick.bid;
        }
      else if(position_type == POSITION_TYPE_SELL)
        {
         request.type = ORDER_TYPE_BUY;
         request.price = tick.ask;
        }
      else
        {
         operation_result.message = "Tipo de posicao invalido para reducao.";
         return false;
        }

      ResetLastError();
      if(!OrderCheck(request, check_result))
        {
         operation_result.code = check_result.retcode;
         operation_result.message = StringFormat(
            "OrderCheck da reducao falhou. erro=%d retcode=%u comentario=%s",
            GetLastError(), check_result.retcode, check_result.comment
         );
         return false;
        }

      if(!IsCheckRetcodeAccepted(check_result.retcode))
        {
         operation_result.code = check_result.retcode;
         operation_result.message = StringFormat(
            "Reducao rejeitada no OrderCheck. retcode=%u comentario=%s",
            check_result.retcode, check_result.comment
         );
         return false;
        }

      ResetLastError();
      if(!OrderSend(request, result))
        {
         operation_result.code = result.retcode;
         operation_result.message = StringFormat(
            "OrderSend da reducao falhou. erro=%d retcode=%u comentario=%s",
            GetLastError(), result.retcode, result.comment
         );
         return false;
        }

      operation_result.code = result.retcode;
      if(!IsCloseRetcodeAccepted(result.retcode))
        {
         operation_result.message = StringFormat(
            "Reducao rejeitada. retcode=%u comentario=%s",
            result.retcode, result.comment
         );
         return false;
        }

      operation_result.success = true;
      operation_result.message = StringFormat(
         "Reducao enviada: atual=%.8f alvo=%.8f reduzir=%.8f.",
         current_volume, target_volume, reduce_volume
      );
      return true;
     }

   bool CloseAllOwnPositions(const string close_reason,
                             OperationResult &operation_result)
     {
      operation_result.success = true;
      operation_result.code    = 0;
      operation_result.message = "Nenhuma posicao do EA encontrada.";

      int close_count = 0;

      for(int index = PositionsTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic_number)
            continue;

         OperationResult close_result = {};
         if(!ClosePosition(ticket, close_reason, close_result))
           {
            operation_result = close_result;
            return false;
           }

         close_count++;
        }

      operation_result.message = StringFormat(
         "%d posicao(oes) enviada(s) para fechamento.",
         close_count
      );
      return true;
     }

   bool GetOwnPosition(const ulong position_ticket,
                       ENUM_SIGNAL_DIRECTION &direction,
                       double &volume,
                       double &open_price,
                       double &stop_price,
                       double &target_price,
                       string &error)
     {
      direction = SIGNAL_NONE;
      volume = 0.0;
      open_price = 0.0;
      stop_price = 0.0;
      target_price = 0.0;
      error = "";

      if(position_ticket == 0 || !PositionSelectByTicket(position_ticket))
        {
         error = "Posicao nao encontrada.";
         return false;
        }

      if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic_number)
        {
         error = "Posicao nao pertence a este EA.";
         return false;
        }

      const ENUM_POSITION_TYPE position_type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(position_type == POSITION_TYPE_BUY)
         direction = SIGNAL_BUY;
      else if(position_type == POSITION_TYPE_SELL)
         direction = SIGNAL_SELL;
      else
        {
         error = "Tipo de posicao desconhecido.";
         return false;
        }

      volume       = PositionGetDouble(POSITION_VOLUME);
      open_price   = PositionGetDouble(POSITION_PRICE_OPEN);
      stop_price   = PositionGetDouble(POSITION_SL);
      target_price = PositionGetDouble(POSITION_TP);

      if(volume <= 0.0 || open_price <= 0.0 || stop_price <= 0.0)
        {
         error = "Dados da posicao invalidos.";
         return false;
        }

      return true;
     }

   bool HasAnyTradingActivityForSymbol(void)
     {
      for(int index = PositionsTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = PositionGetTicket(index);
         if(ticket == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) == m_symbol)
            return true;
        }

      for(int index = OrdersTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = OrderGetTicket(index);
         if(ticket == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol)
            return true;
        }

      return false;
     }

   bool RecoverState(ENUM_EA_STATE &state,
                     ulong &pending_order_ticket,
                     ulong &position_ticket,
                     string &error)
     {
      bool all_positions_protected = true;

      const int pending_count = CountOwnPendingOrders(
         pending_order_ticket
      );

      const int position_count = CountOwnPositions(
         position_ticket,
         all_positions_protected
      );

      if(pending_count > 1 || position_count > 1)
        {
         error = StringFormat(
            "Estado inconsistente: ordens=%d posicoes=%d.",
            pending_count,
            position_count
         );

         return false;
        }

      if(pending_count > 0 && position_count > 0)
        {
         // Durante OnTradeTransaction pode existir uma janela transitoria em
         // que o deal/posicao ja foi criado e a ordem pendente ainda nao foi
         // removida da lista. Tambem cobre fill parcial conservadoramente.
         // A posicao prevalece para impedir qualquer nova entrada.
         if(!all_positions_protected)
           {
            error = "Posicao aberta sem Stop Loss ou Take Profit durante fill.";
            return false;
           }

         state = EA_STATE_POSITION_OPEN;
         error = "";
         return true;
        }

      if(position_count == 1)
        {
         if(!all_positions_protected)
           {
            error = "Posicao aberta sem Stop Loss ou Take Profit.";
            return false;
           }

         state = EA_STATE_POSITION_OPEN;
         error = "";
         return true;
        }

      if(pending_count == 1)
        {
         state = EA_STATE_ORDER_PENDING;
         error = "";
         return true;
        }

      state = EA_STATE_IDLE;
      pending_order_ticket = 0;
      position_ticket = 0;
      error = "";
      return true;
     }

   void ProcessTransaction(const MqlTradeTransaction &transaction,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result)
     {
      if(!m_log_details)
         return;

      string symbol = transaction.symbol;
      if(symbol == "")
         symbol = request.symbol;

      if(symbol != m_symbol)
         return;

      const string signal_id = request.comment;
      const string message = StringFormat(
         "tipo=%d order=%I64u deal=%I64u position=%I64u preco=%.*f volume=%.8f retcode=%u",
         (int)transaction.type,
         transaction.order,
         transaction.deal,
         transaction.position,
         (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS),
         transaction.price,
         transaction.volume,
         result.retcode
      );

      PrintFormat(
         "%s | INFO | TRADE_TRANSACTION | %s | %s | %s",
         TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
         m_symbol,
         signal_id,
         message
      );
     }
  };

#endif
