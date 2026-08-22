#ifndef __EMA_TREND_PULLBACK_MARKET_DATA_MQH__
#define __EMA_TREND_PULLBACK_MARKET_DATA_MQH__

#include <EMA_Trend_Pullback/Types.mqh>

class CMarketData
{
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   int m_ema21_handle;
   int m_ema40_handle;
   int m_ema80_handle;
   int m_atr_handle;

   int m_ema21_period;
   int m_ema40_period;
   int m_ema80_period;
   int m_atr_period;

public:
   CMarketData(void)
   {
      m_symbol = "";
      m_timeframe = PERIOD_CURRENT;
      m_ema21_handle = INVALID_HANDLE;
      m_ema40_handle = INVALID_HANDLE;
      m_ema80_handle = INVALID_HANDLE;
      m_atr_handle = INVALID_HANDLE;
      m_ema21_period = 21;
      m_ema40_period = 40;
      m_ema80_period = 80;
      m_atr_period = 14;
   }

   bool Initialize(const string symbol,
                   const ENUM_TIMEFRAMES timeframe,
                   const int ema21_period,
                   const int ema40_period,
                   const int ema80_period,
                   const int atr_period,
                   string &error)
   {
      error = "";
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_ema21_period = ema21_period;
      m_ema40_period = ema40_period;
      m_ema80_period = ema80_period;
      m_atr_period = atr_period;

      m_ema21_handle = iMA(m_symbol, m_timeframe, m_ema21_period, 0, MODE_EMA, PRICE_CLOSE);
      m_ema40_handle = iMA(m_symbol, m_timeframe, m_ema40_period, 0, MODE_EMA, PRICE_CLOSE);
      m_ema80_handle = iMA(m_symbol, m_timeframe, m_ema80_period, 0, MODE_EMA, PRICE_CLOSE);
      m_atr_handle   = iATR(m_symbol, m_timeframe, m_atr_period);

      if(m_ema21_handle == INVALID_HANDLE ||
         m_ema40_handle == INVALID_HANDLE ||
         m_ema80_handle == INVALID_HANDLE ||
         m_atr_handle == INVALID_HANDLE)
      {
         error = StringFormat("Falha ao criar handles. last_error=%d", GetLastError());
         return false;
      }

      return true;
   }

   void Release(void)
   {
      if(m_ema21_handle != INVALID_HANDLE) IndicatorRelease(m_ema21_handle);
      if(m_ema40_handle != INVALID_HANDLE) IndicatorRelease(m_ema40_handle);
      if(m_ema80_handle != INVALID_HANDLE) IndicatorRelease(m_ema80_handle);
      if(m_atr_handle != INVALID_HANDLE)   IndicatorRelease(m_atr_handle);

      m_ema21_handle = INVALID_HANDLE;
      m_ema40_handle = INVALID_HANDLE;
      m_ema80_handle = INVALID_HANDLE;
      m_atr_handle = INVALID_HANDLE;
   }

   bool LoadSnapshot(MarketSnapshot &snapshot, string &error)
   {
      error = "";

      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      const int copied_rates = CopyRates(m_symbol, m_timeframe, 0, 6, rates);
      if(copied_rates != 6)
      {
         error = StringFormat("CopyRates esperado=6 recebido=%d erro=%d",
                              copied_rates, GetLastError());
         return false;
      }

      for(int i = 0; i < 6; i++)
         snapshot.rates[i] = rates[i];

      double ema21[];
      double ema40[];
      double ema80[];
      double atr[];

      ArraySetAsSeries(ema21, true);
      ArraySetAsSeries(ema40, true);
      ArraySetAsSeries(ema80, true);
      ArraySetAsSeries(atr, true);

      if(CopyBuffer(m_ema21_handle, 0, 0, 3, ema21) != 3 ||
         CopyBuffer(m_ema40_handle, 0, 0, 3, ema40) != 3 ||
         CopyBuffer(m_ema80_handle, 0, 0, 3, ema80) != 3 ||
         CopyBuffer(m_atr_handle,   0, 0, 3, atr)   != 3)
      {
         error = StringFormat("CopyBuffer insuficiente. erro=%d", GetLastError());
         return false;
      }

      MqlTick tick = {};
      if(!SymbolInfoTick(m_symbol, tick))
      {
         error = StringFormat("SymbolInfoTick falhou. erro=%d", GetLastError());
         return false;
      }

      snapshot.point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      snapshot.tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);

      if(snapshot.point <= 0.0 || snapshot.tick_size <= 0.0)
      {
         error = "SYMBOL_POINT ou SYMBOL_TRADE_TICK_SIZE invalido.";
         return false;
      }

      snapshot.ema21_1 = ema21[1];
      snapshot.ema40_1 = ema40[1];
      snapshot.ema80_1 = ema80[1];
      snapshot.atr_1   = atr[1];
      snapshot.signal_time = rates[1].time;
      snapshot.spread_points = (tick.ask - tick.bid) / snapshot.point;

      if(!MathIsValidNumber(snapshot.ema21_1) ||
         !MathIsValidNumber(snapshot.ema40_1) ||
         !MathIsValidNumber(snapshot.ema80_1) ||
         !MathIsValidNumber(snapshot.atr_1) ||
         snapshot.atr_1 <= 0.0)
      {
         error = "Indicadores invalidos no candle fechado.";
         return false;
      }

      return true;
   }

   bool LoadEMA40PastValue(const int lookback, double &value, string &error)
   {
      error = "";
      value = 0.0;

      if(lookback <= 0)
      {
         error = "Lookback invalido.";
         return false;
      }

      double buffer[];
      ArraySetAsSeries(buffer, true);

      const int need = lookback + 2;
      if(CopyBuffer(m_ema40_handle, 0, 0, need, buffer) != need)
      {
         error = StringFormat("CopyBuffer EMA40 passado falhou. erro=%d", GetLastError());
         return false;
      }

      value = buffer[1 + lookback];
      return MathIsValidNumber(value);
   }
};

#endif
