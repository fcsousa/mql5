//+------------------------------------------------------------------+
//|                                  EA_EMA_Padroes_1R_v4_2.mq5       |
//| EMA21/40/80 + 123, PFR ou Engolfo + risco percentual            |
//| Versao 4.20: metricas por padrao/direcao e OnTester robusto    |
//+------------------------------------------------------------------+
#property strict
#property version   "4.20"
#property description "EA modular EMA21/40/80 com padroes 123, PFR e Engolfo completo."
#property description "Inclui risco total, auditoria por padrao/direcao e criterio OnTester de robustez."

#include <FCSousa/EMA_Padroes_1R/Types.mqh>
#include <FCSousa/EMA_Padroes_1R/Logger.mqh>
#include <FCSousa/EMA_Padroes_1R/MarketData.mqh>
#include <FCSousa/EMA_Padroes_1R/Strategy.mqh>
#include <FCSousa/EMA_Padroes_1R/RiskManager.mqh>
#include <FCSousa/EMA_Padroes_1R/ExecutionManager.mqh>
#include <FCSousa/EMA_Padroes_1R/TradingSchedule.mqh>

//====================================================================
// Indicadores
//====================================================================
input group "Indicadores"
input int      InpEMA21Period       = 21;    // EMA de gatilho
input int      InpEMA40Period       = 40;    // EMA de contexto intermediaria
input int      InpEMA80Period       = 80;    // EMA de contexto longa
input bool     InpShowEMAs          = true;  // Exibir EMAs no grafico

//====================================================================
// Formacoes e prioridade
// Quando mais de um padrao ocorrer no mesmo candle, somente o primeiro
// padrao valido da ordem abaixo sera usado para entrada, stop e log.
//====================================================================
input group "Formacoes e prioridade"
input bool            InpUse123             = true;
input bool            InpUsePFR             = false; // desativado por padrao; codigo preservado para testes isolados
input bool            InpUseEngulfing       = true;
input ENUM_EA_PATTERN InpPatternPriority1   = EA_PATTERN_123;
input ENUM_EA_PATTERN InpPatternPriority2   = EA_PATTERN_PFR;
input ENUM_EA_PATTERN InpPatternPriority3   = EA_PATTERN_ENGULFING;

//====================================================================
// Direcao, risco e alvo
//====================================================================
input group "Direcao, risco e alvo"
input ENUM_EA_DIRECTION_MODE InpTradeDirection = EA_DIRECTION_BOTH;
input double                 InpRiskPercent    = 1.00;  // % do saldo
input double                 InpTargetR        = 1.00;  // alvo liquido em R

//====================================================================
// Risco total, custos e limite de lote
// O sizing considera: perda tecnica + comissao estimada + spread +
// reserva de slippage. A comissao deve ser informada na moeda da conta
// por 1.0 lote para o round trip completo (entrada + saida).
//====================================================================
input group "Risco total e custos"
input double InpMaxRoundTripCostRiskPercent       = 10.0; // custos <= % do risco
input double InpMaxVolumeLots                     = 10.0; // teto absoluto; 0 desabilita
input double InpEstimatedRoundTripCommissionPerLot = 0.0; // moeda da conta / lote
input double InpRoundTripSlippageReservePoints    = 2.0;  // reserva total em pontos
input double InpMaxRealRiskOverPlanPercent        = 10.0; // tolerancia apos o fill
input ENUM_EA_REAL_RISK_ACTION InpRealRiskAction  = EA_REAL_RISK_REDUCE;

//====================================================================
// Stop minimo
// O sinal e rejeitado quando o stop tecnico fica abaixo do maior entre:
// minimo absoluto, multiplo do spread, multiplo do ATR e stop level broker.
// O EA NAO afasta o stop tecnico: preserva a formacao e rejeita o setup.
//====================================================================
input group "Stop minimo"
input double InpMinStopPointsAbsolute = 10.0;
input int    InpATRPeriod             = 14;
input double InpMinStopATRMultiple    = 0.50;

//====================================================================
// Filtros de spread
// Pontos usam SYMBOL_POINT. Exemplo EURUSD com 5 digitos: 10 pontos = 1 pip.
// InpMinStopSpreadMultiple=3 exige stop operacional >= 3 x spread atual.
// Use zero para desabilitar qualquer um dos filtros.
//====================================================================
input group "Filtros de spread"
input double InpMaxSpreadPoints       = 30.0;
input double InpMinStopSpreadMultiple = 3.0;

//====================================================================
// Kill Time 1 - horario do servidor da corretora
// Padrao: bloqueia entradas das 23:00 ate 23:59.
//====================================================================
input group "Kill Time 1 - horario do servidor"
input bool InpKillTime1Enabled     = true;
input int  InpKillTime1StartHour   = 23;
input int  InpKillTime1StartMinute = 0;
input int  InpKillTime1EndHour     = 23;
input int  InpKillTime1EndMinute   = 59;

//====================================================================
// Kill Time 2 - horario do servidor da corretora
// Padrao: bloqueia entradas das 00:00 ate 00:59.
//====================================================================
input group "Kill Time 2 - horario do servidor"
input bool InpKillTime2Enabled     = true;
input int  InpKillTime2StartHour   = 0;
input int  InpKillTime2StartMinute = 0;
input int  InpKillTime2EndHour     = 0;
input int  InpKillTime2EndMinute   = 59;

//====================================================================
// Protecao de rollover
// Cancela ordens pendentes do EA antes do horario configurado e bloqueia
// novas entradas durante a janela preventiva.
//====================================================================
input group "Protecao de rollover - horario do servidor"
input bool InpCancelBeforeRollover      = true;
input int  InpRolloverHour              = 0;
input int  InpRolloverMinute            = 0;
input int  InpRolloverCancelLeadMinutes = 15;

//====================================================================
// Protecao de fim de semana
// Na sexta, a partir do horario configurado, cancela pendentes e envia
// posicoes deste Magic Number para fechamento. Entradas permanecem
// bloqueadas ate o horario de retomada de segunda-feira.
//====================================================================
input group "Protecao de fim de semana - horario do servidor"
input bool InpAvoidWeekend       = true;
input int  InpFridayExitHour     = 20;
input int  InpFridayExitMinute   = 0;
input int  InpMondayResumeHour   = 1;
input int  InpMondayResumeMinute = 0;

//====================================================================
// Execucao
//====================================================================
input group "Execucao"
input ulong InpMagicNumber     = 214080;
input ulong InpDeviationPoints = 20;
input bool  InpLogDetails      = true;
input int   InpSafetyTimerSeconds = 10; // watchdog de horario/seguranca

//====================================================================
// Otimizacao / OnTester
// Estes parametros NAO sao filtros tecnicos de entrada. Servem apenas para
// classificar passes de otimizacao por robustez, evitando selecionar setups
// por lucro bruto isolado.
//====================================================================
input group "Otimizacao - criterio de robustez"
input int    InpOptimizationMinTrades          = 30;   // amostra minima aceitavel
input double InpOptimizationMaxDrawdownPercent = 25.0; // acima disso recebe penalidade adicional

CLogger           g_logger;
CMarketData       g_market_data;
CStrategy         g_strategy;
CRiskManager      g_risk_manager;
CExecutionManager g_execution_manager;
CTradingSchedule  g_trading_schedule;

ENUM_EA_STATE g_ea_state = EA_STATE_IDLE;
datetime      g_last_bar_time = 0;
datetime      g_last_safety_minute = 0;
ulong         g_pending_order_ticket = 0;
ulong         g_position_ticket = 0;
string        g_last_processed_signal_id = "";

// Contexto operacional ativo. Como o EA permite apenas uma ordem/posicao
// por vez, um unico registro e suficiente para auditoria e revalidacoes.
PreparedOrder g_active_prepared = {};
RiskResult    g_active_risk = {};
TradeAudit    g_trade_audit = {};
FunnelCounters g_funnel = {};
PatternDirectionMetrics g_pattern_metrics[6];
bool          g_has_active_context = false;

int           g_visual_indicator_handle = INVALID_HANDLE;
string        g_visual_indicator_short_name = "";

// Retorna true somente no modo visual do Strategy Tester.
bool IsTesterVisualMode(void)
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      return false;

   return (bool)MQLInfoInteger(MQL_VISUAL_MODE);
  }

string DirectionToString(const ENUM_SIGNAL_DIRECTION direction)
  {
   if(direction == SIGNAL_BUY)
      return "COMPRA";

   if(direction == SIGNAL_SELL)
      return "VENDA";

   return "SEM_DIRECAO";
  }

bool IsValidHourMinute(const int hour, const int minute)
  {
   return(
      hour >= 0 && hour <= 23 &&
      minute >= 0 && minute <= 59
   );
  }

// Retorna o horario estimado do servidor da corretora. No tester ou em
// indisponibilidade temporaria, utiliza TimeCurrent como fallback seguro.
datetime GetBrokerServerTime(void)
  {
   datetime server_time = TimeTradeServer();
   if(server_time <= 0)
      server_time = TimeCurrent();

   return server_time;
  }

bool ValidateInputs(void)
  {
   if(InpEMA21Period <= 0 ||
      InpEMA40Period <= InpEMA21Period ||
      InpEMA80Period <= InpEMA40Period)
     {
      Print("Periodos invalidos: use EMA21 > 0, EMA40 > EMA21 e EMA80 > EMA40.");
      return false;
     }

   if(InpRiskPercent <= 0.0 || InpRiskPercent > 10.0)
     {
      Print("InpRiskPercent deve estar entre 0 e 10 por cento.");
      return false;
     }

   if(InpTargetR <= 0.0 || InpTargetR > 20.0)
     {
      Print("InpTargetR deve ser maior que zero e menor ou igual a 20.");
      return false;
     }

   if(InpMaxSpreadPoints < 0.0 || InpMinStopSpreadMultiple < 0.0)
     {
      Print("Filtros de spread nao podem ser negativos.");
      return false;
     }

   if(InpMaxRoundTripCostRiskPercent < 0.0 ||
      InpMaxRoundTripCostRiskPercent > 100.0)
     {
      Print("InpMaxRoundTripCostRiskPercent deve estar entre 0 e 100.");
      return false;
     }

   if(InpMaxVolumeLots < 0.0 ||
      InpEstimatedRoundTripCommissionPerLot < 0.0 ||
      InpRoundTripSlippageReservePoints < 0.0)
     {
      Print("Limite de lote, comissao e reserva de slippage nao podem ser negativos.");
      return false;
     }

   if(InpMaxRealRiskOverPlanPercent < 0.0 ||
      InpMaxRealRiskOverPlanPercent > 100.0)
     {
      Print("InpMaxRealRiskOverPlanPercent deve estar entre 0 e 100.");
      return false;
     }

   if(InpMinStopPointsAbsolute < 0.0 ||
      InpATRPeriod <= 0 ||
      InpMinStopATRMultiple < 0.0)
     {
      Print("Parametros de stop minimo/ATR invalidos.");
      return false;
     }

   if(!InpUse123 && !InpUsePFR && !InpUseEngulfing)
     {
      Print("Habilite pelo menos uma formacao operacional.");
      return false;
     }

   if(InpPatternPriority1 == InpPatternPriority2 ||
      InpPatternPriority1 == InpPatternPriority3 ||
      InpPatternPriority2 == InpPatternPriority3)
     {
      Print("As tres prioridades de padrao devem ser diferentes.");
      return false;
     }

   if(InpMagicNumber == 0)
     {
      Print("InpMagicNumber deve ser maior que zero.");
      return false;
     }

   if(InpSafetyTimerSeconds < 1 || InpSafetyTimerSeconds > 60)
     {
      Print("InpSafetyTimerSeconds deve estar entre 1 e 60 segundos.");
      return false;
     }

   if(InpOptimizationMinTrades < 0)
     {
      Print("InpOptimizationMinTrades nao pode ser negativo.");
      return false;
     }

   if(InpOptimizationMaxDrawdownPercent < 0.0 ||
      InpOptimizationMaxDrawdownPercent > 100.0)
     {
      Print("InpOptimizationMaxDrawdownPercent deve estar entre 0 e 100.");
      return false;
     }

   if(!IsValidHourMinute(InpKillTime1StartHour, InpKillTime1StartMinute) ||
      !IsValidHourMinute(InpKillTime1EndHour, InpKillTime1EndMinute) ||
      !IsValidHourMinute(InpKillTime2StartHour, InpKillTime2StartMinute) ||
      !IsValidHourMinute(InpKillTime2EndHour, InpKillTime2EndMinute) ||
      !IsValidHourMinute(InpRolloverHour, InpRolloverMinute) ||
      !IsValidHourMinute(InpFridayExitHour, InpFridayExitMinute) ||
      !IsValidHourMinute(InpMondayResumeHour, InpMondayResumeMinute))
     {
      Print("Existe horario invalido nos filtros operacionais.");
      return false;
     }

   if(InpRolloverCancelLeadMinutes < 0 ||
      InpRolloverCancelLeadMinutes > 360)
     {
      Print("InpRolloverCancelLeadMinutes deve estar entre 0 e 360.");
      return false;
     }

   return true;
  }

bool InitializeVisualIndicator(string &error)
  {
   error = "";

   if(!InpShowEMAs)
      return true;

   const bool is_tester = (bool)MQLInfoInteger(MQL_TESTER);
   if(is_tester && !IsTesterVisualMode())
      return true;

   g_visual_indicator_short_name = StringFormat(
      "EMA 21/40/80 (%d,%d,%d)",
      InpEMA21Period,
      InpEMA40Period,
      InpEMA80Period
   );

   ResetLastError();
   g_visual_indicator_handle = iCustom(
      _Symbol,
      PERIOD_CURRENT,
      "FCSousa\\EMA_21_40_80_Visual_v4_2",
      InpEMA21Period,
      InpEMA40Period,
      InpEMA80Period
   );

   if(g_visual_indicator_handle == INVALID_HANDLE)
     {
      error = StringFormat(
         "Falha ao criar indicador visual das EMAs. erro=%d",
         GetLastError()
      );
      return false;
     }

   // No tester visual, o indicador e adicionado automaticamente.
   if(is_tester)
      return true;

   ResetLastError();
   if(!ChartIndicatorAdd(0, 0, g_visual_indicator_handle))
     {
      error = StringFormat(
         "ChartIndicatorAdd falhou para as EMAs. erro=%d",
         GetLastError()
      );

      IndicatorRelease(g_visual_indicator_handle);
      g_visual_indicator_handle = INVALID_HANDLE;
      return false;
     }

   return true;
  }

void ReleaseVisualIndicator(void)
  {
   if(g_visual_indicator_short_name != "")
      ChartIndicatorDelete(0, 0, g_visual_indicator_short_name);

   if(g_visual_indicator_handle != INVALID_HANDLE)
     {
      IndicatorRelease(g_visual_indicator_handle);
      g_visual_indicator_handle = INVALID_HANDLE;
     }

   g_visual_indicator_short_name = "";
  }

void EnterErrorState(const string reason)
  {
   g_ea_state = EA_STATE_ERROR;
   g_logger.Error("EA_BLOCKED", _Symbol, "", reason);
  }

bool ReconcileState(void)
  {
   ENUM_EA_STATE recovered_state = EA_STATE_IDLE;
   ulong pending_ticket = 0;
   ulong position_ticket = 0;
   string error = "";

   if(!g_execution_manager.RecoverState(
         recovered_state,
         pending_ticket,
         position_ticket,
         error
      ))
     {
      EnterErrorState(error);
      return false;
     }

   g_ea_state = recovered_state;
   g_pending_order_ticket = pending_ticket;
   g_position_ticket = position_ticket;
   return true;
  }

//====================================================================
// Auditoria e cancelamentos padronizados
//====================================================================
//====================================================================
// Contadores quantitativos do funil
//
// Regras de contagem:
// - cada signal_id unico incrementa signals_detected uma unica vez;
// - rejected_* conta a causa que impediu aquele sinal de prosseguir;
// - pending_not_filled e um resultado de ciclo de vida da ordem aceita e
//   pode coexistir com a causa de cancelamento posterior (ex.: COST_RISK);
// - executed incrementa somente no primeiro deal de entrada do signal_id,
//   evitando dupla contagem em fills parciais.
//====================================================================
// Indices fixos para manter relatorios deterministicos.
#define METRIC_123_BUY      0
#define METRIC_123_SELL     1
#define METRIC_ENGULF_BUY   2
#define METRIC_ENGULF_SELL  3
#define METRIC_PFR_BUY      4
#define METRIC_PFR_SELL     5

int GetPatternMetricIndex(const string pattern_name,
                          const ENUM_SIGNAL_DIRECTION direction)
  {
   if(pattern_name == "123")
      return direction == SIGNAL_BUY ? METRIC_123_BUY : METRIC_123_SELL;

   if(pattern_name == "ENG")
      return direction == SIGNAL_BUY ? METRIC_ENGULF_BUY : METRIC_ENGULF_SELL;

   if(pattern_name == "PFR")
      return direction == SIGNAL_BUY ? METRIC_PFR_BUY : METRIC_PFR_SELL;

   return -1;
  }

string PatternMetricLabel(const int index)
  {
   switch(index)
     {
      case METRIC_123_BUY:     return "123_BUY";
      case METRIC_123_SELL:    return "123_SELL";
      case METRIC_ENGULF_BUY:  return "ENGULF_BUY";
      case METRIC_ENGULF_SELL: return "ENGULF_SELL";
      case METRIC_PFR_BUY:     return "PFR_BUY";
      case METRIC_PFR_SELL:    return "PFR_SELL";
      default:                 return "UNKNOWN";
     }
  }

void IncrementPatternSignal(const string pattern_name,
                            const ENUM_SIGNAL_DIRECTION direction)
  {
   const int index = GetPatternMetricIndex(pattern_name, direction);
   if(index >= 0)
      g_pattern_metrics[index].signals++;
  }

void IncrementPatternRejection(const string pattern_name,
                               const ENUM_SIGNAL_DIRECTION direction,
                               const string counter_name)
  {
   const int index = GetPatternMetricIndex(pattern_name, direction);
   if(index < 0)
      return;

   if(counter_name == "COST_RISK")
      g_pattern_metrics[index].rejected_cost++;
   else if(counter_name == "SPREAD")
      g_pattern_metrics[index].rejected_spread++;
   else if(counter_name == "STOP")
      g_pattern_metrics[index].rejected_stop++;
  }

void IncrementPatternPendingNotFilled(const string pattern_name,
                                      const ENUM_SIGNAL_DIRECTION direction)
  {
   const int index = GetPatternMetricIndex(pattern_name, direction);
   if(index >= 0)
      g_pattern_metrics[index].pending_not_filled++;
  }

void IncrementPatternExecuted(const string pattern_name,
                              const ENUM_SIGNAL_DIRECTION direction)
  {
   const int index = GetPatternMetricIndex(pattern_name, direction);
   if(index >= 0)
      g_pattern_metrics[index].executed++;
  }

void FinalizePatternTradeResult(const string pattern_name,
                                const ENUM_SIGNAL_DIRECTION direction,
                                const double net_profit)
  {
   const int index = GetPatternMetricIndex(pattern_name, direction);
   if(index < 0)
      return;

   g_pattern_metrics[index].net_profit += net_profit;

   if(net_profit > 1e-8)
      g_pattern_metrics[index].wins++;
   else if(net_profit < -1e-8)
      g_pattern_metrics[index].losses++;
  }

void LogPatternMetricsSummary(const string event_name)
  {
   for(int i = 0; i < 6; i++)
     {
      g_logger.Info(
         event_name,
         _Symbol,
         "",
         StringFormat(
            "bucket=%s signals=%I64u rejected_cost=%I64u rejected_spread=%I64u "
            "rejected_stop=%I64u pending_not_filled=%I64u executed=%I64u "
            "wins=%I64u losses=%I64u net_profit=%.2f",
            PatternMetricLabel(i),
            g_pattern_metrics[i].signals,
            g_pattern_metrics[i].rejected_cost,
            g_pattern_metrics[i].rejected_spread,
            g_pattern_metrics[i].rejected_stop,
            g_pattern_metrics[i].pending_not_filled,
            g_pattern_metrics[i].executed,
            g_pattern_metrics[i].wins,
            g_pattern_metrics[i].losses,
            g_pattern_metrics[i].net_profit
         )
      );
     }
  }

void LogFunnelSummary(const string event_name)
  {
   g_logger.Info(
      event_name,
      _Symbol,
      "",
      StringFormat(
         "signals_detected=%I64u rejected_cost_risk=%I64u rejected_spread=%I64u "
         "rejected_stop=%I64u rejected_kill_time=%I64u rejected_weekend=%I64u "
         "pending_not_filled=%I64u executed=%I64u",
         g_funnel.signals_detected,
         g_funnel.rejected_cost_risk,
         g_funnel.rejected_spread,
         g_funnel.rejected_stop,
         g_funnel.rejected_kill_time,
         g_funnel.rejected_weekend,
         g_funnel.pending_not_filled,
         g_funnel.executed
      )
   );
  }

void CountSignalDetected(const string signal_id,
                         const string pattern_name,
                         const ENUM_SIGNAL_DIRECTION direction)
  {
   g_funnel.signals_detected++;
   IncrementPatternSignal(pattern_name, direction);
   g_logger.Info(
      "COUNTER_SIGNAL_DETECTED",
      _Symbol,
      signal_id,
      StringFormat("signals_detected=%I64u", g_funnel.signals_detected)
   );
  }

void CountRejection(const string counter_name,
                    const string signal_id,
                    const string detail,
                    const string pattern_name,
                    const ENUM_SIGNAL_DIRECTION direction)
  {
   if(counter_name == "COST_RISK")
      g_funnel.rejected_cost_risk++;
   else if(counter_name == "SPREAD")
      g_funnel.rejected_spread++;
   else if(counter_name == "STOP")
      g_funnel.rejected_stop++;
   else if(counter_name == "KILL_TIME")
      g_funnel.rejected_kill_time++;
   else if(counter_name == "WEEKEND")
      g_funnel.rejected_weekend++;
   else
      return;

   // Metricas segmentadas solicitadas abrangem custos, spread e stop.
   // Kill time/weekend permanecem no funil global, sem contaminar a leitura
   // de qualidade operacional de cada padrao/direcao.
   IncrementPatternRejection(pattern_name, direction, counter_name);

   g_logger.Info(
      "COUNTER_REJECTION",
      _Symbol,
      signal_id,
      StringFormat("cause=%s detalhe=%s", counter_name, detail)
   );
  }

bool IsCostRiskRejectionMessage(const string message)
  {
   return(
      StringFind(message, "Custo round trip") >= 0 ||
      StringFind(message, "Custo estimado") >= 0
   );
  }

bool IsSpreadRejectionMessage(const string message)
  {
   return(
      StringFind(message, "Spread elevado") >= 0 ||
      StringFind(message, "Spread no envio elevado") >= 0 ||
      StringFind(message, "Spread aumentou entre sizing e envio") >= 0
   );
  }

bool IsStopRejectionMessage(const string message)
  {
   return(
      StringFind(message, "Stop abaixo do minimo") >= 0 ||
      StringFind(message, "Stop/spread inseguro") >= 0 ||
      StringFind(message, "entrada/stop") >= 0 ||
      StringFind(message, "Entrada ou stop preparados") >= 0
   );
  }

void CountPendingNotFilledIfApplicable(const string detail)
  {
   if(!g_trade_audit.active ||
      g_trade_audit.pending_not_filled_counted ||
      g_trade_audit.volume_executed > 0.0)
      return;

   g_trade_audit.pending_not_filled_counted = true;
   g_funnel.pending_not_filled++;
   IncrementPatternPendingNotFilled(g_trade_audit.pattern_name, g_trade_audit.direction);
   g_logger.Info(
      "COUNTER_PENDING_NOT_FILLED",
      _Symbol,
      g_trade_audit.signal_id,
      StringFormat(
         "pending_not_filled=%I64u detalhe=%s",
         g_funnel.pending_not_filled,
         detail
      )
   );
  }

string CancelReasonToString(const ENUM_EA_CANCEL_REASON reason)
  {
   switch(reason)
     {
      case CANCEL_SPREAD:     return "CANCEL_SPREAD";
      case CANCEL_KILL_TIME:  return "CANCEL_KILL_TIME";
      case CANCEL_ROLLOVER:   return "CANCEL_ROLLOVER";
      case CANCEL_WEEKEND:    return "CANCEL_WEEKEND";
      case CANCEL_EXPIRATION: return "CANCEL_EXPIRATION";
      case CANCEL_RISK:       return "CANCEL_RISK";
      default:                return "CANCEL_NONE";
     }
  }

void ResetActiveContext(void)
  {
   ZeroMemory(g_active_prepared);
   ZeroMemory(g_active_risk);
   ZeroMemory(g_trade_audit);
   g_has_active_context = false;
  }

void LogAuditSnapshot(const string event_name,
                      const string detail)
  {
   if(!g_trade_audit.active)
      return;

   g_logger.Info(
      event_name,
      _Symbol,
      g_trade_audit.signal_id,
      StringFormat(
         "padrao=%s direcao=%s spread_sinal=%.2f spread_envio=%.2f spread_max_pendente=%.2f "
         "technical_entry=%.*f normalized_entry=%.*f requested_price=%.*f executed_price=%.*f "
         "slippage=%.2fpts stop=%.2fpts custo_estimado=%.2f custo_realizado=%.2f "
         "risco_planejado=%.2f risco_real=%.2f cancel=%s detalhe=%s",
         g_trade_audit.pattern_name,
         DirectionToString(g_trade_audit.direction),
         g_trade_audit.spread_signal_points,
         g_trade_audit.spread_send_points,
         g_trade_audit.spread_max_pending_points,
         _Digits,
         g_trade_audit.technical_entry_price,
         _Digits,
         g_trade_audit.normalized_entry_price,
         _Digits,
         g_trade_audit.requested_price,
         _Digits,
         g_trade_audit.executed_price,
         g_trade_audit.slippage_points,
         g_trade_audit.stop_points,
         g_trade_audit.estimated_cost,
         g_trade_audit.realized_cost,
         g_trade_audit.planned_risk,
         g_trade_audit.real_risk,
         CancelReasonToString(g_trade_audit.cancel_reason),
         detail
      )
   );
  }

bool CancelPendingWithReason(const ENUM_EA_CANCEL_REASON reason,
                             const string detail)
  {
   OperationResult cancel_result = {};
   if(!g_execution_manager.CancelAllPendingOrders(cancel_result))
     {
      g_logger.Warning(
         "CANCEL_REJECTED",
         _Symbol,
         g_trade_audit.active ? g_trade_audit.signal_id : "",
         StringFormat(
            "motivo=%s detalhe=%s erro=%s",
            CancelReasonToString(reason),
            detail,
            cancel_result.message
         )
      );
      return false;
     }

   // Nao gera evento de cancelamento quando nao havia ordem.
   if(StringFind(cancel_result.message, "0 ordem") == 0 ||
      StringFind(cancel_result.message, "Nenhuma") == 0)
      return true;

   if(g_trade_audit.active)
     {
      g_trade_audit.cancel_reason = reason;
      g_trade_audit.cancel_detail = detail;

      // Uma ordem que chegou a ser aceita, mas terminou sem fill, entra no
      // contador de pending_not_filled independentemente da causa final.
      CountPendingNotFilledIfApplicable(detail);

      // Rejeicoes durante a vida da ordem pendente tambem precisam manter
      // a causa original do descarte. So contamos se ainda nao houve fill.
      if(g_trade_audit.volume_executed <= 0.0)
        {
         if(reason == CANCEL_RISK && StringFind(detail, "custo/risco") >= 0)
            CountRejection("COST_RISK", g_trade_audit.signal_id, detail, g_trade_audit.pattern_name, g_trade_audit.direction);
         else if(reason == CANCEL_KILL_TIME)
            CountRejection("KILL_TIME", g_trade_audit.signal_id, detail, g_trade_audit.pattern_name, g_trade_audit.direction);
         else if(reason == CANCEL_WEEKEND)
            CountRejection("WEEKEND", g_trade_audit.signal_id, detail, g_trade_audit.pattern_name, g_trade_audit.direction);
         else if(reason == CANCEL_SPREAD)
           {
            // Se o spread absoluto excedeu o maximo, a causa principal e
            // SPREAD. Caso contrario, a eliminacao veio da relacao stop/spread.
            if(StringFind(detail, "spread=") >= 0 &&
               StringFind(detail, "stop/spread=") >= 0)
              {
               // O detalhe e produzido por ProcessPendingProtection. Usa a
               // presenca de 'max=' e o valor corrente para manter prioridade
               // causal no ponto de decisao. Como ambos podem falhar juntos,
               // SPREAD tem prioridade quando excede o limite absoluto.
               double current_spread = 0.0;
               double current_spread_points = 0.0;
               string current_spread_error = "";
               if(g_execution_manager.GetCurrentSpread(
                     current_spread,
                     current_spread_points,
                     current_spread_error
                  ) &&
                  InpMaxSpreadPoints > 0.0 &&
                  current_spread_points > InpMaxSpreadPoints + 1e-9)
                 {
                  CountRejection("SPREAD", g_trade_audit.signal_id, detail, g_trade_audit.pattern_name, g_trade_audit.direction);
                 }
               else
                 {
                  CountRejection("STOP", g_trade_audit.signal_id, detail, g_trade_audit.pattern_name, g_trade_audit.direction);
                 }
              }
            else
              {
               CountRejection("SPREAD", g_trade_audit.signal_id, detail, g_trade_audit.pattern_name, g_trade_audit.direction);
              }
           }
        }

      LogAuditSnapshot(CancelReasonToString(reason), detail);
     }
   else
     {
      g_logger.Info(
         CancelReasonToString(reason),
         _Symbol,
         "",
         detail
      );
     }

   // Em uma ordem apenas pendente o contexto pode ser descartado. Em fill
   // parcial/transitorio, preserva a auditoria da posicao ja aberta.
   const bool has_open_position =
      g_ea_state == EA_STATE_POSITION_OPEN || g_position_ticket > 0;

   if(!has_open_position)
      ResetActiveContext();

   if(g_ea_state != EA_STATE_ERROR)
      ReconcileState();

   return true;
  }

//====================================================================
// Protecoes de horario
// Executadas no primeiro tick de cada minuto. O OnTimer de 10 s existe
// apenas como fallback quando o mercado fica sem ticks.
//====================================================================
void ProcessSafetyControls(const bool force_execution)
  {
   const datetime server_time = GetBrokerServerTime();
   if(server_time <= 0)
      return;

   const datetime minute_stamp = (datetime)(
      (long)server_time - ((long)server_time % 60)
   );

   if(!force_execution && minute_stamp == g_last_safety_minute)
      return;

   g_last_safety_minute = minute_stamp;

   // Fim de semana tem prioridade sobre as demais janelas.
   if(g_trading_schedule.ShouldForceWeekendFlat(server_time))
     {
      CancelPendingWithReason(
         CANCEL_WEEKEND,
         "Protecao de fim de semana: cancelamento preventivo de pendentes."
      );

      OperationResult close_result = {};
      if(!g_execution_manager.CloseAllOwnPositions(
            "WEEKEND_EXIT",
            close_result
         ))
        {
         g_logger.Warning(
            "WEEKEND_CLOSE_REJECTED",
            _Symbol,
            g_trade_audit.active ? g_trade_audit.signal_id : "",
            close_result.message
         );
        }
      else if(StringFind(close_result.message, "0 posicao") != 0)
        {
         g_logger.Info(
            "WEEKEND_POSITION_CLOSE_SENT",
            _Symbol,
            g_trade_audit.active ? g_trade_audit.signal_id : "",
            close_result.message
         );
        }

      if(g_ea_state != EA_STATE_ERROR)
         ReconcileState();
      return;
     }

   if(g_trading_schedule.IsRolloverProtectionWindow(server_time))
     {
      CancelPendingWithReason(
         CANCEL_ROLLOVER,
         "Janela preventiva anterior ao rollover."
      );
     }
   else
     {
      string kill_reason = "";
      if(g_trading_schedule.IsKillTime(server_time, kill_reason))
        {
         CancelPendingWithReason(
            CANCEL_KILL_TIME,
            kill_reason
         );
        }
     }

   if(g_ea_state != EA_STATE_ERROR)
      ReconcileState();
  }

//====================================================================
// Protecao de ordem pendente por tick
//
// Esta rotina e chamada em TODO OnTick enquanto ha ordem pendente.
// O watchdog OnTimer executa a mesma rotina somente como fallback.
//====================================================================
void ProcessPendingProtection(void)
  {
   if(g_ea_state != EA_STATE_ORDER_PENDING)
      return;

   double spread_price = 0.0;
   double spread_points = 0.0;
   string spread_error = "";

   if(!g_execution_manager.GetCurrentSpread(
         spread_price,
         spread_points,
         spread_error
      ))
     {
      g_logger.Warning(
         "SPREAD_PROTECTION_ERROR",
         _Symbol,
         g_trade_audit.active ? g_trade_audit.signal_id : "",
         spread_error
      );
      return;
     }

   if(g_trade_audit.active)
     {
      g_trade_audit.spread_max_pending_points = MathMax(
         g_trade_audit.spread_max_pending_points,
         spread_points
      );
     }

   // Em caso de reinicio, o contexto detalhado pode nao estar em memoria.
   // O filtro legado ainda protege a ordem por spread como fallback.
   if(!g_has_active_context)
     {
      OperationResult fallback_result = {};
      if(!g_execution_manager.CancelPendingOrdersWithUnsafeSpread(
            fallback_result
         ))
        {
         g_logger.Warning(
            "SPREAD_PROTECTION_ERROR",
            _Symbol,
            "",
            fallback_result.message
         );
         return;
        }

      if(StringFind(fallback_result.message, "Nenhuma") != 0)
         g_logger.Info("CANCEL_SPREAD", _Symbol, "", fallback_result.message);

      if(g_ea_state != EA_STATE_ERROR)
         ReconcileState();
      return;
     }

   const double risk_distance = MathAbs(
      g_active_prepared.submitted_entry_price -
      g_active_prepared.submitted_stop_price
   );

   const double current_stop_spread_ratio =
      spread_price > 0.0 ? risk_distance / spread_price : 0.0;

   const bool spread_above_maximum =
      InpMaxSpreadPoints > 0.0 &&
      spread_points > InpMaxSpreadPoints + 1e-9;

   const bool stop_spread_unsafe =
      InpMinStopSpreadMultiple > 0.0 &&
      current_stop_spread_ratio + 1e-9 < InpMinStopSpreadMultiple;

   if(spread_above_maximum || stop_spread_unsafe)
     {
      CancelPendingWithReason(
         CANCEL_SPREAD,
         StringFormat(
            "spread=%.2fpts max=%.2fpts stop/spread=%.2fx minimo=%.2fx",
            spread_points,
            InpMaxSpreadPoints,
            current_stop_spread_ratio,
            InpMinStopSpreadMultiple
         )
      );
      return;
     }

   // Recalcula o peso dos custos com o spread corrente. O volume nao e
   // aumentado; a ordem e cancelada quando os custos excedem a tolerancia.
   double cost_risk_percent = 0.0;
   double current_estimated_cost = 0.0;
   string risk_error = "";

   if(!g_risk_manager.CalculatePendingCostRiskPercent(
         _Symbol,
         g_active_prepared,
         g_active_risk.volume,
         spread_price,
         cost_risk_percent,
         current_estimated_cost,
         risk_error
      ))
     {
      g_logger.Warning(
         "PENDING_RISK_REVALIDATION_ERROR",
         _Symbol,
         g_trade_audit.signal_id,
         risk_error
      );
      return;
     }

   if(InpMaxRoundTripCostRiskPercent > 0.0 &&
      cost_risk_percent > InpMaxRoundTripCostRiskPercent + 1e-9)
     {
      CancelPendingWithReason(
         CANCEL_RISK,
         StringFormat(
            "custo/risco=%.2f%% max=%.2f%% custo_atual=%.2f",
            cost_risk_percent,
            InpMaxRoundTripCostRiskPercent,
            current_estimated_cost
         )
      );
     }
  }

int OnInit(void)
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_logger.Configure(InpLogDetails);

   g_trading_schedule.Configure(
      InpKillTime1Enabled,
      InpKillTime1StartHour,
      InpKillTime1StartMinute,
      InpKillTime1EndHour,
      InpKillTime1EndMinute,
      InpKillTime2Enabled,
      InpKillTime2StartHour,
      InpKillTime2StartMinute,
      InpKillTime2EndHour,
      InpKillTime2EndMinute,
      InpCancelBeforeRollover,
      InpRolloverHour,
      InpRolloverMinute,
      InpRolloverCancelLeadMinutes,
      InpAvoidWeekend,
      InpFridayExitHour,
      InpFridayExitMinute,
      InpMondayResumeHour,
      InpMondayResumeMinute
   );

   string market_error = "";
   const bool is_tester = (bool)MQLInfoInteger(MQL_TESTER);

   // Oculta os handles internos para evitar tres EMAs com a cor padrao.
   if(is_tester)
      TesterHideIndicators(true);

   const bool market_initialized = g_market_data.Initialize(
      _Symbol,
      (ENUM_TIMEFRAMES)_Period,
      InpEMA21Period,
      InpEMA40Period,
      InpEMA80Period,
      InpATRPeriod,
      market_error
   );

   if(is_tester)
      TesterHideIndicators(false);

   if(!market_initialized)
     {
      g_logger.Error("MARKET_DATA_ERROR", _Symbol, "", market_error);
      return INIT_FAILED;
     }

   string visual_error = "";
   if(!InitializeVisualIndicator(visual_error))
     {
      g_logger.Warning(
         "VISUAL_INDICATOR_ERROR",
         _Symbol,
         "",
         visual_error
      );
     }

   g_strategy.Configure(
      InpUse123,
      InpUsePFR,
      InpUseEngulfing,
      InpPatternPriority1,
      InpPatternPriority2,
      InpPatternPriority3,
      InpTradeDirection,
      InpTargetR,
      InpRiskPercent
   );

   g_execution_manager.Configure(
      _Symbol,
      InpMagicNumber,
      InpDeviationPoints,
      InpLogDetails,
      InpMaxSpreadPoints,
      InpMinStopSpreadMultiple,
      InpMinStopPointsAbsolute,
      InpMinStopATRMultiple
   );

   g_risk_manager.Configure(
      InpMaxRoundTripCostRiskPercent,
      InpMaxVolumeLots,
      InpEstimatedRoundTripCommissionPerLot,
      InpRoundTripSlippageReservePoints
   );

   g_last_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(g_last_bar_time <= 0)
     {
      ReleaseVisualIndicator();
      g_market_data.Release();
      return INIT_FAILED;
     }

   OperationResult expiration_result = {};
   if(!g_execution_manager.CancelExpiredPendingOrders(
         g_last_bar_time,
         expiration_result
      ))
     {
      g_logger.Warning(
         "CANCEL_REJECTED",
         _Symbol,
         "",
         StringFormat("motivo=CANCEL_EXPIRATION erro=%s", expiration_result.message)
      );
     }

   if(expiration_result.message != "Nenhuma ordem vencida.")
     {
      g_logger.Info(
         "CANCEL_EXPIRATION",
         _Symbol,
         "",
         expiration_result.message
      );
     }

   if(!ReconcileState())
     {
      ReleaseVisualIndicator();
      g_market_data.Release();
      return INIT_FAILED;
     }

   ProcessSafetyControls(true);

   ResetLastError();
   if(!EventSetTimer(InpSafetyTimerSeconds))
     {
      g_logger.Error(
         "TIMER_ERROR",
         _Symbol,
         "",
         StringFormat("EventSetTimer(%d) falhou. erro=%d", InpSafetyTimerSeconds, GetLastError())
      );
      ReleaseVisualIndicator();
      g_market_data.Release();
      return INIT_FAILED;
     }

   ZeroMemory(g_funnel);
   for(int metric_index = 0; metric_index < 6; metric_index++)
      ZeroMemory(g_pattern_metrics[metric_index]);

   g_logger.Info(
      "EA_INITIALIZED",
      _Symbol,
      "",
      StringFormat(
         "estado=%d magic=%I64u timeframe=%s alvo=%.2fR max_spread=%.2f stop_spread=%.2fx "
         "min_stop_abs=%.2f ATR=%d x %.2f max_custo_risco=%.2f%% max_lote=%.2f "
         "tolerancia_risco_real=%.2f%% watchdog=%ds",
         (int)g_ea_state,
         InpMagicNumber,
         EnumToString((ENUM_TIMEFRAMES)_Period),
         InpTargetR,
         InpMaxSpreadPoints,
         InpMinStopSpreadMultiple,
         InpMinStopPointsAbsolute,
         InpATRPeriod,
         InpMinStopATRMultiple,
         InpMaxRoundTripCostRiskPercent,
         InpMaxVolumeLots,
         InpMaxRealRiskOverPlanPercent,
         InpSafetyTimerSeconds
      )
   );

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   LogFunnelSummary("FUNNEL_SUMMARY_FINAL");
   LogPatternMetricsSummary("PATTERN_DIRECTION_SUMMARY_FINAL");

   EventKillTimer();
   ReleaseVisualIndicator();
   g_market_data.Release();

   g_logger.Info(
      "EA_DEINITIALIZED",
      _Symbol,
      "",
      StringFormat("motivo=%d", reason)
   );
  }

void ProcessIdleState(void)
  {
   // A estrategia e avaliada antes do filtro de horario para que o funil
   // consiga medir sinais que EXISTIAM, mas foram rejeitados por kill time
   // ou fim de semana. Isto nao altera a decisao operacional: nenhuma ordem
   // e enviada enquanto o horario estiver bloqueado.
   if(g_execution_manager.HasAnyTradingActivityForSymbol())
     {
      g_logger.Info(
         "SYMBOL_BUSY",
         _Symbol,
         "",
         "Existe ordem ou posicao no simbolo; nova entrada bloqueada."
      );
      return;
     }

   MarketSnapshot snapshot = {};
   string market_error = "";

   if(!g_market_data.LoadSnapshot(snapshot, market_error))
     {
      g_logger.Warning("MARKET_DATA_ERROR", _Symbol, "", market_error);
      return;
     }

   TradePlan plan = {};
   string strategy_error = "";

   if(!g_strategy.Evaluate(snapshot, plan, strategy_error))
     {
      if(strategy_error != "")
         g_logger.Warning("SIGNAL_REJECTED", _Symbol, "", strategy_error);
      return;
     }

   if(plan.signal_id == g_last_processed_signal_id)
      return;

   g_last_processed_signal_id = plan.signal_id;
   CountSignalDetected(plan.signal_id, plan.pattern_name, plan.direction);

   string schedule_reason = "";
   const datetime server_time = GetBrokerServerTime();

   string weekend_reason = "";
   if(g_trading_schedule.IsWeekendBlocked(server_time, weekend_reason))
     {
      CountRejection("WEEKEND", plan.signal_id, weekend_reason, plan.pattern_name, plan.direction);
      g_logger.Info("ENTRY_BLOCKED_BY_TIME", _Symbol, plan.signal_id, weekend_reason);
      return;
     }

   string kill_reason = "";
   if(g_trading_schedule.IsKillTime(server_time, kill_reason))
     {
      CountRejection("KILL_TIME", plan.signal_id, kill_reason, plan.pattern_name, plan.direction);
      g_logger.Info("ENTRY_BLOCKED_BY_TIME", _Symbol, plan.signal_id, kill_reason);
      return;
     }

   // Rollover continua bloqueado, mas nao entra nos contadores solicitados.
   if(g_trading_schedule.IsRolloverProtectionWindow(server_time))
     {
      schedule_reason = "Janela preventiva anterior ao rollover.";
      g_logger.Info("ENTRY_BLOCKED_BY_TIME", _Symbol, plan.signal_id, schedule_reason);
      return;
     }

   g_logger.Info(
      "SIGNAL_CREATED",
      _Symbol,
      plan.signal_id,
      StringFormat(
         "direcao=%s padrao=%s alvo=%.2fR spread_sinal=%.2fpts ATR=%.*f entrada_tecnica=%.*f stop_tecnico=%.*f",
         DirectionToString(plan.direction),
         plan.pattern_name,
         plan.target_r,
         plan.signal_spread_points,
         _Digits,
         plan.atr_value,
         _Digits,
         plan.technical_entry_price,
         _Digits,
         plan.technical_stop_price
      )
   );

   PreparedOrder prepared = {};
   OperationResult preparation_result = {};

   if(!g_execution_manager.Prepare(plan, prepared, preparation_result))
     {
      if(IsSpreadRejectionMessage(preparation_result.message))
         CountRejection("SPREAD", plan.signal_id, preparation_result.message, plan.pattern_name, plan.direction);
      else if(IsStopRejectionMessage(preparation_result.message))
         CountRejection("STOP", plan.signal_id, preparation_result.message, plan.pattern_name, plan.direction);

      g_logger.Warning(
         "ORDER_PREPARATION_REJECTED",
         _Symbol,
         plan.signal_id,
         preparation_result.message
      );
      return;
     }

   // Revalida o spread imediatamente antes do sizing. Este valor passa a
   // representar o spread de envio para risco, TP liquido e auditoria.
   OperationResult send_spread_result = {};
   if(!g_execution_manager.RefreshSendSpread(prepared, send_spread_result))
     {
      if(IsSpreadRejectionMessage(send_spread_result.message))
         CountRejection("SPREAD", plan.signal_id, send_spread_result.message, plan.pattern_name, plan.direction);
      else if(IsStopRejectionMessage(send_spread_result.message))
         CountRejection("STOP", plan.signal_id, send_spread_result.message, plan.pattern_name, plan.direction);

      g_logger.Warning(
         "ORDER_PREPARATION_REJECTED",
         _Symbol,
         plan.signal_id,
         send_spread_result.message
      );
      return;
     }

   RiskResult risk_result = {};
   if(!g_risk_manager.Calculate(
         _Symbol,
         prepared,
         plan.risk_percent,
         risk_result
      ))
     {
      if(IsCostRiskRejectionMessage(risk_result.message))
         CountRejection("COST_RISK", plan.signal_id, risk_result.message, plan.pattern_name, plan.direction);

      g_logger.Warning(
         "RISK_REJECTED",
         _Symbol,
         plan.signal_id,
         risk_result.message
      );
      return;
     }

   // O target tecnico da Strategy serve apenas como referencia. O TP enviado
   // e recalculado aqui para entregar TargetR liquido apos custos estimados.
   prepared.submitted_target_price = risk_result.target_price;

   OperationResult target_result = {};
   if(!g_execution_manager.ValidateTarget(prepared, target_result))
     {
      g_logger.Warning(
         "TARGET_REJECTED",
         _Symbol,
         plan.signal_id,
         target_result.message
      );
      return;
     }

   g_active_prepared = prepared;
   g_active_risk = risk_result;
   g_has_active_context = true;

   ZeroMemory(g_trade_audit);
   g_trade_audit.active                    = true;
   g_trade_audit.signal_id                 = plan.signal_id;
   g_trade_audit.pattern_name              = plan.pattern_name;
   g_trade_audit.signal_time               = plan.signal_time;
   g_trade_audit.direction                 = plan.direction;
   g_trade_audit.volume_planned            = risk_result.volume;
   g_trade_audit.spread_signal_points      = plan.signal_spread_points;
   g_trade_audit.spread_send_points        = prepared.send_spread_points;
   g_trade_audit.spread_max_pending_points = prepared.send_spread_points;
   g_trade_audit.technical_entry_price     = plan.technical_entry_price;
   g_trade_audit.normalized_entry_price    = prepared.submitted_entry_price;
   g_trade_audit.requested_price           = prepared.submitted_entry_price;
   g_trade_audit.stop_price                = prepared.submitted_stop_price;
   g_trade_audit.target_price              = prepared.submitted_target_price;
   g_trade_audit.stop_points               = prepared.stop_points;
   g_trade_audit.estimated_cost            = risk_result.estimated_cost;
   g_trade_audit.planned_risk              = risk_result.planned_total_risk;
   g_trade_audit.cancel_reason             = CANCEL_NONE;
   g_trade_audit.cancel_detail             = "";
   g_trade_audit.risk_control_attempted     = false;
   g_trade_audit.execution_counted           = false;
   g_trade_audit.pending_not_filled_counted  = false;

   ExecutionResult execution_result = {};
   if(!g_execution_manager.Submit(
         g_active_prepared,
         risk_result.volume,
         execution_result
      ))
     {
      if(IsSpreadRejectionMessage(execution_result.message))
         CountRejection("SPREAD", plan.signal_id, execution_result.message, plan.pattern_name, plan.direction);
      else if(IsStopRejectionMessage(execution_result.message))
         CountRejection("STOP", plan.signal_id, execution_result.message, plan.pattern_name, plan.direction);

      g_logger.Error(
         "ORDER_REJECTED",
         _Symbol,
         plan.signal_id,
         execution_result.message
      );

      LogAuditSnapshot("SIGNAL_AUDIT_REJECTED", execution_result.message);
      ResetActiveContext();
      ReconcileState();
      return;
     }

   // Captura o preco efetivamente colocado em MqlTradeRequest.price.
   // Para uma ordem pendente ele normalmente coincide com normalized_entry,
   // mas os campos permanecem separados para detectar futuras divergencias.
   g_trade_audit.requested_price = execution_result.requested_price;

   g_ea_state = EA_STATE_ORDER_PENDING;
   g_pending_order_ticket = execution_result.order_ticket;
   g_trade_audit.order_ticket = execution_result.order_ticket;
   g_trade_audit.spread_send_points = g_active_prepared.send_spread_points;
   g_trade_audit.spread_max_pending_points = MathMax(
      g_trade_audit.spread_max_pending_points,
      g_active_prepared.send_spread_points
   );

   g_logger.Info(
      "ORDER_PLACED",
      _Symbol,
      plan.signal_id,
      StringFormat(
         "ticket=%I64u volume=%.8f spread_sinal=%.2f spread_envio=%.2f "
         "stop=%.2fpts min_stop=%.2fpts custo=%.2f custo/risco=%.2f%% "
         "risco_planejado=%.2f alvo=%.2fR alvo_bruto=%.2f "
         "technical_entry=%.*f normalized_entry=%.*f requested_price=%.*f SL=%.*f TP=%.*f",
         execution_result.order_ticket,
         risk_result.volume,
         plan.signal_spread_points,
         g_active_prepared.send_spread_points,
         g_active_prepared.stop_points,
         g_active_prepared.minimum_stop_points_required,
         risk_result.estimated_cost,
         risk_result.round_trip_cost_risk_percent,
         risk_result.planned_total_risk,
         plan.target_r,
         risk_result.gross_target_profit,
         _Digits,
         plan.technical_entry_price,
         _Digits,
         g_active_prepared.submitted_entry_price,
         _Digits,
         execution_result.requested_price,
         _Digits,
         g_active_prepared.submitted_stop_price,
         _Digits,
         g_active_prepared.submitted_target_price
      )
   );
  }

void ProcessNewBar(const datetime current_bar_time)
  {
   if(g_ea_state == EA_STATE_ERROR)
      return;

   OperationResult cancellation_result = {};
   if(!g_execution_manager.CancelExpiredPendingOrders(
         current_bar_time,
         cancellation_result
      ))
     {
      g_logger.Error(
         "CANCEL_REJECTED",
         _Symbol,
         g_trade_audit.active ? g_trade_audit.signal_id : "",
         StringFormat(
            "motivo=CANCEL_EXPIRATION erro=%s",
            cancellation_result.message
         )
      );

      ReconcileState();
      return;
     }

   if(cancellation_result.message != "Nenhuma ordem vencida.")
     {
      if(g_trade_audit.active)
        {
         g_trade_audit.cancel_reason = CANCEL_EXPIRATION;
         g_trade_audit.cancel_detail = cancellation_result.message;
         CountPendingNotFilledIfApplicable(cancellation_result.message);
         LogAuditSnapshot("CANCEL_EXPIRATION", cancellation_result.message);
         ResetActiveContext();
        }
      else
        {
         g_logger.Info(
            "CANCEL_EXPIRATION",
            _Symbol,
            "",
            cancellation_result.message
         );
        }
     }

   if(!ReconcileState())
      return;

   switch(g_ea_state)
     {
      case EA_STATE_IDLE:
         ProcessIdleState();
         break;

      case EA_STATE_ORDER_PENDING:
      case EA_STATE_POSITION_OPEN:
      case EA_STATE_ERROR:
         break;

      default:
         EnterErrorState("Estado do EA desconhecido.");
         break;
     }
  }

double ExplicitDealCost(const ulong deal_ticket)
  {
   if(deal_ticket == 0 || !HistoryDealSelect(deal_ticket))
      return 0.0;

   const double commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   const double fee        = HistoryDealGetDouble(deal_ticket, DEAL_FEE);
   const double swap       = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);

   // Valores negativos representam custo. Swap positivo reduz custo.
   return MathMax(0.0, -(commission + fee + swap));
  }

// Atualiza a auditoria a partir dos deals reais. A confirmacao de execucao
// continua sendo dirigida pelo OnTradeTransaction, nunca pelo retorno local
// de OrderSend.
void ProcessDealAudit(const MqlTradeTransaction &transaction)
  {
   if(transaction.type != TRADE_TRANSACTION_DEAL_ADD || transaction.deal == 0)
      return;

   if(!HistoryDealSelect(transaction.deal))
      return;

   if(HistoryDealGetString(transaction.deal, DEAL_SYMBOL) != _Symbol)
      return;

   if((ulong)HistoryDealGetInteger(transaction.deal, DEAL_MAGIC) != InpMagicNumber)
      return;

   if(!g_trade_audit.active)
      return;

   const ENUM_DEAL_ENTRY deal_entry =
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(transaction.deal, DEAL_ENTRY);

   const ENUM_DEAL_REASON deal_reason =
      (ENUM_DEAL_REASON)HistoryDealGetInteger(transaction.deal, DEAL_REASON);

   const double deal_price  = HistoryDealGetDouble(transaction.deal, DEAL_PRICE);
   const double deal_volume = HistoryDealGetDouble(transaction.deal, DEAL_VOLUME);

   if(deal_price <= 0.0 || deal_volume <= 0.0)
      return;

   g_trade_audit.realized_commission_fee += ExplicitDealCost(transaction.deal);

   // Resultado liquido do ciclo da operacao: lucro do deal + custos/swap
   // assinados reportados pelo servidor. E acumulado inclusive em reducoes
   // parciais e finalizado somente quando a posicao deixa de existir.
   g_trade_audit.trade_net_profit +=
      HistoryDealGetDouble(transaction.deal, DEAL_PROFIT) +
      HistoryDealGetDouble(transaction.deal, DEAL_COMMISSION) +
      HistoryDealGetDouble(transaction.deal, DEAL_FEE) +
      HistoryDealGetDouble(transaction.deal, DEAL_SWAP);

   if(deal_entry == DEAL_ENTRY_IN || deal_entry == DEAL_ENTRY_INOUT)
     {
      if(!g_trade_audit.execution_counted)
        {
         g_trade_audit.execution_counted = true;
         g_funnel.executed++;
         IncrementPatternExecuted(g_trade_audit.pattern_name, g_trade_audit.direction);
         g_logger.Info(
            "COUNTER_EXECUTED",
            _Symbol,
            g_trade_audit.signal_id,
            StringFormat("executed=%I64u deal=%I64u", g_funnel.executed, transaction.deal)
         );
        }

      const double old_volume = g_trade_audit.volume_executed;
      const double new_volume = old_volume + deal_volume;

      if(new_volume > 0.0)
        {
         g_trade_audit.executed_price =
            (g_trade_audit.executed_price * old_volume +
             deal_price * deal_volume) / new_volume;
        }

      g_trade_audit.volume_executed = new_volume;
      g_trade_audit.position_ticket = transaction.position;
      g_trade_audit.position_identifier =
         (ulong)HistoryDealGetInteger(transaction.deal, DEAL_POSITION_ID);

      double spread_price = 0.0;
      double spread_points = 0.0;
      string spread_error = "";

      if(g_execution_manager.GetCurrentSpread(
            spread_price,
            spread_points,
            spread_error
         ))
        {
         g_trade_audit.spread_fill_points = spread_points;

         CostEstimate fill_cost = {};
         if(g_risk_manager.EstimateRoundTripCosts(
               _Symbol,
               g_trade_audit.direction,
               deal_price,
               deal_volume,
               spread_price,
               fill_cost
            ))
           {
            // Spread realizado e aproximado pelo spread observado no evento
            // de fill. Comissao/fee vem diretamente do deal do MT5.
            g_trade_audit.realized_spread_cost += fill_cost.spread_total;
           }
        }

      double slippage_cost = 0.0;
      double slippage_points = 0.0;
      string slippage_error = "";

      if(g_risk_manager.CalculateActualSlippageCost(
            _Symbol,
            g_trade_audit.direction,
            g_trade_audit.normalized_entry_price,
            g_trade_audit.executed_price,
            g_trade_audit.volume_executed,
            slippage_cost,
            slippage_points,
            slippage_error
         ))
        {
         g_trade_audit.slippage_points = slippage_points;
         g_trade_audit.realized_slippage_cost = slippage_cost;
        }

      g_trade_audit.realized_cost =
         g_trade_audit.realized_commission_fee +
         g_trade_audit.realized_spread_cost +
         g_trade_audit.realized_slippage_cost;

      g_logger.Info(
         "DEAL_EXECUTED",
         _Symbol,
         g_trade_audit.signal_id,
         StringFormat(
            "bucket=%s deal=%I64u volume=%.8f technical_entry=%.*f normalized_entry=%.*f "
            "requested_price=%.*f executed_price=%.*f spread_fill=%.2fpts slippage=%.2fpts custo_realizado_parcial=%.2f",
            PatternMetricLabel(GetPatternMetricIndex(g_trade_audit.pattern_name, g_trade_audit.direction)),
            transaction.deal,
            deal_volume,
            _Digits,
            g_trade_audit.technical_entry_price,
            _Digits,
            g_trade_audit.normalized_entry_price,
            _Digits,
            g_trade_audit.requested_price,
            _Digits,
            deal_price,
            g_trade_audit.spread_fill_points,
            g_trade_audit.slippage_points,
            g_trade_audit.realized_cost
         )
      );
     }
   else if(deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_OUT_BY)
     {
      // Para saida por SL/TP, mede slippage adverso contra o nivel esperado.
      double expected_exit_price = 0.0;
      if(deal_reason == DEAL_REASON_SL)
         expected_exit_price = g_trade_audit.stop_price;
      else if(deal_reason == DEAL_REASON_TP)
         expected_exit_price = g_trade_audit.target_price;

      if(expected_exit_price > 0.0)
        {
         double exit_slippage_cost = 0.0;
         double exit_slippage_points = 0.0;
         string exit_slippage_error = "";

         if(g_risk_manager.CalculateExitSlippageCost(
               _Symbol,
               g_trade_audit.direction,
               expected_exit_price,
               deal_price,
               deal_volume,
               exit_slippage_cost,
               exit_slippage_points,
               exit_slippage_error
            ))
           {
            g_trade_audit.realized_slippage_cost += exit_slippage_cost;
           }
        }

      g_trade_audit.realized_cost =
         g_trade_audit.realized_commission_fee +
         g_trade_audit.realized_spread_cost +
         g_trade_audit.realized_slippage_cost;
     }
  }

// Recalcula o risco usando o preco efetivamente executado. Quando o risco
// ultrapassa o planejado + tolerancia, reduz ou encerra a posicao conforme
// InpRealRiskAction.
void ProcessRealRiskAfterFill(void)
  {
   if(!g_trade_audit.active ||
      !g_has_active_context ||
      g_ea_state != EA_STATE_POSITION_OPEN ||
      g_trade_audit.executed_price <= 0.0 ||
      g_trade_audit.risk_control_attempted)
      return;

   ENUM_SIGNAL_DIRECTION position_direction = SIGNAL_NONE;
   double position_volume = 0.0;
   double open_price = 0.0;
   double stop_price = 0.0;
   double target_price = 0.0;
   string position_error = "";

   if(!g_execution_manager.GetOwnPosition(
         g_position_ticket,
         position_direction,
         position_volume,
         open_price,
         stop_price,
         target_price,
         position_error
      ))
     {
      g_logger.Warning(
         "REAL_RISK_RECALC_ERROR",
         _Symbol,
         g_trade_audit.signal_id,
         position_error
      );
      return;
     }

   double spread_price = 0.0;
   double spread_points = 0.0;
   string spread_error = "";
   if(!g_execution_manager.GetCurrentSpread(
         spread_price,
         spread_points,
         spread_error
      ))
     {
      g_logger.Warning(
         "REAL_RISK_RECALC_ERROR",
         _Symbol,
         g_trade_audit.signal_id,
         spread_error
      );
      return;
     }

   RealRiskResult real_risk = {};
   if(!g_risk_manager.CalculateRealRisk(
         _Symbol,
         position_direction,
         open_price,
         stop_price,
         position_volume,
         spread_price,
         g_trade_audit.realized_slippage_cost,
         g_trade_audit.planned_risk,
         InpMaxRealRiskOverPlanPercent,
         real_risk
      ))
     {
      g_logger.Warning(
         "REAL_RISK_RECALC_ERROR",
         _Symbol,
         g_trade_audit.signal_id,
         real_risk.message
      );
      return;
     }

   g_trade_audit.real_risk = real_risk.real_risk;

   g_logger.Info(
      "RISK_REAL_RECALCULATED",
      _Symbol,
      g_trade_audit.signal_id,
      StringFormat(
         "preco_solicitado=%.*f preco_normalizado=%.*f preco_executado=%.*f slippage=%.2fpts "
         "risco_planejado=%.2f risco_real=%.2f permitido=%.2f excesso=%.2f%% volume=%.8f volume_seguro=%.8f",
         _Digits,
         g_trade_audit.requested_price,
         _Digits,
         g_trade_audit.normalized_entry_price,
         _Digits,
         open_price,
         g_trade_audit.slippage_points,
         g_trade_audit.planned_risk,
         real_risk.real_risk,
         real_risk.allowed_risk,
         real_risk.excess_percent,
         position_volume,
         real_risk.target_safe_volume
      )
   );

   g_trade_audit.risk_control_attempted = true;

   if(real_risk.real_risk <= real_risk.allowed_risk + 0.01)
      return;

   OperationResult risk_action_result = {};

   if(InpRealRiskAction == EA_REAL_RISK_REDUCE)
     {
      if(!g_execution_manager.ReducePosition(
            g_position_ticket,
            real_risk.target_safe_volume,
            "REAL_RISK_REDUCE",
            risk_action_result
         ))
        {
         EnterErrorState(
            StringFormat(
               "Falha ao reduzir posicao apos excesso de risco: %s",
               risk_action_result.message
            )
         );
         return;
        }

      g_logger.Warning(
         "RISK_POSITION_REDUCE",
         _Symbol,
         g_trade_audit.signal_id,
         risk_action_result.message
      );
     }
   else
     {
      if(!g_execution_manager.ClosePosition(
            g_position_ticket,
            "REAL_RISK_CLOSE",
            risk_action_result
         ))
        {
         EnterErrorState(
            StringFormat(
               "Falha ao fechar posicao apos excesso de risco: %s",
               risk_action_result.message
            )
         );
         return;
        }

      g_logger.Warning(
         "RISK_POSITION_CLOSE",
         _Symbol,
         g_trade_audit.signal_id,
         risk_action_result.message
      );
     }
  }

void OnTick(void)
  {
   // Horarios tem precedencia causal nos logs; em seguida o spread da
   // pendente e revalidado no mesmo tick.
   ProcessSafetyControls(false);
   ProcessPendingProtection();

   const datetime current_bar_time = iTime(
      _Symbol,
      PERIOD_CURRENT,
      0
   );

   if(current_bar_time <= 0 || current_bar_time == g_last_bar_time)
      return;

   g_last_bar_time = current_bar_time;
   ProcessNewBar(current_bar_time);
  }

void OnTimer(void)
  {
   // Watchdog: fallback para periodos sem ticks. O default permanece 10 s.
   ProcessSafetyControls(false);
   ProcessPendingProtection();

   if(g_ea_state != EA_STATE_ERROR)
     {
      ReconcileState();

      // Fill parcial conservador: se apos o watchdog ainda coexistirem
      // posicao e remanescente pendente, cancela o restante para impedir
      // aumento posterior do risco planejado.
      if(g_ea_state == EA_STATE_POSITION_OPEN &&
         g_pending_order_ticket > 0)
        {
         CancelPendingWithReason(
            CANCEL_RISK,
            "Remanescente de ordem apos fill parcial; cancelado para limitar risco."
         );
        }

      ProcessRealRiskAfterFill();
     }
  }

//====================================================================
// Criterio customizado de otimizacao
//
// Prioridades:
// 1) amostra minima de trades;
// 2) Profit Factor;
// 3) Recovery Factor;
// 4) Sharpe Ratio;
// 5) penalidade por drawdown de equity.
//
// Nao usa lucro bruto como criterio principal. Valores extremos sao limitados
// para evitar que PF=DBL_MAX (sem perdas) domine uma amostra pequena.
//====================================================================
double OnTester(void)
  {
   const double trades = TesterStatistics(STAT_TRADES);
   const double profit = TesterStatistics(STAT_PROFIT);
   double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   double recovery_factor = TesterStatistics(STAT_RECOVERY_FACTOR);
   double sharpe_ratio = TesterStatistics(STAT_SHARPE_RATIO);
   double drawdown_percent = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);

   if(!MathIsValidNumber(trades) || trades < 0.0)
      return -1.0e12;

   // Configuracoes com amostra insuficiente ficam abaixo de qualquer passe
   // robusto. O pequeno componente de trades apenas ordena os rejeitados.
   if(InpOptimizationMinTrades > 0 && trades < (double)InpOptimizationMinTrades)
      return -1.0e9 + trades;

   if(!MathIsValidNumber(profit_factor) || profit_factor < 0.0)
      profit_factor = 0.0;
   if(!MathIsValidNumber(recovery_factor))
      recovery_factor = 0.0;
   if(!MathIsValidNumber(sharpe_ratio))
      sharpe_ratio = 0.0;
   if(!MathIsValidNumber(drawdown_percent) || drawdown_percent < 0.0)
      drawdown_percent = 100.0;

   // Caps tornam o criterio estavel diante de divisao por zero/valores
   // estatisticamente extremos em amostras pequenas.
   profit_factor   = MathMin(profit_factor, 10.0);
   recovery_factor = MathMax(-10.0, MathMin(recovery_factor, 10.0));
   sharpe_ratio    = MathMax(-5.0, MathMin(sharpe_ratio, 5.0));
   drawdown_percent = MathMin(drawdown_percent, 100.0);

   const double trade_sample_score = MathLog(1.0 + trades) * 5.0;

   double score =
      profit_factor * 35.0 +
      recovery_factor * 25.0 +
      sharpe_ratio * 20.0 +
      trade_sample_score -
      drawdown_percent * 2.0;

   // Lucro liquido negativo nao deve vencer apenas por ratios isolados.
   if(profit <= 0.0)
      score -= 200.0;

   // Drawdown acima do limite recebe penalidade adicional progressiva.
   if(InpOptimizationMaxDrawdownPercent > 0.0 &&
      drawdown_percent > InpOptimizationMaxDrawdownPercent)
     {
      score -=
         (drawdown_percent - InpOptimizationMaxDrawdownPercent) * 10.0;
     }

   return score;
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_execution_manager.ProcessTransaction(transaction, request, result);
   ProcessDealAudit(transaction);

   // Ordem, deal e posicao sao sempre reconciliados a partir do estado real
   // do terminal. OrderSend/retcode confirmam a solicitacao, nao substituem
   // esta confirmacao assincrona.
   if(g_ea_state != EA_STATE_ERROR)
     {
      ReconcileState();
      ProcessRealRiskAfterFill();
     }

   // Finaliza auditoria apenas quando a posicao realmente deixou de existir.
   if(g_trade_audit.active &&
      g_trade_audit.executed_price > 0.0 &&
      g_ea_state == EA_STATE_IDLE)
     {
      FinalizePatternTradeResult(
         g_trade_audit.pattern_name,
         g_trade_audit.direction,
         g_trade_audit.trade_net_profit
      );

      g_logger.Info(
         "PATTERN_TRADE_RESULT",
         _Symbol,
         g_trade_audit.signal_id,
         StringFormat(
            "bucket=%s net_profit=%.2f",
            PatternMetricLabel(GetPatternMetricIndex(g_trade_audit.pattern_name, g_trade_audit.direction)),
            g_trade_audit.trade_net_profit
         )
      );

      LogAuditSnapshot(
         "SIGNAL_AUDIT_FINAL",
         "Operacao encerrada; resultado liquido e custos consolidados pelos deals observados."
      );
      ResetActiveContext();
     }
  }
//+------------------------------------------------------------------+
