#ifndef EMA_PADROES_1R_STRATEGY_MQH
#define EMA_PADROES_1R_STRATEGY_MQH

#include <EMA_Padroes_1R/Types.mqh>

// Strategy contem apenas regras tecnicas. Nao consulta margem e nao envia ordens.
class CStrategy
  {
private:
   bool                   m_use_ema21_trap;
   bool                   m_use_ema80_trap;
   bool                   m_use_123;
   bool                   m_use_pfr;
   bool                   m_use_engulfing;
   ENUM_EA_PATTERN        m_priority_1;
   ENUM_EA_PATTERN        m_priority_2;
   ENUM_EA_PATTERN        m_priority_3;
   ENUM_EA_DIRECTION_MODE m_direction_mode;
   double                 m_target_r;
   double                 m_risk_percent;

   bool IsBuy123(const MarketSnapshot &snapshot)
     {
      return(
         snapshot.previous_bar.low < snapshot.context_bar.low &&
         snapshot.previous_bar.low < snapshot.signal_bar.low &&
         snapshot.signal_bar.close > snapshot.previous_bar.high
      );
     }

   bool IsSell123(const MarketSnapshot &snapshot)
     {
      return(
         snapshot.previous_bar.high > snapshot.context_bar.high &&
         snapshot.previous_bar.high > snapshot.signal_bar.high &&
         snapshot.signal_bar.close < snapshot.previous_bar.low
      );
     }

   bool IsBuyPfr(const MarketSnapshot &snapshot)
     {
      return(
         snapshot.previous_bar.low < snapshot.context_bar.low &&
         snapshot.signal_bar.low < snapshot.previous_bar.low &&
         snapshot.signal_bar.close > snapshot.previous_bar.low
      );
     }

   bool IsSellPfr(const MarketSnapshot &snapshot)
     {
      return(
         snapshot.previous_bar.high > snapshot.context_bar.high &&
         snapshot.signal_bar.high > snapshot.previous_bar.high &&
         snapshot.signal_bar.close < snapshot.previous_bar.high
      );
     }

   bool IsBuyEngulfing(const MarketSnapshot &snapshot)
     {
      const bool previous_bearish =
         snapshot.previous_bar.close < snapshot.previous_bar.open;

      const bool signal_bullish =
         snapshot.signal_bar.close > snapshot.signal_bar.open;

      const bool body_engulfed =
         snapshot.signal_bar.open <= snapshot.previous_bar.close &&
         snapshot.signal_bar.close >= snapshot.previous_bar.open;

      const bool full_range_engulfed =
         snapshot.signal_bar.low <= snapshot.previous_bar.low &&
         snapshot.signal_bar.high >= snapshot.previous_bar.high;

      return(
         previous_bearish &&
         signal_bullish &&
         body_engulfed &&
         full_range_engulfed
      );
     }

   bool IsSellEngulfing(const MarketSnapshot &snapshot)
     {
      const bool previous_bullish =
         snapshot.previous_bar.close > snapshot.previous_bar.open;

      const bool signal_bearish =
         snapshot.signal_bar.close < snapshot.signal_bar.open;

      const bool body_engulfed =
         snapshot.signal_bar.open >= snapshot.previous_bar.close &&
         snapshot.signal_bar.close <= snapshot.previous_bar.open;

      const bool full_range_engulfed =
         snapshot.signal_bar.low <= snapshot.previous_bar.low &&
         snapshot.signal_bar.high >= snapshot.previous_bar.high;

      return(
         previous_bullish &&
         signal_bearish &&
         body_engulfed &&
         full_range_engulfed
      );
     }

   bool IsPatternMatched(const PatternResult &detected,
                         const ENUM_EA_PATTERN pattern)
     {
      switch(pattern)
        {
         case EA_PATTERN_123:
            return detected.pattern_123;

         case EA_PATTERN_PFR:
            return detected.pfr;

         case EA_PATTERN_ENGULFING:
            return detected.engulfing;

         default:
            return false;
        }
     }

   void SelectPattern(const ENUM_EA_PATTERN pattern,
                      PatternResult &selected)
     {
      selected.pattern_123      = false;
      selected.pfr              = false;
      selected.engulfing        = false;
      selected.selected_pattern = pattern;

      switch(pattern)
        {
         case EA_PATTERN_123:
            selected.pattern_123 = true;
            selected.formation_bars = 3;
            selected.name = "123";
            break;

         case EA_PATTERN_PFR:
            selected.pfr = true;
            selected.formation_bars = 3;
            selected.name = "PFR";
            break;

         case EA_PATTERN_ENGULFING:
            selected.engulfing = true;
            selected.formation_bars = 2;
            selected.name = "ENG";
            break;
        }
     }

   PatternResult ApplyPriority(const PatternResult &detected)
     {
      PatternResult selected = {};
      selected.name = "";

      if(IsPatternMatched(detected, m_priority_1))
        {
         SelectPattern(m_priority_1, selected);
         return selected;
        }

      if(IsPatternMatched(detected, m_priority_2))
        {
         SelectPattern(m_priority_2, selected);
         return selected;
        }

      if(IsPatternMatched(detected, m_priority_3))
         SelectPattern(m_priority_3, selected);

      return selected;
     }

   PatternResult DetectBuyPatterns(const MarketSnapshot &snapshot)
     {
      PatternResult detected = {};
      detected.pattern_123 = m_use_123 && IsBuy123(snapshot);
      detected.pfr         = m_use_pfr && IsBuyPfr(snapshot);
      detected.engulfing   = m_use_engulfing && IsBuyEngulfing(snapshot);
      return ApplyPriority(detected);
     }

   PatternResult DetectSellPatterns(const MarketSnapshot &snapshot)
     {
      PatternResult detected = {};
      detected.pattern_123 = m_use_123 && IsSell123(snapshot);
      detected.pfr         = m_use_pfr && IsSellPfr(snapshot);
      detected.engulfing   = m_use_engulfing && IsSellEngulfing(snapshot);
      return ApplyPriority(detected);
     }

   bool HasPattern(const PatternResult &patterns)
     {
      return patterns.name != "";
     }

   bool BuyDirectionEnabled(void)
     {
      return(
         m_direction_mode == EA_DIRECTION_BOTH ||
         m_direction_mode == EA_DIRECTION_BUY_ONLY
      );
     }

   bool SellDirectionEnabled(void)
     {
      return(
         m_direction_mode == EA_DIRECTION_BOTH ||
         m_direction_mode == EA_DIRECTION_SELL_ONLY
      );
     }

   double BuyFormationLow(const MarketSnapshot &snapshot,
                          const int formation_bars)
     {
      double formation_low = MathMin(
         snapshot.signal_bar.low,
         snapshot.previous_bar.low
      );

      if(formation_bars == 3)
         formation_low = MathMin(formation_low, snapshot.context_bar.low);

      return formation_low;
     }

   double SellFormationHigh(const MarketSnapshot &snapshot,
                            const int formation_bars)
     {
      double formation_high = MathMax(
         snapshot.signal_bar.high,
         snapshot.previous_bar.high
      );

      if(formation_bars == 3)
         formation_high = MathMax(formation_high, snapshot.context_bar.high);

      return formation_high;
     }

   string BuildSignalId(const string direction,
                        const string pattern_name,
                        const string entry_trap_name,
                        const datetime signal_time)
     {
      // Mantem exatamente o formato historico para Trap EMA21, garantindo
      // compatibilidade de signal_id com a v4.4 quando EMA80 esta desativada.
      const string prefix = entry_trap_name == "EMA80" ? "E1R80" : "E1R";

      string signal_id = StringFormat(
         "%s|%s|%s|%I64d",
         prefix,
         direction,
         pattern_name,
         (long)signal_time
      );

      if(StringLen(signal_id) > 31)
         signal_id = StringSubstr(signal_id, 0, 31);

      return signal_id;
     }

   void FillTechnicalSignal(const PatternResult &patterns,
                            const ENUM_SIGNAL_DIRECTION direction,
                            const string entry_trap_name,
                            const datetime signal_time,
                            TechnicalSignal &signal)
     {
      signal.pattern_name    = patterns.name;
      signal.entry_trap_name = entry_trap_name;
      signal.signal_time     = signal_time;
      signal.direction       = direction;
      signal.formation_bars  = patterns.formation_bars;

      signal.signal_id = BuildSignalId(
         direction == SIGNAL_BUY ? "B" : "S",
         patterns.name,
         entry_trap_name,
         signal_time
      );
     }

   bool BuildBuyPlan(const MarketSnapshot &snapshot,
                     const TechnicalSignal &signal,
                     TradePlan &plan,
                     string &error)
     {
      const double entry =
         snapshot.signal_bar.high + snapshot.tick_size;

      const double stop = BuyFormationLow(
         snapshot,
         signal.formation_bars
      );

      const double risk_distance = entry - stop;
      if(risk_distance <= 0.0)
        {
         error = "Distancia tecnica de risco da compra invalida.";
         return false;
        }

      plan.signal_id              = signal.signal_id;
      plan.pattern_name           = signal.pattern_name;
      plan.signal_time            = signal.signal_time;
      plan.direction              = SIGNAL_BUY;
      plan.order_type             = ORDER_TYPE_BUY_STOP;
      plan.technical_entry_price  = entry;
      plan.technical_stop_price   = stop;
      plan.technical_target_price = entry + risk_distance * m_target_r;
      plan.target_r               = m_target_r;
      plan.risk_percent           = m_risk_percent;
      plan.atr_value              = snapshot.atr_signal;
      plan.signal_spread_price    = snapshot.tick.ask - snapshot.tick.bid;
      plan.signal_spread_points   = plan.signal_spread_price / snapshot.point;
      plan.expiration             = snapshot.current_bar.time +
                                    PeriodSeconds(snapshot.timeframe);

      error = "";
      return true;
     }

   bool BuildSellPlan(const MarketSnapshot &snapshot,
                      const TechnicalSignal &signal,
                      TradePlan &plan,
                      string &error)
     {
      const double entry =
         snapshot.signal_bar.low - snapshot.tick_size;

      const double stop = SellFormationHigh(
         snapshot,
         signal.formation_bars
      );

      const double risk_distance = stop - entry;
      if(risk_distance <= 0.0)
        {
         error = "Distancia tecnica de risco da venda invalida.";
         return false;
        }

      plan.signal_id              = signal.signal_id;
      plan.pattern_name           = signal.pattern_name;
      plan.signal_time            = signal.signal_time;
      plan.direction              = SIGNAL_SELL;
      plan.order_type             = ORDER_TYPE_SELL_STOP;
      plan.technical_entry_price  = entry;
      plan.technical_stop_price   = stop;
      plan.technical_target_price = entry - risk_distance * m_target_r;
      plan.target_r               = m_target_r;
      plan.risk_percent           = m_risk_percent;
      plan.atr_value              = snapshot.atr_signal;
      plan.signal_spread_price    = snapshot.tick.ask - snapshot.tick.bid;
      plan.signal_spread_points   = plan.signal_spread_price / snapshot.point;
      plan.expiration             = snapshot.current_bar.time +
                                    PeriodSeconds(snapshot.timeframe);

      error = "";
      return true;
     }

public:
   CStrategy(void)
     {
      m_use_ema21_trap = true;
      m_use_ema80_trap = false;
      m_use_123        = true;
      m_use_pfr        = true;
      m_use_engulfing  = true;
      m_priority_1     = EA_PATTERN_123;
      m_priority_2     = EA_PATTERN_PFR;
      m_priority_3     = EA_PATTERN_ENGULFING;
      m_direction_mode = EA_DIRECTION_BOTH;
      m_target_r       = 1.0;
      m_risk_percent   = 1.0;
     }

   void Configure(const bool use_ema21_trap,
                  const bool use_ema80_trap,
                  const bool use_123,
                  const bool use_pfr,
                  const bool use_engulfing,
                  const ENUM_EA_PATTERN priority_1,
                  const ENUM_EA_PATTERN priority_2,
                  const ENUM_EA_PATTERN priority_3,
                  const ENUM_EA_DIRECTION_MODE direction_mode,
                  const double target_r,
                  const double risk_percent)
     {
      m_use_ema21_trap = use_ema21_trap;
      m_use_ema80_trap = use_ema80_trap;
      m_use_123        = use_123;
      m_use_pfr        = use_pfr;
      m_use_engulfing  = use_engulfing;
      m_priority_1     = priority_1;
      m_priority_2     = priority_2;
      m_priority_3     = priority_3;
      m_direction_mode = direction_mode;
      m_target_r       = target_r;
      m_risk_percent   = risk_percent;
     }

   // Detecta somente o sinal tecnico. A v4.5 suporta dois contextos de
   // entrada: Trap EMA21 (regra historica) e Trap EMA80 (nova). Quando os
   // dois sao validos no mesmo candle, EMA80 tem prioridade obrigatoria.
   // Nao calcula entry/stop/target.
   bool DetectSignal(const MarketSnapshot &snapshot,
                     TechnicalSignal &signal,
                     string &error)
     {
      const bool is_bullish_context =
         snapshot.ema_40_signal > snapshot.ema_80_signal;

      const bool is_bearish_context =
         snapshot.ema_40_signal < snapshot.ema_80_signal;

      // Trap EMA21: preserva exatamente a regra existente da v4.4.
      const bool has_buy_ema21_trap =
         m_use_ema21_trap &&
         snapshot.previous_bar.close < snapshot.ema_21_previous &&
         snapshot.signal_bar.close > snapshot.ema_21_signal;

      const bool has_sell_ema21_trap =
         m_use_ema21_trap &&
         snapshot.previous_bar.close > snapshot.ema_21_previous &&
         snapshot.signal_bar.close < snapshot.ema_21_signal;

      // Trap EMA80: compara o fechamento do penultimo candle [2] com a
      // EMA80 do mesmo candle [2]. Nao exige cruzamento/fechamento do candle
      // [1] do outro lado da EMA80; a confirmacao continua sendo o padrao.
      const bool has_buy_ema80_trap =
         m_use_ema80_trap &&
         snapshot.previous_bar.close < snapshot.ema_80_previous;

      const bool has_sell_ema80_trap =
         m_use_ema80_trap &&
         snapshot.previous_bar.close > snapshot.ema_80_previous;

      const PatternResult buy_patterns = DetectBuyPatterns(snapshot);
      const PatternResult sell_patterns = DetectSellPatterns(snapshot);

      const bool has_buy_ema80_signal =
         BuyDirectionEnabled() &&
         is_bullish_context &&
         has_buy_ema80_trap &&
         HasPattern(buy_patterns);

      const bool has_sell_ema80_signal =
         SellDirectionEnabled() &&
         is_bearish_context &&
         has_sell_ema80_trap &&
         HasPattern(sell_patterns);

      const bool has_buy_ema21_signal =
         BuyDirectionEnabled() &&
         is_bullish_context &&
         has_buy_ema21_trap &&
         HasPattern(buy_patterns);

      const bool has_sell_ema21_signal =
         SellDirectionEnabled() &&
         is_bearish_context &&
         has_sell_ema21_trap &&
         HasPattern(sell_patterns);

      // Prioridade estrutural: Trap EMA80 sempre vence Trap EMA21.
      if(has_buy_ema80_signal)
        {
         FillTechnicalSignal(
            buy_patterns,
            SIGNAL_BUY,
            "EMA80",
            snapshot.signal_bar.time,
            signal
         );
         error = "";
         return true;
        }

      if(has_sell_ema80_signal)
        {
         FillTechnicalSignal(
            sell_patterns,
            SIGNAL_SELL,
            "EMA80",
            snapshot.signal_bar.time,
            signal
         );
         error = "";
         return true;
        }

      if(has_buy_ema21_signal)
        {
         FillTechnicalSignal(
            buy_patterns,
            SIGNAL_BUY,
            "EMA21",
            snapshot.signal_bar.time,
            signal
         );
         error = "";
         return true;
        }

      if(has_sell_ema21_signal)
        {
         FillTechnicalSignal(
            sell_patterns,
            SIGNAL_SELL,
            "EMA21",
            snapshot.signal_bar.time,
            signal
         );
         error = "";
         return true;
        }

      error = "";
      return false;
     }

   // Construcao do TradePlan permanece identica a v4.2 e ocorre somente
   // depois que o chamador aprovou eventuais filtros entre sinal e plano.
   bool BuildTradePlan(const MarketSnapshot &snapshot,
                       const TechnicalSignal &signal,
                       TradePlan &plan,
                       string &error)
     {
      if(signal.direction == SIGNAL_BUY)
         return BuildBuyPlan(snapshot, signal, plan, error);

      if(signal.direction == SIGNAL_SELL)
         return BuildSellPlan(snapshot, signal, plan, error);

      error = "Direcao invalida ao construir TradePlan.";
      return false;
     }

   // Wrapper mantido para compatibilidade. O fluxo principal usa
   // DetectSignal() -> slope -> Higher TF -> BuildTradePlan().
   bool Evaluate(const MarketSnapshot &snapshot,
                 TradePlan &plan,
                 string &error)
     {
      TechnicalSignal signal = {};

      if(!DetectSignal(snapshot, signal, error))
         return false;

      return BuildTradePlan(snapshot, signal, plan, error);
     }
  };

#endif
