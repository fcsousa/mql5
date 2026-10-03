# EA Trend Pullback v1.1

Nova versão do coordenador do EA, preservando a v1.0.

## Alterações principais

- Regime: EMA40 > EMA80 para BUY; EMA40 < EMA80 para SELL.
- Pullback selecionado por `InpPullbackEMA`: EMA21 ou EMA40, nunca ambos na mesma execução.
- Tolerância de pullback: 0.10 ATR por padrão.
- Gatilhos: Engolfo e 123.
- PFR removido do escopo desta versão.
- Entrada: Buy Stop em High[1] + 1 tick; Sell Stop em Low[1] - 1 tick.
- Stop: estrutural da formação, usando o módulo Strategy existente.
- Pending expiration: 3 barras.
- Target: 1.50R.
- Risco: 1.00% do saldo.
- Cost/R máximo: 10%.
- Slope EMA40/ATR opcional e OFF por padrão; quando ligado usa comparação estrita (> limite / < -limite).
- Métricas mantidas por bucket PB21/PB40 + ENG/123 + BUY/SELL.
- Magic Number padrão da v1.1: 214082, para evitar colisão com v1.0.

## Dependências

O EA utiliza os includes já existentes em:

`MQL5/Include/FCSousa/EMA_Trend_Pullback/`

- Types.mqh
- Logger.mqh
- MarketData.mqh
- Strategy.mqh
- RiskManager.mqh
- ExecutionManager.mqh
- TradingSchedule.mqh

## Teste isolado recomendado

Executar uma bateria com `InpPullbackEMA=PULLBACK_EMA_21` e repetir trocando apenas para
`InpPullbackEMA=PULLBACK_EMA_40`.

Para comparar os gatilhos sem sobreposição, executar também baterias separadas:
- Engolfo ON / 123 OFF
- Engolfo OFF / 123 ON
