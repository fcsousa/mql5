# EA EMA6 SMA40 Pattern 1R v1.0

## Regras tecnicas
- Compra: EMA6[1] > SMA40[1], Close[1] > EMA6[1], Close[2] < EMA6[2] e padrao 123/PFR/Engolfo habilitado.
- Venda: condicoes inversas.
- Entrada: Buy Stop em High[1] + 1 tick; Sell Stop em Low[1] - 1 tick.
- Stop: extremo da formacao selecionada. 123/PFR usam candles [1..3]; Engolfo usa [1..2].
- Alvo: `InpTargetR`, padrao 1.0 R, depois dos custos estimados pelo gestor de risco.

## Operacao
O projeto deriva os modulos de risco, execucao, logs estruturados, watchdog de spread, expiracao e protecoes de horario da versao 4.5. O slope opcional usa `(SMA40[1] - SMA40[1+lookback]) / ATR[1]` e somente candles fechados.

## Instalacao
Compile `Experts/FCSousa/EMA6_SMA40_Pattern_1R/EA_EMA6_SMA40_Pattern_1R_v1_0.mq5` no MetaEditor. Aplique o preset inicial em `Presets/EMA6_SMA40_Pattern_1R_default.set`.