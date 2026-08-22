#ifndef __EMA_TREND_PULLBACK_RISK_MANAGER_MQH__
#define __EMA_TREND_PULLBACK_RISK_MANAGER_MQH__

#include <EMA_Trend_Pullback/Types.mqh>

class CRiskManager
{
private:
   double m_max_cost_risk_percent;
   double m_max_volume_lots;
   double m_round_trip_commission_per_lot;
   double m_round_trip_slippage_points;

   double NormalizeVolumeDown(const string symbol, const double volume) const
   {
      const double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      const double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      const double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(step <= 0.0 || min_volume <= 0.0 || max_volume <= 0.0)
         return 0.0;

      double normalized = MathFloor(volume / step + 1e-12) * step;
      normalized = MathMin(normalized, max_volume);

      if(m_max_volume_lots > 0.0)
         normalized = MathMin(normalized, m_max_volume_lots);

      if(normalized + 1e-12 < min_volume)
         return 0.0;

      return normalized;
   }

public:
   CRiskManager(void)
   {
      m_max_cost_risk_percent = 10.0;
      m_max_volume_lots = 10.0;
      m_round_trip_commission_per_lot = 0.0;
      m_round_trip_slippage_points = 2.0;
   }

   void Configure(const double max_cost_risk_percent,
                  const double max_volume_lots,
                  const double commission_per_lot,
                  const double slippage_points)
   {
      m_max_cost_risk_percent = max_cost_risk_percent;
      m_max_volume_lots = max_volume_lots;
      m_round_trip_commission_per_lot = commission_per_lot;
      m_round_trip_slippage_points = slippage_points;
   }

   bool Calculate(const string symbol,
                  const TradePlan &plan,
                  const double current_spread_points,
                  RiskResult &result)
   {
      result.success = false;
      result.message = "";

      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance <= 0.0)
      {
         result.message = "Saldo invalido.";
         return false;
      }

      const double planned_risk =
         balance * plan.risk_percent / 100.0;

      if(planned_risk <= 0.0)
      {
         result.message = "Risco financeiro invalido.";
         return false;
      }

      const ENUM_ORDER_TYPE market_type =
         plan.direction == SIGNAL_BUY
         ? ORDER_TYPE_BUY
         : ORDER_TYPE_SELL;

      double loss_one_lot = 0.0;
      if(!OrderCalcProfit(
            market_type,
            symbol,
            1.0,
            plan.technical_entry_price,
            plan.technical_stop_price,
            loss_one_lot))
      {
         result.message =
            StringFormat("OrderCalcProfit falhou. erro=%d", GetLastError());
         return false;
      }

      loss_one_lot = MathAbs(loss_one_lot);
      if(loss_one_lot <= 0.0)
      {
         result.message = "Perda por lote invalida.";
         return false;
      }

      const double raw_volume = planned_risk / loss_one_lot;
      const double volume = NormalizeVolumeDown(symbol, raw_volume);

      if(volume <= 0.0)
      {
         result.message =
            "Volume calculado abaixo do minimo ou invalido.";
         return false;
      }

      const double tick_value_loss =
         SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      const double tick_size =
         SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      const double point =
         SymbolInfoDouble(symbol, SYMBOL_POINT);

      if(tick_size <= 0.0 || point <= 0.0)
      {
         result.message = "Tick size/point invalido.";
         return false;
      }

      double spread_cost_per_lot = 0.0;
      double slippage_cost_per_lot = 0.0;

      if(tick_value_loss > 0.0)
      {
         const double spread_price =
            current_spread_points * point;

         const double slippage_price =
            m_round_trip_slippage_points * point;

         spread_cost_per_lot =
            (spread_price / tick_size) * tick_value_loss;

         slippage_cost_per_lot =
            (slippage_price / tick_size) * tick_value_loss;
      }

      const double estimated_cost =
         volume *
         (m_round_trip_commission_per_lot +
          spread_cost_per_lot +
          slippage_cost_per_lot);

      const double technical_risk_money =
         loss_one_lot * volume;

      const double cost_risk_percent =
         technical_risk_money > 0.0
         ? estimated_cost / technical_risk_money * 100.0
         : 1.0e100;

      if(m_max_cost_risk_percent > 0.0 &&
         cost_risk_percent > m_max_cost_risk_percent + 1e-9)
      {
         result.message =
            StringFormat("Custo round trip %.2f%% > max %.2f%%",
                         cost_risk_percent,
                         m_max_cost_risk_percent);
         return false;
      }

      const double risk_distance =
         MathAbs(plan.technical_entry_price -
                 plan.technical_stop_price);

      if(risk_distance <= 0.0)
      {
         result.message = "Distancia de risco invalida.";
         return false;
      }

      const double gross_target_distance =
         risk_distance * plan.target_r;

      double target_price = 0.0;

      if(plan.direction == SIGNAL_BUY)
         target_price =
            plan.technical_entry_price + gross_target_distance;
      else
         target_price =
            plan.technical_entry_price - gross_target_distance;

      result.success = true;
      result.volume = volume;
      result.planned_risk_money = technical_risk_money;
      result.loss_per_lot = loss_one_lot;
      result.estimated_round_trip_cost = estimated_cost;
      result.round_trip_cost_risk_percent = cost_risk_percent;
      result.target_price = target_price;
      result.message = "OK";
      return true;
   }
};

#endif
