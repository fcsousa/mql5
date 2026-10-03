#ifndef EMA_PADROES_1R_TRADING_SCHEDULE_MQH
#define EMA_PADROES_1R_TRADING_SCHEDULE_MQH

// Todos os horÃ¡rios desta classe usam o horÃ¡rio do servidor da corretora.
class CTradingSchedule
  {
private:
   bool m_kill_1_enabled;
   int  m_kill_1_start;
   int  m_kill_1_end;

   bool m_kill_2_enabled;
   int  m_kill_2_start;
   int  m_kill_2_end;

   bool m_cancel_before_rollover;
   int  m_rollover_minute;
   int  m_cancel_lead_minutes;

   bool m_avoid_weekend;
   int  m_friday_exit_minute;
   int  m_monday_resume_minute;

   int ToMinute(const int hour, const int minute)
     {
      return hour * 60 + minute;
     }

   int MinuteOfDay(const MqlDateTime &time_parts)
     {
      return time_parts.hour * 60 + time_parts.min;
     }

   bool IsInsideWindow(const int current_minute,
                       const int start_minute,
                       const int end_minute)
     {
      if(start_minute <= end_minute)
        {
         return(
            current_minute >= start_minute &&
            current_minute <= end_minute
         );
        }

      // Janela que cruza a meia-noite, por exemplo 23:30 atÃ© 00:30.
      return(
         current_minute >= start_minute ||
         current_minute <= end_minute
      );
     }

   bool DecodeTime(const datetime server_time,
                   MqlDateTime &time_parts)
     {
      ZeroMemory(time_parts);
      return TimeToStruct(server_time, time_parts);
     }

public:
   CTradingSchedule(void)
     {
      m_kill_1_enabled        = true;
      m_kill_1_start          = ToMinute(23, 0);
      m_kill_1_end            = ToMinute(23, 59);
      m_kill_2_enabled        = true;
      m_kill_2_start          = ToMinute(0, 0);
      m_kill_2_end            = ToMinute(0, 59);
      m_cancel_before_rollover = true;
      m_rollover_minute       = ToMinute(0, 0);
      m_cancel_lead_minutes   = 15;
      m_avoid_weekend         = true;
      m_friday_exit_minute    = ToMinute(20, 0);
      m_monday_resume_minute  = ToMinute(1, 0);
     }

   void Configure(const bool kill_1_enabled,
                  const int kill_1_start_hour,
                  const int kill_1_start_minute,
                  const int kill_1_end_hour,
                  const int kill_1_end_minute,
                  const bool kill_2_enabled,
                  const int kill_2_start_hour,
                  const int kill_2_start_minute,
                  const int kill_2_end_hour,
                  const int kill_2_end_minute,
                  const bool cancel_before_rollover,
                  const int rollover_hour,
                  const int rollover_minute,
                  const int cancel_lead_minutes,
                  const bool avoid_weekend,
                  const int friday_exit_hour,
                  const int friday_exit_minute,
                  const int monday_resume_hour,
                  const int monday_resume_minute)
     {
      m_kill_1_enabled         = kill_1_enabled;
      m_kill_1_start           = ToMinute(
         kill_1_start_hour,
         kill_1_start_minute
      );
      m_kill_1_end             = ToMinute(
         kill_1_end_hour,
         kill_1_end_minute
      );

      m_kill_2_enabled         = kill_2_enabled;
      m_kill_2_start           = ToMinute(
         kill_2_start_hour,
         kill_2_start_minute
      );
      m_kill_2_end             = ToMinute(
         kill_2_end_hour,
         kill_2_end_minute
      );

      m_cancel_before_rollover = cancel_before_rollover;
      m_rollover_minute        = ToMinute(
         rollover_hour,
         rollover_minute
      );
      m_cancel_lead_minutes    = cancel_lead_minutes;

      m_avoid_weekend          = avoid_weekend;
      m_friday_exit_minute     = ToMinute(
         friday_exit_hour,
         friday_exit_minute
      );
      m_monday_resume_minute   = ToMinute(
         monday_resume_hour,
         monday_resume_minute
      );
     }

   bool IsKillTime(const datetime server_time,
                   string &reason)
     {
      MqlDateTime time_parts = {};
      if(!DecodeTime(server_time, time_parts))
        {
         reason = "Falha ao converter o horario do servidor.";
         return true;
        }

      const int current_minute = MinuteOfDay(time_parts);

      if(m_kill_1_enabled &&
         IsInsideWindow(current_minute, m_kill_1_start, m_kill_1_end))
        {
         reason = "Kill Time 1 ativo.";
         return true;
        }

      if(m_kill_2_enabled &&
         IsInsideWindow(current_minute, m_kill_2_start, m_kill_2_end))
        {
         reason = "Kill Time 2 ativo.";
         return true;
        }

      reason = "";
      return false;
     }

   bool IsRolloverProtectionWindow(const datetime server_time)
     {
      if(!m_cancel_before_rollover || m_cancel_lead_minutes <= 0)
         return false;

      MqlDateTime time_parts = {};
      if(!DecodeTime(server_time, time_parts))
         return true;

      const int current_minute = MinuteOfDay(time_parts);
      const int minutes_until_rollover =
         (m_rollover_minute - current_minute + 1440) % 1440;

      return minutes_until_rollover <= m_cancel_lead_minutes;
     }

   bool IsWeekendBlocked(const datetime server_time,
                         string &reason)
     {
      if(!m_avoid_weekend)
        {
         reason = "";
         return false;
        }

      MqlDateTime time_parts = {};
      if(!DecodeTime(server_time, time_parts))
        {
         reason = "Falha ao converter o horario para o filtro semanal.";
         return true;
        }

      const int current_minute = MinuteOfDay(time_parts);

      if(time_parts.day_of_week == 5 &&
         current_minute >= m_friday_exit_minute)
        {
         reason = "Protecao de fim de semana ativa apos o horario de sexta.";
         return true;
        }

      if(time_parts.day_of_week == 6 || time_parts.day_of_week == 0)
        {
         reason = "Protecao de fim de semana ativa.";
         return true;
        }

      if(time_parts.day_of_week == 1 &&
         current_minute < m_monday_resume_minute)
        {
         reason = "Aguardando horario de retomada de segunda-feira.";
         return true;
        }

      reason = "";
      return false;
     }

   bool IsEntryBlocked(const datetime server_time,
                       string &reason)
     {
      if(IsWeekendBlocked(server_time, reason))
         return true;

      if(IsKillTime(server_time, reason))
         return true;

      if(IsRolloverProtectionWindow(server_time))
        {
         reason = "Janela preventiva anterior ao rollover.";
         return true;
        }

      reason = "";
      return false;
     }

   bool ShouldCancelPendingForRollover(const datetime server_time)
     {
      string reason = "";
      return(
         IsRolloverProtectionWindow(server_time) ||
         IsKillTime(server_time, reason)
      );
     }

   bool ShouldForceWeekendFlat(const datetime server_time)
     {
      if(!m_avoid_weekend)
         return false;

      MqlDateTime time_parts = {};
      if(!DecodeTime(server_time, time_parts))
         return false;

      const int current_minute = MinuteOfDay(time_parts);

      // O fechamento forcado e tentado na sexta enquanto o mercado ainda
      // esta aberto. Sabado e domingo permanecem apenas bloqueados.
      return(
         time_parts.day_of_week == 5 &&
         current_minute >= m_friday_exit_minute
      );
     }
  };

#endif
