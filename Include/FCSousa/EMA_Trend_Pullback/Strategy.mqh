#ifndef __EMA_TREND_PULLBACK_STRATEGY_MQH__
#define __EMA_TREND_PULLBACK_STRATEGY_MQH__

#include <FCSousa/EMA_Trend_Pullback/Types.mqh>

class CStrategy
{
private:
   bool m_use_pb21;
   bool m_use_pb40;
   bool m_use_engulfing;
   bool m_use_123;
   bool m_use_pfr;

   double m_tolerance_atr;
   int m_entry_buffer_ticks;
   int m_pending_expiration_bars;
   double m_target_r;
   double m_risk_percent;
   ENUM_EA_DIRECTION_MODE m_direction_mode;

   bool DirectionAllowed(const ENUM_SIGNAL_DIRECTION direction) const
   {
      if(m_direction_mode == EA_DIRECTION_BOTH)
         return true;

      if(m_direction_mode == EA_DIRECTION_BUY)
         return direction == SIGNAL_BUY;

      if(m_direction_mode == EA_DIRECTION_SELL)
         return direction == SIGNAL_SELL;

      return false;
   }

   bool BullishRegime(const MarketSnapshot &s) const
   {
      return s.ema40_1 > s.ema80_1;
   }

   bool BearishRegime(const MarketSnapshot &s) const
   {
      return s.ema40_1 < s.ema80_1;
   }

   bool BuyPullback(const MarketSnapshot &s, const double ema) const
   {
      const double tolerance = s.atr_1 * m_tolerance_atr;
      return s.rates[1].low <= ema + tolerance;
   }

   bool SellPullback(const MarketSnapshot &s, const double ema) const
   {
      const double tolerance = s.atr_1 * m_tolerance_atr;
      return s.rates[1].high >= ema - tolerance;
   }

   bool BullishEngulfing(const MarketSnapshot &s) const
   {
      return
         s.rates[1].close > s.rates[1].open &&
         s.rates[1].open  <= s.rates[2].close &&
         s.rates[1].close >= s.rates[2].open;
   }

   bool BearishEngulfing(const MarketSnapshot &s) const
   {
      return
         s.rates[1].close < s.rates[1].open &&
         s.rates[1].open  >= s.rates[2].close &&
         s.rates[1].close <= s.rates[2].open;
   }

   // 123 objetivo:
   // BUY = minima [2] abaixo de [3], minima [1] acima de [2] e
   //       fechamento [1] acima da maxima [2].
   // SELL = inverso.
   bool Bullish123(const MarketSnapshot &s) const
   {
      return
         s.rates[2].low < s.rates[3].low &&
         s.rates[1].low > s.rates[2].low &&
         s.rates[1].close > s.rates[2].high;
   }

   bool Bearish123(const MarketSnapshot &s) const
   {
      return
         s.rates[2].high > s.rates[3].high &&
         s.rates[1].high < s.rates[2].high &&
         s.rates[1].close < s.rates[2].low;
   }

   bool BuildSignal(const MarketSnapshot &s,
                    const string setup_name,
                    const string pattern_name,
                    const ENUM_SIGNAL_DIRECTION direction,
                    TechnicalSignal &signal) const
   {
      if(!DirectionAllowed(direction))
         return false;

      signal.valid = true;
      signal.setup_name = setup_name;
      signal.pattern_name = pattern_name;
      signal.signal_time = s.signal_time;
      signal.direction = direction;

      const string direction_text =
         direction == SIGNAL_BUY ? "BUY" : "SELL";

      signal.signal_id = StringFormat(
         "%s|%s|%s|%s|%s|%s",
         setup_name,
         pattern_name,
         _Symbol,
         EnumToString((ENUM_TIMEFRAMES)_Period),
         TimeToString(s.signal_time, TIME_DATE|TIME_MINUTES),
         direction_text
      );

      if(direction == SIGNAL_BUY)
      {
         signal.technical_entry_price =
            s.rates[1].high + m_entry_buffer_ticks * s.tick_size;

         if(pattern_name == "ENG")
            signal.technical_stop_price =
               MathMin(s.rates[1].low, s.rates[2].low);
         else
            signal.technical_stop_price =
               MathMin(s.rates[1].low, s.rates[2].low);
      }
      else
      {
         signal.technical_entry_price =
            s.rates[1].low - m_entry_buffer_ticks * s.tick_size;

         if(pattern_name == "ENG")
            signal.technical_stop_price =
               MathMax(s.rates[1].high, s.rates[2].high);
         else
            signal.technical_stop_price =
               MathMax(s.rates[1].high, s.rates[2].high);
      }

      return true;
   }

public:
   CStrategy(void)
   {
      m_use_pb21 = true;
      m_use_pb40 = false;
      m_use_engulfing = true;
      m_use_123 = false;
      m_use_pfr = false;
      m_tolerance_atr = 0.10;
      m_entry_buffer_ticks = 1;
      m_pending_expiration_bars = 3;
      m_target_r = 1.50;
      m_risk_percent = 1.0;
      m_direction_mode = EA_DIRECTION_BOTH;
   }

   void Configure(const bool use_pb21,
                  const bool use_pb40,
                  const bool use_engulfing,
                  const bool use_123,
                  const bool use_pfr,
                  const double tolerance_atr,
                  const int entry_buffer_ticks,
                  const int pending_expiration_bars,
                  const double target_r,
                  const double risk_percent,
                  const ENUM_EA_DIRECTION_MODE direction_mode)
   {
      m_use_pb21 = use_pb21;
      m_use_pb40 = use_pb40;
      m_use_engulfing = use_engulfing;
      m_use_123 = use_123;
      m_use_pfr = use_pfr;
      m_tolerance_atr = tolerance_atr;
      m_entry_buffer_ticks = entry_buffer_ticks;
      m_pending_expiration_bars = pending_expiration_bars;
      m_target_r = target_r;
      m_risk_percent = risk_percent;
      m_direction_mode = direction_mode;
   }

   bool DetectSignal(const MarketSnapshot &s,
                     TechnicalSignal &signal,
                     string &error)
   {
      error = "";
      signal.valid = false;

      const bool bullish_regime = BullishRegime(s);
      const bool bearish_regime = BearishRegime(s);

      // Determinismo: PB21 tem prioridade se ambos estiverem ligados.
      if(m_use_pb21)
      {
         if(bullish_regime && BuyPullback(s, s.ema21_1))
         {
            if(m_use_engulfing && BullishEngulfing(s))
               return BuildSignal(s, "PB21", "ENG", SIGNAL_BUY, signal);

            if(m_use_123 && Bullish123(s))
               return BuildSignal(s, "PB21", "123", SIGNAL_BUY, signal);
         }

         if(bearish_regime && SellPullback(s, s.ema21_1))
         {
            if(m_use_engulfing && BearishEngulfing(s))
               return BuildSignal(s, "PB21", "ENG", SIGNAL_SELL, signal);

            if(m_use_123 && Bearish123(s))
               return BuildSignal(s, "PB21", "123", SIGNAL_SELL, signal);
         }
      }

      if(m_use_pb40)
      {
         if(bullish_regime && BuyPullback(s, s.ema40_1))
         {
            if(m_use_engulfing && BullishEngulfing(s))
               return BuildSignal(s, "PB40", "ENG", SIGNAL_BUY, signal);

            if(m_use_123 && Bullish123(s))
               return BuildSignal(s, "PB40", "123", SIGNAL_BUY, signal);
         }

         if(bearish_regime && SellPullback(s, s.ema40_1))
         {
            if(m_use_engulfing && BearishEngulfing(s))
               return BuildSignal(s, "PB40", "ENG", SIGNAL_SELL, signal);

            if(m_use_123 && Bearish123(s))
               return BuildSignal(s, "PB40", "123", SIGNAL_SELL, signal);
         }
      }

      return false;
   }

   bool BuildTradePlan(const MarketSnapshot &s,
                       const TechnicalSignal &signal,
                       TradePlan &plan,
                       string &error)
   {
      error = "";

      if(!signal.valid)
      {
         error = "TechnicalSignal invalido.";
         return false;
      }

      const int seconds_per_bar =
         PeriodSeconds((ENUM_TIMEFRAMES)_Period);

      if(seconds_per_bar <= 0)
      {
         error = "PeriodSeconds invalido.";
         return false;
      }

      plan.signal_id = signal.signal_id;
      plan.setup_name = signal.setup_name;
      plan.pattern_name = signal.pattern_name;
      plan.signal_time = signal.signal_time;
      plan.direction = signal.direction;
      plan.order_type =
         signal.direction == SIGNAL_BUY
         ? ORDER_TYPE_BUY_STOP
         : ORDER_TYPE_SELL_STOP;

      plan.technical_entry_price = signal.technical_entry_price;
      plan.technical_stop_price = signal.technical_stop_price;
      plan.target_r = m_target_r;
      plan.risk_percent = m_risk_percent;
      plan.signal_spread_points = s.spread_points;
      plan.atr_value = s.atr_1;

      // O primeiro candle apos o sinal comeca em rates[0].time.
      // N barras completas = rates[0].time + N * PeriodSeconds.
      plan.expiration =
         s.rates[0].time +
         (datetime)(m_pending_expiration_bars * seconds_per_bar);

      return true;
   }
};

#endif
