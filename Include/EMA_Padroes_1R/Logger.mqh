#ifndef EMA_PADROES_1R_LOGGER_MQH
#define EMA_PADROES_1R_LOGGER_MQH

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

      PrintFormat(
         "%s | %s | %s | %s | %s | %s",
         TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
         level,
         event_name,
         symbol,
         signal_id,
         message
      );
     }

public:
   CLogger(void)
     {
      m_enabled = true;
     }

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
