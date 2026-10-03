#ifndef EMA6_SMA40_PATTERN_MARKET_DATA_MQH
#define EMA6_SMA40_PATTERN_MARKET_DATA_MQH

#include <FCSousa/EMA6_SMA40_Pattern/Types.mqh>

class CMarketData
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_ema6_period;
   int             m_sma40_period;
   int             m_atr_period;
   int             m_required_history;
   int             m_ema6_handle;
   int             m_sma40_handle;
   int             m_atr_handle;

public:
   CMarketData(void)
     {
      m_symbol = "";
      m_timeframe = PERIOD_CURRENT;
      m_ema6_period = 6;
      m_sma40_period = 40;
      m_atr_period = 14;
      m_required_history = 0;
      m_ema6_handle = INVALID_HANDLE;
      m_sma40_handle = INVALID_HANDLE;
      m_atr_handle = INVALID_HANDLE;
     }

   bool Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe,
                   const int ema6_period, const int sma40_period,
                   const int atr_period, string &error)
     {
      Release();
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_ema6_period = ema6_period;
      m_sma40_period = sma40_period;
      m_atr_period = atr_period;
      m_required_history = MathMax(m_ema6_period, MathMax(m_sma40_period, m_atr_period)) + 4;
      ResetLastError();
      m_ema6_handle = iMA(m_symbol, m_timeframe, m_ema6_period, 0, MODE_EMA, PRICE_CLOSE);
      m_sma40_handle = iMA(m_symbol, m_timeframe, m_sma40_period, 0, MODE_SMA, PRICE_CLOSE);
      m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
      if(m_ema6_handle == INVALID_HANDLE || m_sma40_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE)
        {
         error = StringFormat("Falha ao criar handles EMA6/SMA40/ATR. erro=%d", GetLastError());
         Release();
         return false;
        }
      error = "";
      return true;
     }

   bool LoadSnapshot(MarketSnapshot &snapshot, string &error)
     {
      const int required_values = 4;
      if(Bars(m_symbol, m_timeframe) < m_required_history ||
         BarsCalculated(m_ema6_handle) < required_values ||
         BarsCalculated(m_sma40_handle) < required_values ||
         BarsCalculated(m_atr_handle) < required_values)
        {
         error = "Historico ou buffers EMA6/SMA40/ATR insuficientes.";
         return false;
        }
      MqlRates rates[];
      double ema6[];
      double sma40[];
      double atr[];
      ArrayResize(rates, required_values);
      ArrayResize(ema6, required_values);
      ArrayResize(sma40, required_values);
      ArrayResize(atr, required_values);
      ArraySetAsSeries(rates, true);
      ArraySetAsSeries(ema6, true);
      ArraySetAsSeries(sma40, true);
      ArraySetAsSeries(atr, true);
      ResetLastError();
      if(CopyRates(m_symbol, m_timeframe, 0, required_values, rates) != required_values ||
         CopyBuffer(m_ema6_handle, 0, 0, required_values, ema6) != required_values ||
         CopyBuffer(m_sma40_handle, 0, 0, required_values, sma40) != required_values ||
         CopyBuffer(m_atr_handle, 0, 0, required_values, atr) != required_values)
        {
         error = StringFormat("CopyRates/CopyBuffer EMA6/SMA40/ATR incompleto. erro=%d", GetLastError());
         return false;
        }
      SpreadSnapshot spread = {};
      if(!LoadSpreadSnapshot(m_symbol, spread))
        {
         error = StringFormat("Spread/tick indisponivel no snapshot. reason=%s erro=%u", spread.reason, spread.error_code);
         return false;
        }
      const double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick_size <= 0.0 || !MathIsValidNumber(tick_size))
        {
         error = "SYMBOL_TRADE_TICK_SIZE invalido.";
         return false;
        }
      ZeroMemory(snapshot);
      snapshot.symbol = m_symbol;
      snapshot.timeframe = m_timeframe;
      snapshot.loaded_at = TimeCurrent();
      snapshot.tick.bid = spread.bid;
      snapshot.tick.ask = spread.ask;
      snapshot.tick_size = tick_size;
      snapshot.point = spread.point;
      snapshot.digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      snapshot.current_bar = rates[0];
      snapshot.signal_bar = rates[1];
      snapshot.previous_bar = rates[2];
      snapshot.context_bar = rates[3];
      snapshot.ema_6_signal = ema6[1];
      snapshot.ema_6_previous = ema6[2];
      snapshot.sma_40_signal = sma40[1];
      snapshot.atr_signal = atr[1];
      if(snapshot.atr_signal <= 0.0 || !MathIsValidNumber(snapshot.atr_signal))
        {
         error = "ATR invalido no candle de sinal.";
         return false;
        }
      error = "";
      return true;
     }

   bool LoadSMA40PastValue(const int lookback, double &sma40_past, string &error)
     {
      sma40_past = 0.0;
      if(lookback <= 0 || BarsCalculated(m_sma40_handle) <= 1 + lookback)
        {
         error = "Historico SMA40 insuficiente para slope.";
         return false;
        }
      double value[1];
      ResetLastError();
      if(CopyBuffer(m_sma40_handle, 0, 1 + lookback, 1, value) != 1 || !MathIsValidNumber(value[0]))
        {
         error = StringFormat("CopyBuffer SMA40 slope falhou. erro=%d", GetLastError());
         return false;
        }
      sma40_past = value[0];
      error = "";
      return true;
     }

   bool LoadHigherTFEMAValues(double &fast_value, double &slow_value, string &error)
     {
      fast_value = 0.0;
      slow_value = 0.0;
      error = "Filtro Higher TF nao suportado nesta estrategia.";
      return false;
     }

   void Release(void)
     {
      if(m_ema6_handle != INVALID_HANDLE) { IndicatorRelease(m_ema6_handle); m_ema6_handle = INVALID_HANDLE; }
      if(m_sma40_handle != INVALID_HANDLE) { IndicatorRelease(m_sma40_handle); m_sma40_handle = INVALID_HANDLE; }
      if(m_atr_handle != INVALID_HANDLE) { IndicatorRelease(m_atr_handle); m_atr_handle = INVALID_HANDLE; }
     }
  };

#endif