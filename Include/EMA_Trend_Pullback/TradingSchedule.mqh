#ifndef __EMA_TREND_PULLBACK_TRADING_SCHEDULE_MQH__
#define __EMA_TREND_PULLBACK_TRADING_SCHEDULE_MQH__

class CTradingSchedule
{
private:
   bool m_kill1_enabled;
   int m_kill1_start;
   int m_kill1_end;

   bool m_kill2_enabled;
   int m_kill2_start;
   int m_kill2_end;

   bool m_avoid_weekend;
   int m_friday_exit;
   int m_monday_resume;

   int MinuteOfDay(const datetime value) const
   {
      MqlDateTime dt = {};
      TimeToStruct(value, dt);
      return dt.hour * 60 + dt.min;
   }

   bool InWindow(const int now_min,
                 const int start_min,
                 const int end_min) const
   {
      if(start_min <= end_min)
         return now_min >= start_min && now_min <= end_min;

      return now_min >= start_min || now_min <= end_min;
   }

public:
   CTradingSchedule(void)
   {
      m_kill1_enabled = true;
      m_kill1_start = 23 * 60;
      m_kill1_end = 23 * 60 + 59;

      m_kill2_enabled = true;
      m_kill2_start = 0;
      m_kill2_end = 59;

      m_avoid_weekend = true;
      m_friday_exit = 20 * 60;
      m_monday_resume = 60;
   }

   void Configure(const bool kill1_enabled,
                  const int kill1_start_hour,
                  const int kill1_start_minute,
                  const int kill1_end_hour,
                  const int kill1_end_minute,
                  const bool kill2_enabled,
                  const int kill2_start_hour,
                  const int kill2_start_minute,
                  const int kill2_end_hour,
                  const int kill2_end_minute,
                  const bool avoid_weekend,
                  const int friday_exit_hour,
                  const int friday_exit_minute,
                  const int monday_resume_hour,
                  const int monday_resume_minute)
   {
      m_kill1_enabled = kill1_enabled;
      m_kill1_start = kill1_start_hour * 60 + kill1_start_minute;
      m_kill1_end = kill1_end_hour * 60 + kill1_end_minute;

      m_kill2_enabled = kill2_enabled;
      m_kill2_start = kill2_start_hour * 60 + kill2_start_minute;
      m_kill2_end = kill2_end_hour * 60 + kill2_end_minute;

      m_avoid_weekend = avoid_weekend;
      m_friday_exit = friday_exit_hour * 60 + friday_exit_minute;
      m_monday_resume = monday_resume_hour * 60 + monday_resume_minute;
   }

   bool IsKillTime(const datetime server_time,
                   string &reason) const
   {
      reason = "";
      const int now_min = MinuteOfDay(server_time);

      if(m_kill1_enabled &&
         InWindow(now_min, m_kill1_start, m_kill1_end))
      {
         reason = "Kill Time 1.";
         return true;
      }

      if(m_kill2_enabled &&
         InWindow(now_min, m_kill2_start, m_kill2_end))
      {
         reason = "Kill Time 2.";
         return true;
      }

      return false;
   }

   bool IsWeekendBlocked(const datetime server_time,
                         string &reason) const
   {
      reason = "";

      if(!m_avoid_weekend)
         return false;

      MqlDateTime dt = {};
      TimeToStruct(server_time, dt);
      const int minute = dt.hour * 60 + dt.min;

      // MQL5: 0 domingo ... 6 sabado
      if(dt.day_of_week == 6 || dt.day_of_week == 0)
      {
         reason = "Fim de semana.";
         return true;
      }

      if(dt.day_of_week == 5 && minute >= m_friday_exit)
      {
         reason = "Sexta-feira apos horario limite.";
         return true;
      }

      if(dt.day_of_week == 1 && minute < m_monday_resume)
      {
         reason = "Segunda-feira antes da retomada.";
         return true;
      }

      return false;
   }

   bool ShouldForceWeekendFlat(const datetime server_time) const
   {
      if(!m_avoid_weekend)
         return false;

      MqlDateTime dt = {};
      TimeToStruct(server_time, dt);

      const int minute = dt.hour * 60 + dt.min;

      return dt.day_of_week == 5 &&
             minute >= m_friday_exit;
   }
};

#endif
