#ifndef FCSOUSA_EA123_MA_BUY_STRATEGY_MQH
#define FCSOUSA_EA123_MA_BUY_STRATEGY_MQH

#include <FCSousa/EA123_MA_Buy/Types.mqh>

class CBuy123Strategy
{
private:
   string                   m_symbol;
   ENUM_TIMEFRAMES          m_timeframe;
   int                      m_short_ma_handle;
   int                      m_long_ma_handle;
   double                   m_target_r;
   double                   m_risk_percent;
   ENUM_ORDER_VALIDITY_MODE m_validity_mode;

public:
   CBuy123Strategy(void)
   {
      m_symbol          = "";
      m_timeframe       = PERIOD_CURRENT;
      m_short_ma_handle = INVALID_HANDLE;
      m_long_ma_handle  = INVALID_HANDLE;
      m_target_r        = 1.0;
      m_risk_percent    = 1.0;
      m_validity_mode   = VALIDITY_ONE_CANDLE;
   }

   bool Initialize(
      const string symbol,
      const ENUM_TIMEFRAMES timeframe,
      const int short_period,
      const ENUM_MA_METHOD short_method,
      const int long_period,
      const ENUM_MA_METHOD long_method,
      const double target_r,
      const double risk_percent,
      const ENUM_ORDER_VALIDITY_MODE validity_mode,
      string &error
   )
   {
      error = "";

      m_symbol        = symbol;
      m_timeframe     = timeframe;
      m_target_r      = target_r;
      m_risk_percent  = risk_percent;
      m_validity_mode = validity_mode;

      m_short_ma_handle = iMA(
         m_symbol,
         m_timeframe,
         short_period,
         0,
         short_method,
         PRICE_CLOSE
      );

      if(m_short_ma_handle == INVALID_HANDLE)
      {
         error = StringFormat(
            "Falha ao criar MA curta. erro=%d",
            GetLastError()
         );
         return false;
      }

      m_long_ma_handle = iMA(
         m_symbol,
         m_timeframe,
         long_period,
         0,
         long_method,
         PRICE_CLOSE
      );

      if(m_long_ma_handle == INVALID_HANDLE)
      {
         error = StringFormat(
            "Falha ao criar MA longa. erro=%d",
            GetLastError()
         );

         IndicatorRelease(m_short_ma_handle);
         m_short_ma_handle = INVALID_HANDLE;
         return false;
      }

      return true;
   }

   void Release(void)
   {
      if(m_short_ma_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_short_ma_handle);
         m_short_ma_handle = INVALID_HANDLE;
      }

      if(m_long_ma_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_long_ma_handle);
         m_long_ma_handle = INVALID_HANDLE;
      }
   }

   bool Evaluate(TradePlan &plan, string &error)
   {
      error = "";
      ZeroMemory(plan);

      MqlRates rates[];
      double short_ma[];
      double long_ma[];

      ArraySetAsSeries(rates, true);
      ArraySetAsSeries(short_ma, true);
      ArraySetAsSeries(long_ma, true);

      ResetLastError();

      const int copied_rates = CopyRates(
         m_symbol,
         m_timeframe,
         0,
         4,
         rates
      );

      if(copied_rates != 4)
      {
         error = StringFormat(
            "CopyRates insuficiente. esperado=4 recebido=%d erro=%d",
            copied_rates,
            GetLastError()
         );
         return false;
      }

      const int copied_short = CopyBuffer(
         m_short_ma_handle,
         0,
         0,
         4,
         short_ma
      );

      if(copied_short != 4)
      {
         error = StringFormat(
            "CopyBuffer MA curta insuficiente. esperado=4 recebido=%d erro=%d",
            copied_short,
            GetLastError()
         );
         return false;
      }

      const int copied_long = CopyBuffer(
         m_long_ma_handle,
         0,
         0,
         4,
         long_ma
      );

      if(copied_long != 4)
      {
         error = StringFormat(
            "CopyBuffer MA longa insuficiente. esperado=4 recebido=%d erro=%d",
            copied_long,
            GetLastError()
         );
         return false;
      }

      const bool has_buy_123 =
         rates[3].low > rates[2].low &&
         rates[1].low > rates[2].low;

      const bool is_bullish_trend =
         short_ma[1] > long_ma[1];

      if(!has_buy_123 || !is_bullish_trend)
         return false;

      const double tick_size = GetTradeTickSize(m_symbol);

      if(tick_size <= 0.0)
      {
         error = "SYMBOL_TRADE_TICK_SIZE inválido.";
         return false;
      }

      const double technical_entry =
         rates[1].high + tick_size;

      const double entry_price =
         NormalizePriceUp(m_symbol, technical_entry);

      const double stop_price =
         NormalizePriceDown(m_symbol, rates[2].low);

      if(entry_price <= 0.0 || stop_price <= 0.0)
      {
         error = "Falha na normalização de entrada/stop.";
         return false;
      }

      if(stop_price >= entry_price)
      {
         error = StringFormat(
            "Setup inválido: stop >= entrada. entry=%.*f stop=%.*f",
            (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS),
            entry_price,
            (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS),
            stop_price
         );
         return false;
      }

      const double one_r =
         entry_price - stop_price;

      const double raw_target =
         entry_price + (one_r * m_target_r);

      const double target_price =
         NormalizePriceDown(m_symbol, raw_target);

      if(target_price <= entry_price)
      {
         error = "Alvo inválido após normalização.";
         return false;
      }

      const int period_seconds =
         PeriodSeconds(m_timeframe);

      if(period_seconds <= 0)
      {
         error = "PeriodSeconds retornou valor inválido.";
         return false;
      }

      plan.signal_id =
         "123B|" + IntegerToString((long)rates[1].time);

      plan.signal_time         = rates[1].time;
      plan.direction           = SIGNAL_BUY;
      plan.order_type          = ORDER_TYPE_BUY_STOP;
      plan.validity_mode       = m_validity_mode;
      plan.entry_price         = entry_price;
      plan.stop_price          = stop_price;
      plan.target_price        = target_price;
      plan.risk_percent        = m_risk_percent;
      plan.expiration_bar_time =
         rates[0].time + period_seconds;

      return true;
   }
};

#endif
