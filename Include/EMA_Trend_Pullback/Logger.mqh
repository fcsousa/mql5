#ifndef __EMA_TREND_PULLBACK_LOGGER_MQH__
#define __EMA_TREND_PULLBACK_LOGGER_MQH__

class CLogger
{
private:
   bool m_enabled;

   void Write(const string level,
              const string event_name,
              const string symbol,
              const string signal_id,
              const string message)
   {
      if(!m_enabled && level == "INFO")
         return;

      PrintFormat("%s | %s | %s | %s | %s",
                  level,
                  event_name,
                  symbol,
                  signal_id,
                  message);
   }

public:
   CLogger(void) : m_enabled(true) {}

   void Configure(const bool enabled)
   {
      m_enabled = enabled;
   }

   void Info(const string event_name,
             const string symbol,
             const string signal_id,
             const string message)
   {
      Write("INFO", event_name, symbol, signal_id, message);
   }

   void Warning(const string event_name,
                const string symbol,
                const string signal_id,
                const string message)
   {
      Write("WARN", event_name, symbol, signal_id, message);
   }

   void Error(const string event_name,
              const string symbol,
              const string signal_id,
              const string message)
   {
      Write("ERROR", event_name, symbol, signal_id, message);
   }
};

#endif
