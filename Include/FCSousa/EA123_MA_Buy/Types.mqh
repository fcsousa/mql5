#ifndef FCSOUSA_EA123_MA_BUY_TYPES_MQH
#define FCSOUSA_EA123_MA_BUY_TYPES_MQH

enum ENUM_SIGNAL_DIRECTION
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1
};

enum ENUM_ORDER_VALIDITY_MODE
{
   VALIDITY_ONE_CANDLE        = 0,
   VALIDITY_UNTIL_STOP_BROKEN = 1
};

enum ENUM_EA_STATE
{
   EA_STATE_IDLE = 0,
   EA_STATE_ORDER_PENDING,
   EA_STATE_POSITION_OPEN,
   EA_STATE_ERROR
};

struct TradePlan
{
   string                   signal_id;
   datetime                 signal_time;
   ENUM_SIGNAL_DIRECTION    direction;
   ENUM_ORDER_TYPE          order_type;
   ENUM_ORDER_VALIDITY_MODE validity_mode;

   double                   entry_price;
   double                   stop_price;
   double                   target_price;
   double                   risk_percent;

   datetime                 expiration_bar_time;
};

struct ExecutionResult
{
   bool   success;
   uint   retcode;

   ulong  order_ticket;
   ulong  deal_ticket;

   double requested_price;
   double normalized_price;
   double executed_price;

   string message;
};

double GetTradeTickSize(const string symbol)
{
   return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
}

double NormalizePriceUp(const string symbol, const double price)
{
   const double tick_size = GetTradeTickSize(symbol);

   if(tick_size <= 0.0)
      return 0.0;

   return MathCeil((price / tick_size) - 1e-12) * tick_size;
}

double NormalizePriceDown(const string symbol, const double price)
{
   const double tick_size = GetTradeTickSize(symbol);

   if(tick_size <= 0.0)
      return 0.0;

   return MathFloor((price / tick_size) + 1e-12) * tick_size;
}

bool IsAcceptedTradeRetcode(const uint retcode)
{
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_PLACED ||
          retcode == TRADE_RETCODE_DONE_PARTIAL;
}

#endif
