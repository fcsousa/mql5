#ifndef __EMA_TREND_PULLBACK_TYPES_MQH__
#define __EMA_TREND_PULLBACK_TYPES_MQH__

enum ENUM_EA_STATE
{
   EA_STATE_IDLE = 0,
   EA_STATE_ORDER_PENDING,
   EA_STATE_POSITION_OPEN,
   EA_STATE_ERROR
};

enum ENUM_SIGNAL_DIRECTION
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY,
   SIGNAL_SELL
};

enum ENUM_EA_DIRECTION_MODE
{
   EA_DIRECTION_BOTH = 0,
   EA_DIRECTION_BUY,
   EA_DIRECTION_SELL
};

enum ENUM_EA_PATTERN
{
   EA_PATTERN_ENGULFING = 0,
   EA_PATTERN_123,
   EA_PATTERN_PFR
};

struct MarketSnapshot
{
   MqlRates rates[6];

   double ema21_1;
   double ema40_1;
   double ema80_1;
   double atr_1;

   double spread_points;
   double point;
   double tick_size;
   datetime signal_time;
};

struct TechnicalSignal
{
   bool valid;
   string signal_id;
   string setup_name;
   string pattern_name;
   datetime signal_time;
   ENUM_SIGNAL_DIRECTION direction;

   double technical_entry_price;
   double technical_stop_price;
};

struct TradePlan
{
   string signal_id;
   string setup_name;
   string pattern_name;
   datetime signal_time;
   ENUM_SIGNAL_DIRECTION direction;
   ENUM_ORDER_TYPE order_type;

   double technical_entry_price;
   double technical_stop_price;
   double target_r;
   double risk_percent;

   datetime expiration;
   double signal_spread_points;
   double atr_value;
};

struct RiskResult
{
   bool success;
   double volume;
   double planned_risk_money;
   double loss_per_lot;
   double estimated_round_trip_cost;
   double round_trip_cost_risk_percent;
   double target_price;
   string message;
};

struct ExecutionResult
{
   bool success;
   uint retcode;
   ulong order_ticket;
   double requested_price;
   double normalized_entry_price;
   double normalized_stop_price;
   double normalized_target_price;
   string message;
};

struct SetupMetrics
{
   ulong signals;
   ulong rejected_regime;
   ulong rejected_cost;
   ulong rejected_spread;
   ulong rejected_stop;
   ulong rejected_time;
   ulong pending_not_filled;
   ulong executed;
   ulong wins;
   ulong losses;
   double net_profit;
};

#endif
