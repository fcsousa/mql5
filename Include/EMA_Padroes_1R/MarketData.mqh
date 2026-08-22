#ifndef EMA_PADROES_1R_MARKET_DATA_MQH
#define EMA_PADROES_1R_MARKET_DATA_MQH

#include <EMA_Padroes_1R/Types.mqh>

class CMarketData
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_ema_21_period;
   int             m_ema_40_period;
   int             m_ema_80_period;
   int             m_atr_period;
   int             m_required_history;
   bool            m_use_higher_tf_filter;
   ENUM_TIMEFRAMES m_higher_timeframe;

   int             m_ema_21_handle;
   int             m_ema_40_handle;
   int             m_ema_80_handle;
   int             m_atr_handle;
   int             m_ema_40_htf_handle;
   int             m_ema_80_htf_handle;

public:
   CMarketData(void)
     {
      m_symbol           = "";
      m_timeframe        = PERIOD_CURRENT;
      m_ema_21_period    = 0;
      m_ema_40_period    = 0;
      m_ema_80_period    = 0;
      m_atr_period       = 14;
      m_required_history = 0;
      m_use_higher_tf_filter = false;
      m_higher_timeframe = PERIOD_H1;
      m_ema_21_handle    = INVALID_HANDLE;
      m_ema_40_handle    = INVALID_HANDLE;
      m_ema_80_handle    = INVALID_HANDLE;
      m_atr_handle       = INVALID_HANDLE;
      m_ema_40_htf_handle = INVALID_HANDLE;
      m_ema_80_htf_handle = INVALID_HANDLE;
     }

   bool Initialize(const string symbol,
                   const ENUM_TIMEFRAMES timeframe,
                   const int ema_21_period,
                   const int ema_40_period,
                   const int ema_80_period,
                   const int atr_period,
                   const bool use_higher_tf_filter,
                   const ENUM_TIMEFRAMES higher_timeframe,
                   string &error)
     {
      Release();

      m_symbol        = symbol;
      m_timeframe     = timeframe;
      m_ema_21_period = ema_21_period;
      m_ema_40_period = ema_40_period;
      m_ema_80_period = ema_80_period;
      m_atr_period    = atr_period;
      m_use_higher_tf_filter = use_higher_tf_filter;
      m_higher_timeframe = higher_timeframe;

      int largest_period = m_ema_21_period;
      if(m_ema_40_period > largest_period)
         largest_period = m_ema_40_period;
      if(m_ema_80_period > largest_period)
         largest_period = m_ema_80_period;
      if(m_atr_period > largest_period)
         largest_period = m_atr_period;

      m_required_history = largest_period + 4;

      ResetLastError();
      m_ema_21_handle = iMA(
         m_symbol,
         m_timeframe,
         m_ema_21_period,
         0,
         MODE_EMA,
         PRICE_CLOSE
      );

      m_ema_40_handle = iMA(
         m_symbol,
         m_timeframe,
         m_ema_40_period,
         0,
         MODE_EMA,
         PRICE_CLOSE
      );

      m_ema_80_handle = iMA(
         m_symbol,
         m_timeframe,
         m_ema_80_period,
         0,
         MODE_EMA,
         PRICE_CLOSE
      );

      m_atr_handle = iATR(
         m_symbol,
         m_timeframe,
         m_atr_period
      );

      // Handles independentes do timeframe operacional. Sao criados
      // somente quando o filtro esta ativo para preservar compatibilidade
      // integral com a v4.3 quando InpUseHigherTFFilter=false.
      if(m_use_higher_tf_filter)
        {
         m_ema_40_htf_handle = iMA(
            m_symbol,
            m_higher_timeframe,
            m_ema_40_period,
            0,
            MODE_EMA,
            PRICE_CLOSE
         );

         m_ema_80_htf_handle = iMA(
            m_symbol,
            m_higher_timeframe,
            m_ema_80_period,
            0,
            MODE_EMA,
            PRICE_CLOSE
         );
        }

      if(m_ema_21_handle == INVALID_HANDLE ||
         m_ema_40_handle == INVALID_HANDLE ||
         m_ema_80_handle == INVALID_HANDLE ||
         m_atr_handle == INVALID_HANDLE ||
         (m_use_higher_tf_filter &&
          (m_ema_40_htf_handle == INVALID_HANDLE ||
           m_ema_80_htf_handle == INVALID_HANDLE)))
        {
         error = StringFormat(
            "Falha ao criar handles das EMAs/ATR (incluindo Higher TF quando ativo). erro=%d",
            GetLastError()
         );

         Release();
         return false;
        }

      error = "";
      return true;
     }

   bool LoadSnapshot(MarketSnapshot &snapshot, string &error)
     {
      const int required_values = 4;

      if(Bars(m_symbol, m_timeframe) < m_required_history)
        {
         error = "Historico insuficiente para calcular as EMAs.";
         return false;
        }

      if(BarsCalculated(m_ema_21_handle) < required_values ||
         BarsCalculated(m_ema_40_handle) < required_values ||
         BarsCalculated(m_ema_80_handle) < required_values ||
         BarsCalculated(m_atr_handle) < required_values)
        {
         error = "Buffers das EMAs ainda nao estao prontos.";
         return false;
        }

      MqlRates rates[];
      double ema_21[];
      double ema_40[];
      double ema_80[];
      double atr[];

      ArrayResize(rates, required_values);
      ArrayResize(ema_21, required_values);
      ArrayResize(ema_40, required_values);
      ArrayResize(ema_80, required_values);
      ArrayResize(atr, required_values);

      ArraySetAsSeries(rates, true);
      ArraySetAsSeries(ema_21, true);
      ArraySetAsSeries(ema_40, true);
      ArraySetAsSeries(ema_80, true);
      ArraySetAsSeries(atr, true);

      ResetLastError();

      const int copied_rates = CopyRates(
         m_symbol,
         m_timeframe,
         0,
         required_values,
         rates
      );

      if(copied_rates != required_values)
        {
         error = StringFormat(
            "CopyRates incompleto. esperado=%d recebido=%d erro=%d",
            required_values,
            copied_rates,
            GetLastError()
         );

         return false;
        }

      const int copied_21 = CopyBuffer(
         m_ema_21_handle,
         0,
         0,
         required_values,
         ema_21
      );

      const int copied_40 = CopyBuffer(
         m_ema_40_handle,
         0,
         0,
         required_values,
         ema_40
      );

      const int copied_80 = CopyBuffer(
         m_ema_80_handle,
         0,
         0,
         required_values,
         ema_80
      );

      const int copied_atr = CopyBuffer(
         m_atr_handle,
         0,
         0,
         required_values,
         atr
      );

      if(copied_21 != required_values ||
         copied_40 != required_values ||
         copied_80 != required_values ||
         copied_atr != required_values)
        {
         error = StringFormat(
            "CopyBuffer incompleto. EMA21=%d EMA40=%d EMA80=%d ATR=%d esperado=%d erro=%d",
            copied_21,
            copied_40,
            copied_80,
            copied_atr,
            required_values,
            GetLastError()
         );

         return false;
        }

      SpreadSnapshot spread = {};
      if(!LoadSpreadSnapshot(m_symbol, spread))
        {
         error = StringFormat(
            "Spread/tick indisponivel no snapshot. reason=%s erro=%u",
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
      if(tick_size <= 0.0)
         tick_size = point;

      if(tick_size <= 0.0 || point <= 0.0)
        {
         error = "Tick size ou point invalido para o simbolo.";
         return false;
        }

      snapshot.symbol          = m_symbol;
      snapshot.timeframe       = m_timeframe;
      snapshot.loaded_at       = TimeCurrent();
      snapshot.tick            = tick;
      snapshot.tick_size       = tick_size;
      snapshot.point           = point;
      snapshot.digits          = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      snapshot.current_bar     = rates[0];
      snapshot.signal_bar      = rates[1];
      snapshot.previous_bar    = rates[2];
      snapshot.context_bar     = rates[3];

      snapshot.ema_21_signal   = ema_21[1];
      snapshot.ema_21_previous = ema_21[2];
      snapshot.ema_40_signal   = ema_40[1];
      snapshot.ema_80_signal   = ema_80[1];
      snapshot.ema_80_previous = ema_80[2];
      snapshot.atr_signal      = atr[1];

      if(snapshot.atr_signal <= 0.0 || !MathIsValidNumber(snapshot.atr_signal))
        {
         error = "ATR invalido no candle de sinal.";
         return false;
        }

      error = "";
      return true;
     }

   // Carrega somente EMA40[1 + lookback] para o filtro de regime.
   // O EMA40[1] e o ATR[1] permanecem vindos do MarketSnapshot, garantindo
   // uso exclusivo de candles fechados e sem alterar o snapshot da v4.2.
   bool LoadEMA40PastValue(const int lookback,
                           double &ema_40_past,
                           string &error)
     {
      ema_40_past = 0.0;

      if(lookback <= 0)
        {
         error = "Lookback da inclinacao EMA40 deve ser maior que zero.";
         return false;
        }

      const int past_shift = 1 + lookback;
      const int required_bars = m_ema_40_period + past_shift + 1;

      if(Bars(m_symbol, m_timeframe) < required_bars)
        {
         error = StringFormat(
            "Historico insuficiente para EMA40 slope. lookback=%d shift=%d",
            lookback,
            past_shift
         );
         return false;
        }

      if(BarsCalculated(m_ema_40_handle) <= past_shift)
        {
         error = StringFormat(
            "Buffer EMA40 insuficiente para slope. lookback=%d shift=%d calculado=%d",
            lookback,
            past_shift,
            BarsCalculated(m_ema_40_handle)
         );
         return false;
        }

      double ema_past_buffer[1];
      ResetLastError();

      const int copied = CopyBuffer(
         m_ema_40_handle,
         0,
         past_shift,
         1,
         ema_past_buffer
      );

      if(copied != 1)
        {
         error = StringFormat(
            "CopyBuffer EMA40 slope falhou. lookback=%d shift=%d recebido=%d erro=%d",
            lookback,
            past_shift,
            copied,
            GetLastError()
         );
         return false;
        }

      ema_40_past = ema_past_buffer[0];
      if(!MathIsValidNumber(ema_40_past))
        {
         error = StringFormat(
            "EMA40 passada invalida para slope. lookback=%d shift=%d",
            lookback,
            past_shift
         );
         return false;
        }

      error = "";
      return true;
     }

   bool LoadHigherTFEMAValues(double &ema_40_htf,
                              double &ema_80_htf,
                              string &error)
     {
      ema_40_htf = 0.0;
      ema_80_htf = 0.0;

      if(!m_use_higher_tf_filter)
        {
         error = "Filtro Higher TF desativado.";
         return false;
        }

      if(m_ema_40_htf_handle == INVALID_HANDLE ||
         m_ema_80_htf_handle == INVALID_HANDLE)
        {
         error = "Handles EMA40/EMA80 Higher TF invalidos.";
         return false;
        }

      const int required_bars = m_ema_80_period + 2;
      if(Bars(m_symbol, m_higher_timeframe) < required_bars)
        {
         error = StringFormat(
            "Historico insuficiente no Higher TF. tf=%s necessario=%d disponivel=%d",
            EnumToString(m_higher_timeframe),
            required_bars,
            Bars(m_symbol, m_higher_timeframe)
         );
         return false;
        }

      if(BarsCalculated(m_ema_40_htf_handle) < 2 ||
         BarsCalculated(m_ema_80_htf_handle) < 2)
        {
         error = StringFormat(
            "Buffers Higher TF insuficientes. tf=%s EMA40=%d EMA80=%d",
            EnumToString(m_higher_timeframe),
            BarsCalculated(m_ema_40_htf_handle),
            BarsCalculated(m_ema_80_htf_handle)
         );
         return false;
        }

      double ema_40_buffer[1];
      double ema_80_buffer[1];
      ResetLastError();

      // start_pos=1: exclusivamente o ultimo candle FECHADO do Higher TF.
      const int copied_40 = CopyBuffer(
         m_ema_40_htf_handle,
         0,
         1,
         1,
         ema_40_buffer
      );

      const int copied_80 = CopyBuffer(
         m_ema_80_htf_handle,
         0,
         1,
         1,
         ema_80_buffer
      );

      if(copied_40 != 1 || copied_80 != 1)
        {
         error = StringFormat(
            "CopyBuffer Higher TF falhou. tf=%s EMA40=%d EMA80=%d erro=%d",
            EnumToString(m_higher_timeframe),
            copied_40,
            copied_80,
            GetLastError()
         );
         return false;
        }

      ema_40_htf = ema_40_buffer[0];
      ema_80_htf = ema_80_buffer[0];

      if(!MathIsValidNumber(ema_40_htf) ||
         !MathIsValidNumber(ema_80_htf))
        {
         error = StringFormat(
            "EMA Higher TF invalida. tf=%s",
            EnumToString(m_higher_timeframe)
         );
         return false;
        }

      error = "";
      return true;
     }

   void Release(void)
     {
      if(m_ema_21_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_ema_21_handle);
         m_ema_21_handle = INVALID_HANDLE;
        }

      if(m_ema_40_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_ema_40_handle);
         m_ema_40_handle = INVALID_HANDLE;
        }

      if(m_ema_80_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_ema_80_handle);
         m_ema_80_handle = INVALID_HANDLE;
        }

      if(m_atr_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_atr_handle);
         m_atr_handle = INVALID_HANDLE;
        }

      if(m_ema_40_htf_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_ema_40_htf_handle);
         m_ema_40_htf_handle = INVALID_HANDLE;
        }

      if(m_ema_80_htf_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_ema_80_htf_handle);
         m_ema_80_htf_handle = INVALID_HANDLE;
        }
     }
  };

#endif
