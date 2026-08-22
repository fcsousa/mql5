#ifndef EMA_PADROES_1R_TYPES_MQH
#define EMA_PADROES_1R_TYPES_MQH

//====================================================================
// Estados operacionais do EA
//====================================================================
enum ENUM_EA_STATE
  {
   EA_STATE_IDLE = 0,
   EA_STATE_ORDER_PENDING,
   EA_STATE_POSITION_OPEN,
   EA_STATE_ERROR
  };

// Direcao efetiva de um sinal.
enum ENUM_SIGNAL_DIRECTION
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY,
   SIGNAL_SELL
  };

// Filtro de direcao configuravel pelo usuario.
enum ENUM_EA_DIRECTION_MODE
  {
   EA_DIRECTION_BOTH = 0,
   EA_DIRECTION_BUY_ONLY,
   EA_DIRECTION_SELL_ONLY
  };

// Tipos de formacao usados na prioridade de selecao.
enum ENUM_EA_PATTERN
  {
   EA_PATTERN_123 = 0,
   EA_PATTERN_PFR,
   EA_PATTERN_ENGULFING
  };

// Acao quando o risco real, apos o fill, excede a tolerancia.
enum ENUM_EA_REAL_RISK_ACTION
  {
   EA_REAL_RISK_REDUCE = 0, // reduz o volume para voltar ao limite
   EA_REAL_RISK_CLOSE        // encerra integralmente a posicao
  };

// Motivos padronizados de cancelamento para auditoria.
enum ENUM_EA_CANCEL_REASON
  {
   CANCEL_NONE = 0,
   CANCEL_SPREAD,
   CANCEL_KILL_TIME,
   CANCEL_ROLLOVER,
   CANCEL_WEEKEND,
   CANCEL_EXPIRATION,
   CANCEL_RISK
  };

// Estados semanticos da leitura de spread.
// SPREAD_DATA_INVALID significa que o spread nao pode ser determinado com
// seguranca; nao equivale a spread excessivo.
enum ENUM_SPREAD_STATUS
  {
   SPREAD_OK = 0,
   SPREAD_TOO_HIGH,
   SPREAD_DATA_INVALID
  };

struct SpreadSnapshot
  {
   bool   valid;
   double bid;
   double ask;
   double point;
   double spread_price;
   double spread_points;
   uint   error_code;
   string reason;
  };

// Fonte unica para leitura/validacao do spread.
// ask == bid e spread zero sao validos quando os demais dados sao coerentes.
bool LoadSpreadSnapshot(const string symbol,
                        SpreadSnapshot &snapshot)
  {
   ZeroMemory(snapshot);
   snapshot.valid = false;
   snapshot.reason = "";

   ResetLastError();
   if(!SymbolInfoDouble(symbol, SYMBOL_POINT, snapshot.point))
     {
      snapshot.error_code = (uint)GetLastError();
      snapshot.reason = "Falha ao obter SYMBOL_POINT.";
      return false;
     }

   if(!MathIsValidNumber(snapshot.point) || snapshot.point <= 0.0)
     {
      snapshot.reason = "SYMBOL_POINT invalido.";
      return false;
     }

   MqlTick tick = {};
   ResetLastError();
   if(!SymbolInfoTick(symbol, tick))
     {
      snapshot.error_code = (uint)GetLastError();
      snapshot.reason = "SymbolInfoTick falhou.";
      return false;
     }

   snapshot.bid = tick.bid;
   snapshot.ask = tick.ask;

   if(!MathIsValidNumber(snapshot.bid) ||
      !MathIsValidNumber(snapshot.ask) ||
      snapshot.bid <= 0.0 ||
      snapshot.ask <= 0.0)
     {
      snapshot.reason = "Bid/ask invalidos.";
      return false;
     }

   if(snapshot.ask < snapshot.bid)
     {
      snapshot.reason = "Ask menor que bid.";
      return false;
     }

   snapshot.spread_price = snapshot.ask - snapshot.bid;
   snapshot.spread_points = snapshot.spread_price / snapshot.point;

   if(!MathIsValidNumber(snapshot.spread_price) ||
      !MathIsValidNumber(snapshot.spread_points) ||
      snapshot.spread_price < 0.0 ||
      snapshot.spread_points < 0.0)
     {
      snapshot.reason = "Spread calculado invalido.";
      return false;
     }

   snapshot.valid = true;
   return true;
  }

ENUM_SPREAD_STATUS EvaluateSpreadStatus(const SpreadSnapshot &snapshot,
                                        const double max_spread_points)
  {
   if(!snapshot.valid)
      return SPREAD_DATA_INVALID;

   if(max_spread_points > 0.0 &&
      snapshot.spread_points > max_spread_points + 1e-9)
      return SPREAD_TOO_HIGH;

   return SPREAD_OK;
  }

struct PatternResult
  {
   bool            pattern_123;
   bool            pfr;
   bool            engulfing;
   ENUM_EA_PATTERN selected_pattern;
   int             formation_bars;
   string          name;
  };

// Sinal tecnico detectado antes de filtros operacionais/regime e antes do TradePlan.
struct TechnicalSignal
  {
   string                signal_id;
   string                pattern_name;
   string                entry_trap_name;
   datetime              signal_time;
   ENUM_SIGNAL_DIRECTION direction;
   int                   formation_bars;
  };

struct MarketSnapshot
  {
   string          symbol;
   ENUM_TIMEFRAMES timeframe;
   datetime        loaded_at;
   MqlTick         tick;
   double          tick_size;
   double          point;
   int             digits;

   MqlRates        current_bar;
   MqlRates        signal_bar;
   MqlRates        previous_bar;
   MqlRates        context_bar;

   double          ema_21_signal;
   double          ema_21_previous;
   double          ema_40_signal;
   double          ema_80_signal;
   double          ema_80_previous;
   double          atr_signal;
  };

// Plano tecnico produzido exclusivamente pela estrategia.
struct TradePlan
  {
   string                signal_id;
   string                pattern_name;
   datetime              signal_time;
   ENUM_SIGNAL_DIRECTION direction;
   ENUM_ORDER_TYPE       order_type;

   double                technical_entry_price;
   double                technical_stop_price;
   double                technical_target_price;
   double                target_r;
   double                risk_percent;
   double                atr_value;
   double                signal_spread_price;
   double                signal_spread_points;

   datetime              expiration;
  };

// Ordem apos normalizacao e aplicacao das regras do broker.
struct PreparedOrder
  {
   string                signal_id;
   string                pattern_name;
   datetime              signal_time;
   ENUM_SIGNAL_DIRECTION direction;
   ENUM_ORDER_TYPE       order_type;

   double                technical_entry_price;
   double                submitted_entry_price;
   double                submitted_stop_price;
   double                submitted_target_price;
   double                target_r;

   double                signal_spread_price;
   double                signal_spread_points;
   double                spread_price;       // spread usado no sizing
   double                spread_points;
   double                send_spread_price;  // spread revalidado imediatamente antes do envio
   double                send_spread_points;
   double                stop_spread_ratio;
   double                stop_points;
   double                atr_value;
   double                atr_points;
   double                minimum_stop_points_required;

   datetime              expiration;
  };

struct OperationResult
  {
   bool   success;
   uint   code;
   string message;
  };

// Componentes de custo calculados na moeda da conta.
struct CostEstimate
  {
   bool   success;
   double commission_per_lot;
   double spread_per_lot;
   double slippage_per_lot;
   double total_per_lot;
   double commission_total;
   double spread_total;
   double slippage_total;
   double total;
   string message;
  };

struct RiskResult
  {
   bool   success;
   double volume;

   // Limite configurado (% do saldo) e risco efetivamente planejado.
   double risk_budget_money;
   double planned_technical_loss;
   double planned_total_risk;

   // Custos estimados do round trip para o volume final.
   double estimated_cost;
   double estimated_commission;
   double estimated_spread_cost;
   double estimated_slippage_cost;
   double round_trip_cost_risk_percent;

   // Alvo bruto necessario para entregar o R liquido.
   double gross_target_profit;
   double target_price;

   // Diagnostico por lote.
   double technical_loss_per_lot;
   double total_loss_per_lot;

   string message;
  };

struct RealRiskResult
  {
   bool   success;
   double technical_loss;
   double estimated_cost;
   double actual_slippage_cost;
   double real_risk;
   double allowed_risk;
   double excess_percent;
   double target_safe_volume;
   string message;
  };

struct ExecutionResult
  {
   bool   success;
   uint   retcode;
   ulong  order_ticket;
   ulong  deal_ticket;

   double technical_entry_price;
   double requested_price;
   double submitted_entry_price;
   double submitted_stop_price;
   double submitted_target_price;
   double executed_price;

   string message;
  };


// Contadores quantitativos do funil de sinais.
// signals_detected conta sinais unicos produzidos pela Strategy.
// rejected_* identifica a causa de rejeicao do sinal.
// pending_not_filled conta ordens aceitas que terminaram sem qualquer fill.
// executed conta sinais que tiveram pelo menos um deal de entrada confirmado.
struct FunnelCounters
  {
   ulong signals_detected;
   ulong rejected_regime;
   ulong rejected_higher_tf;
   ulong rejected_cost_risk;
   ulong rejected_spread;
   ulong rejected_stop;
   ulong rejected_kill_time;
   ulong rejected_weekend;
   ulong pending_not_filled;
   ulong executed;
  };


// Metricas de auditoria segmentadas por padrao e direcao.
// Cada bucket representa uma estrategia operacional distinta para evitar
// que BUY e SELL ocultem assimetrias de execucao ou qualidade.
struct PatternDirectionMetrics
  {
   ulong  signals;
   ulong  rejected_regime;
   ulong  rejected_higher_tf;
   ulong  rejected_cost;
   ulong  rejected_spread;
   ulong  rejected_stop;
   ulong  pending_not_filled;
   ulong  executed;
   ulong  wins;
   ulong  losses;
   double net_profit;
  };

// Auditoria de um unico sinal/operacao. A arquitetura do EA permite uma
// operacao por vez; portanto, uma estrutura ativa e suficiente.
struct TradeAudit
  {
   bool                  active;
   string                signal_id;
   string                pattern_name;
   string                entry_trap_name;
   datetime              signal_time;
   ENUM_SIGNAL_DIRECTION direction;

   ulong                 order_ticket;
   ulong                 position_ticket;
   ulong                 position_identifier;

   double                volume_planned;
   double                volume_executed;

   double                spread_signal_points;
   double                spread_send_points;
   double                spread_max_pending_points;
   double                spread_fill_points;

   double                technical_entry_price;
   double                normalized_entry_price;
   double                requested_price;
   double                executed_price;
   double                slippage_points;
   double                stop_price;
   double                target_price;
   double                stop_points;

   double                estimated_cost;
   double                realized_cost;
   double                realized_commission_fee;
   double                realized_spread_cost;
   double                realized_slippage_cost;
   double                planned_risk;
   double                real_risk;
   double                trade_net_profit;

   ENUM_EA_CANCEL_REASON cancel_reason;
   string                cancel_detail;
   bool                  risk_control_attempted;
   bool                  execution_counted;
   bool                  pending_not_filled_counted;
  };

#endif
