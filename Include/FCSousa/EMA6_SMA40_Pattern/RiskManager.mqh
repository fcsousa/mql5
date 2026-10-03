#ifndef EMA_PADROES_1R_RISK_MANAGER_MQH
#define EMA_PADROES_1R_RISK_MANAGER_MQH

#include <FCSousa/EMA6_SMA40_Pattern/Types.mqh>

//====================================================================
// CRiskManager
//
// Responsabilidades:
// - calcular lote pelo risco total esperado no stop;
// - incluir perda tecnica + comissao + spread + reserva de slippage;
// - limitar custo de round trip como percentual do risco;
// - aplicar limite absoluto de lote;
// - calcular TP para entregar R liquido apos os custos estimados;
// - recalcular risco apos o fill usando o preco realmente executado.
//====================================================================
class CRiskManager
  {
private:
   double m_max_round_trip_cost_risk_percent;
   double m_max_volume_lots;
   double m_round_trip_commission_per_lot;
   double m_round_trip_slippage_reserve_points;

   int VolumeDigits(const string symbol)
     {
      const double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      for(int digits = 0; digits <= 8; digits++)
        {
         if(MathAbs(volume_step - NormalizeDouble(volume_step, digits)) < 1e-9)
            return digits;
        }

      return 8;
     }

   double NormalizeVolumeDown(const string symbol,
                              const double volume)
     {
      const double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(volume_step <= 0.0)
         return 0.0;

      const double normalized =
         MathFloor(volume / volume_step + 1e-9) * volume_step;

      return NormalizeDouble(normalized, VolumeDigits(symbol));
     }

   ENUM_ORDER_TYPE MarketOrderType(const ENUM_SIGNAL_DIRECTION direction)
     {
      return direction == SIGNAL_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
     }

   bool CalculateAdverseMoveCostPerLot(const string symbol,
                                       const ENUM_SIGNAL_DIRECTION direction,
                                       const double reference_price,
                                       const double adverse_price_distance,
                                       double &cost,
                                       string &error)
     {
      cost = 0.0;
      error = "";

      if(adverse_price_distance <= 0.0)
         return true;

      const ENUM_ORDER_TYPE order_type = MarketOrderType(direction);
      const double close_price =
         direction == SIGNAL_BUY
         ? reference_price - adverse_price_distance
         : reference_price + adverse_price_distance;

      double profit = 0.0;
      ResetLastError();

      if(!OrderCalcProfit(
            order_type,
            symbol,
            1.0,
            reference_price,
            close_price,
            profit
         ))
        {
         error = StringFormat(
            "OrderCalcProfit falhou ao estimar custo. erro=%d",
            GetLastError()
         );
         return false;
        }

      cost = MathAbs(profit);
      if(!MathIsValidNumber(cost))
        {
         error = "Custo calculado nao e numericamente valido.";
         return false;
        }

      return true;
     }

   bool CalculateTechnicalLossPerLot(const string symbol,
                                      const ENUM_SIGNAL_DIRECTION direction,
                                      const double entry_price,
                                      const double stop_price,
                                      double &loss,
                                      string &error)
     {
      loss = 0.0;
      error = "";

      if(entry_price <= 0.0 || stop_price <= 0.0 ||
         MathAbs(entry_price - stop_price) <= 1e-12)
        {
         error = "Entrada ou stop invalido para calcular a perda tecnica.";
         return false;
        }

      double profit = 0.0;
      ResetLastError();

      if(!OrderCalcProfit(
            MarketOrderType(direction),
            symbol,
            1.0,
            entry_price,
            stop_price,
            profit
         ))
        {
         error = StringFormat(
            "OrderCalcProfit falhou na perda tecnica. erro=%d",
            GetLastError()
         );
         return false;
        }

      loss = MathAbs(profit);
      if(loss <= 0.0 || !MathIsValidNumber(loss))
        {
         error = "Perda tecnica por lote invalida.";
         return false;
        }

      return true;
     }

   bool CalculateTargetPrice(const string symbol,
                             const PreparedOrder &order,
                             const double volume,
                             const double gross_target_profit,
                             double &target_price,
                             string &error)
     {
      target_price = 0.0;
      error = "";

      if(volume <= 0.0 || gross_target_profit <= 0.0)
        {
         error = "Volume ou lucro bruto alvo invalido.";
         return false;
        }

      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      if(tick_size <= 0.0)
         tick_size = point;

      if(tick_size <= 0.0)
        {
         error = "Tick size invalido para calcular o alvo.";
         return false;
        }

      const double one_tick_close =
         order.direction == SIGNAL_BUY
         ? order.submitted_entry_price + tick_size
         : order.submitted_entry_price - tick_size;

      double one_tick_profit = 0.0;
      ResetLastError();

      if(!OrderCalcProfit(
            MarketOrderType(order.direction),
            symbol,
            volume,
            order.submitted_entry_price,
            one_tick_close,
            one_tick_profit
         ))
        {
         error = StringFormat(
            "OrderCalcProfit falhou ao calcular TP liquido. erro=%d",
            GetLastError()
         );
         return false;
        }

      const double profit_per_tick = MathAbs(one_tick_profit);
      if(profit_per_tick <= 0.0 || !MathIsValidNumber(profit_per_tick))
        {
         error = "Lucro por tick invalido para calcular o TP.";
         return false;
        }

      const double target_ticks = MathCeil(
         gross_target_profit / profit_per_tick - 1e-12
      );

      if(target_ticks < 1.0)
        {
         error = "Quantidade de ticks do alvo invalida.";
         return false;
        }

      const double raw_target =
         order.direction == SIGNAL_BUY
         ? order.submitted_entry_price + target_ticks * tick_size
         : order.submitted_entry_price - target_ticks * tick_size;

      target_price = NormalizeDouble(raw_target, digits);
      return target_price > 0.0;
     }

public:
   CRiskManager(void)
     {
      m_max_round_trip_cost_risk_percent    = 10.0;
      m_max_volume_lots                     = 10.0;
      m_round_trip_commission_per_lot       = 0.0;
      m_round_trip_slippage_reserve_points  = 2.0;
     }

   void Configure(const double max_round_trip_cost_risk_percent,
                  const double max_volume_lots,
                  const double round_trip_commission_per_lot,
                  const double round_trip_slippage_reserve_points)
     {
      m_max_round_trip_cost_risk_percent   = max_round_trip_cost_risk_percent;
      m_max_volume_lots                    = max_volume_lots;
      m_round_trip_commission_per_lot      = round_trip_commission_per_lot;
      m_round_trip_slippage_reserve_points = round_trip_slippage_reserve_points;
     }

   bool EstimateRoundTripCosts(const string symbol,
                               const ENUM_SIGNAL_DIRECTION direction,
                               const double reference_price,
                               const double volume,
                               const double spread_price,
                               CostEstimate &cost)
     {
      cost.success          = false;
      cost.commission_per_lot = 0.0;
      cost.spread_per_lot     = 0.0;
      cost.slippage_per_lot   = 0.0;
      cost.total_per_lot      = 0.0;
      cost.commission_total   = 0.0;
      cost.spread_total       = 0.0;
      cost.slippage_total     = 0.0;
      cost.total              = 0.0;
      cost.message            = "";

      if(volume <= 0.0 ||
         reference_price <= 0.0 ||
         !MathIsValidNumber(spread_price) ||
         spread_price < 0.0)
        {
         cost.message = "Dados invalidos para estimativa de custos.";
         return false;
        }

      const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
        {
         cost.message = "SYMBOL_POINT invalido na estimativa de custos.";
         return false;
        }

      string error = "";
      if(!CalculateAdverseMoveCostPerLot(
            symbol,
            direction,
            reference_price,
            spread_price,
            cost.spread_per_lot,
            error
         ))
        {
         cost.message = error;
         return false;
        }

      const double slippage_price =
         m_round_trip_slippage_reserve_points * point;

      if(!CalculateAdverseMoveCostPerLot(
            symbol,
            direction,
            reference_price,
            slippage_price,
            cost.slippage_per_lot,
            error
         ))
        {
         cost.message = error;
         return false;
        }

      cost.commission_per_lot = MathMax(
         0.0,
         m_round_trip_commission_per_lot
      );

      cost.total_per_lot =
         cost.commission_per_lot +
         cost.spread_per_lot +
         cost.slippage_per_lot;

      cost.commission_total = cost.commission_per_lot * volume;
      cost.spread_total     = cost.spread_per_lot * volume;
      cost.slippage_total   = cost.slippage_per_lot * volume;
      cost.total            = cost.total_per_lot * volume;
      cost.success          = true;
      cost.message          = "Custos estimados com sucesso.";
      return true;
     }

   bool Calculate(const string symbol,
                  const PreparedOrder &order,
                  const double risk_percent,
                  RiskResult &result)
     {
      ZeroMemory(result);
      result.message = "";

      if(risk_percent <= 0.0)
        {
         result.message = "Percentual de risco deve ser maior que zero.";
         return false;
        }

      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      result.risk_budget_money = balance * risk_percent / 100.0;

      if(balance <= 0.0 || result.risk_budget_money <= 0.0)
        {
         result.message = "Saldo ou risco financeiro invalido.";
         return false;
        }

      string technical_error = "";
      if(!CalculateTechnicalLossPerLot(
            symbol,
            order.direction,
            order.submitted_entry_price,
            order.submitted_stop_price,
            result.technical_loss_per_lot,
            technical_error
         ))
        {
         result.message = technical_error;
         return false;
        }

      CostEstimate one_lot_cost = {};
      if(!EstimateRoundTripCosts(
            symbol,
            order.direction,
            order.submitted_entry_price,
            1.0,
            order.spread_price,
            one_lot_cost
         ))
        {
         result.message = one_lot_cost.message;
         return false;
        }

      result.total_loss_per_lot =
         result.technical_loss_per_lot + one_lot_cost.total_per_lot;

      if(result.total_loss_per_lot <= 0.0 ||
         !MathIsValidNumber(result.total_loss_per_lot))
        {
         result.message = "Perda total por lote invalida.";
         return false;
        }

      const double one_lot_cost_risk_percent =
         one_lot_cost.total_per_lot / result.total_loss_per_lot * 100.0;

      if(m_max_round_trip_cost_risk_percent > 0.0 &&
         one_lot_cost_risk_percent >
            m_max_round_trip_cost_risk_percent + 1e-9)
        {
         result.message = StringFormat(
            "Custo round trip %.2f%% do risco excede maximo %.2f%%.",
            one_lot_cost_risk_percent,
            m_max_round_trip_cost_risk_percent
         );
         return false;
        }

      const double volume_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      const double volume_max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      const double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(volume_min <= 0.0 || volume_max <= 0.0 || volume_step <= 0.0)
        {
         result.message = "Propriedades de volume do simbolo sao invalidas.";
         return false;
        }

      const double raw_volume =
         result.risk_budget_money / result.total_loss_per_lot;

      if(raw_volume + 1e-12 < volume_min)
        {
         result.message = StringFormat(
            "Volume calculado %.8f abaixo do minimo %.8f; lote minimo excederia o risco total.",
            raw_volume,
            volume_min
         );
         return false;
        }

      double maximum_allowed_volume = volume_max;
      if(m_max_volume_lots > 0.0)
         maximum_allowed_volume = MathMin(maximum_allowed_volume, m_max_volume_lots);

      if(maximum_allowed_volume + 1e-12 < volume_min)
        {
         result.message = StringFormat(
            "InpMaxVolumeLots %.8f esta abaixo do lote minimo %.8f.",
            m_max_volume_lots,
            volume_min
         );
         return false;
        }

      result.volume = NormalizeVolumeDown(
         symbol,
         MathMin(raw_volume, maximum_allowed_volume)
      );

      if(result.volume < volume_min || result.volume > volume_max)
        {
         result.message = "Volume normalizado fora dos limites do simbolo.";
         return false;
        }

      CostEstimate final_cost = {};
      if(!EstimateRoundTripCosts(
            symbol,
            order.direction,
            order.submitted_entry_price,
            result.volume,
            order.spread_price,
            final_cost
         ))
        {
         result.message = final_cost.message;
         return false;
        }

      result.planned_technical_loss =
         result.technical_loss_per_lot * result.volume;

      result.estimated_commission    = final_cost.commission_total;
      result.estimated_spread_cost   = final_cost.spread_total;
      result.estimated_slippage_cost = final_cost.slippage_total;
      result.estimated_cost          = final_cost.total;
      result.planned_total_risk      =
         result.planned_technical_loss + result.estimated_cost;

      if(result.planned_total_risk > result.risk_budget_money + 0.01)
        {
         result.message = StringFormat(
            "Risco planejado %.2f excede o limite %.2f.",
            result.planned_total_risk,
            result.risk_budget_money
         );
         return false;
        }

      result.round_trip_cost_risk_percent =
         result.planned_total_risk > 0.0
         ? result.estimated_cost / result.planned_total_risk * 100.0
         : 0.0;

      if(m_max_round_trip_cost_risk_percent > 0.0 &&
         result.round_trip_cost_risk_percent >
            m_max_round_trip_cost_risk_percent + 1e-9)
        {
         result.message = StringFormat(
            "Custo estimado %.2f%% do risco planejado excede maximo %.2f%%.",
            result.round_trip_cost_risk_percent,
            m_max_round_trip_cost_risk_percent
         );
         return false;
        }

      // R liquido: lucro bruto necessario = risco planejado * TargetR + custos.
      result.gross_target_profit =
         result.planned_total_risk * order.target_r + result.estimated_cost;

      string target_error = "";
      if(!CalculateTargetPrice(
            symbol,
            order,
            result.volume,
            result.gross_target_profit,
            result.target_price,
            target_error
         ))
        {
         result.message = target_error;
         return false;
        }

      result.success = true;
      result.message = StringFormat(
         "Risco total calculado. lote=%.8f risco=%.2f custo=%.2f custo/risco=%.2f%% alvo_bruto=%.2f",
         result.volume,
         result.planned_total_risk,
         result.estimated_cost,
         result.round_trip_cost_risk_percent,
         result.gross_target_profit
      );
      return true;
     }

   bool CalculateActualSlippageCost(const string symbol,
                                    const ENUM_SIGNAL_DIRECTION direction,
                                    const double submitted_price,
                                    const double executed_price,
                                    const double volume,
                                    double &cost,
                                    double &slippage_points,
                                    string &error)
     {
      cost = 0.0;
      slippage_points = 0.0;
      error = "";

      if(submitted_price <= 0.0 || executed_price <= 0.0 || volume <= 0.0)
        {
         error = "Dados invalidos para calcular slippage real.";
         return false;
        }

      const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
        {
         error = "SYMBOL_POINT invalido no calculo de slippage.";
         return false;
        }

      const double raw_slippage =
         direction == SIGNAL_BUY
         ? executed_price - submitted_price
         : submitted_price - executed_price;

      slippage_points = raw_slippage / point;

      // Slippage favoravel nao e tratado como custo.
      if(raw_slippage <= 0.0)
         return true;

      double profit = 0.0;
      ResetLastError();
      if(!OrderCalcProfit(
            MarketOrderType(direction),
            symbol,
            volume,
            submitted_price,
            executed_price,
            profit
         ))
        {
         error = StringFormat(
            "OrderCalcProfit falhou no slippage real. erro=%d",
            GetLastError()
         );
         return false;
        }

      cost = MathAbs(profit);
      return MathIsValidNumber(cost);
     }

   bool CalculateExitSlippageCost(const string symbol,
                                  const ENUM_SIGNAL_DIRECTION position_direction,
                                  const double expected_exit_price,
                                  const double executed_exit_price,
                                  const double volume,
                                  double &cost,
                                  double &slippage_points,
                                  string &error)
     {
      cost = 0.0;
      slippage_points = 0.0;
      error = "";

      if(expected_exit_price <= 0.0 || executed_exit_price <= 0.0 || volume <= 0.0)
        {
         error = "Dados invalidos para calcular slippage de saida.";
         return false;
        }

      const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
        {
         error = "SYMBOL_POINT invalido no slippage de saida.";
         return false;
        }

      const double adverse_distance =
         position_direction == SIGNAL_BUY
         ? expected_exit_price - executed_exit_price
         : executed_exit_price - expected_exit_price;

      slippage_points = adverse_distance / point;
      if(adverse_distance <= 0.0)
         return true;

      double profit = 0.0;
      ResetLastError();
      if(!OrderCalcProfit(
            MarketOrderType(position_direction),
            symbol,
            volume,
            expected_exit_price,
            executed_exit_price,
            profit
         ))
        {
         error = StringFormat(
            "OrderCalcProfit falhou no slippage de saida. erro=%d",
            GetLastError()
         );
         return false;
        }

      cost = MathAbs(profit);
      return MathIsValidNumber(cost);
     }

   bool CalculatePendingCostRiskPercent(const string symbol,
                                        const PreparedOrder &order,
                                        const double volume,
                                        const double current_spread_price,
                                        double &cost_risk_percent,
                                        double &estimated_cost,
                                        string &error)
     {
      cost_risk_percent = 0.0;
      estimated_cost = 0.0;
      error = "";

      double technical_loss_per_lot = 0.0;
      if(!CalculateTechnicalLossPerLot(
            symbol,
            order.direction,
            order.submitted_entry_price,
            order.submitted_stop_price,
            technical_loss_per_lot,
            error
         ))
         return false;

      CostEstimate cost = {};
      if(!EstimateRoundTripCosts(
            symbol,
            order.direction,
            order.submitted_entry_price,
            volume,
            current_spread_price,
            cost
         ))
        {
         error = cost.message;
         return false;
        }

      const double technical_loss = technical_loss_per_lot * volume;
      const double total_risk = technical_loss + cost.total;
      estimated_cost = cost.total;

      if(total_risk <= 0.0)
        {
         error = "Risco pendente invalido.";
         return false;
        }

      cost_risk_percent = cost.total / total_risk * 100.0;
      return true;
     }

   bool CalculateRealRisk(const string symbol,
                          const ENUM_SIGNAL_DIRECTION direction,
                          const double executed_price,
                          const double stop_price,
                          const double volume,
                          const double current_spread_price,
                          const double actual_slippage_cost,
                          const double planned_risk,
                          const double tolerance_percent,
                          RealRiskResult &result)
     {
      ZeroMemory(result);
      result.message = "";

      if(volume <= 0.0 || planned_risk <= 0.0)
        {
         result.message = "Volume ou risco planejado invalido no pos-fill.";
         return false;
        }

      double technical_loss_per_lot = 0.0;
      string technical_error = "";
      if(!CalculateTechnicalLossPerLot(
            symbol,
            direction,
            executed_price,
            stop_price,
            technical_loss_per_lot,
            technical_error
         ))
        {
         result.message = technical_error;
         return false;
        }

      result.technical_loss = technical_loss_per_lot * volume;

      CostEstimate cost = {};
      if(!EstimateRoundTripCosts(
            symbol,
            direction,
            executed_price,
            volume,
            current_spread_price,
            cost
         ))
        {
         result.message = cost.message;
         return false;
        }

      result.actual_slippage_cost = MathMax(0.0, actual_slippage_cost);

      // A reserva de slippage e substituida pelo custo real quando este for maior.
      const double effective_slippage = MathMax(
         cost.slippage_total,
         result.actual_slippage_cost
      );

      result.estimated_cost =
         cost.commission_total + cost.spread_total + effective_slippage;

      result.real_risk = result.technical_loss + result.estimated_cost;
      result.allowed_risk = planned_risk * (1.0 + tolerance_percent / 100.0);

      result.excess_percent =
         planned_risk > 0.0
         ? (result.real_risk / planned_risk - 1.0) * 100.0
         : 0.0;

      const double volume_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      const double safe_ratio =
         result.real_risk > 0.0
         ? MathMin(1.0, result.allowed_risk / result.real_risk)
         : 1.0;

      result.target_safe_volume = NormalizeVolumeDown(
         symbol,
         volume * safe_ratio
      );

      if(result.target_safe_volume < volume_min)
         result.target_safe_volume = 0.0;

      result.success = true;
      result.message = StringFormat(
         "Risco real=%.2f permitido=%.2f excesso=%.2f%% volume_seguro=%.8f",
         result.real_risk,
         result.allowed_risk,
         result.excess_percent,
         result.target_safe_volume
      );
      return true;
     }

   double MaxRoundTripCostRiskPercent(void)
     {
      return m_max_round_trip_cost_risk_percent;
     }
  };

#endif
