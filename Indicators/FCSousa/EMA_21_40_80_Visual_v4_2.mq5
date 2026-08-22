//+------------------------------------------------------------------+
//|                                  EMA_21_40_80_Visual_v4_2.mq5     |
//| Indicador visual complementar do EA_EMA_Padroes_1R_v4_2           |
//+------------------------------------------------------------------+
#property strict
#property version   "4.20"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "EMA 21"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "EMA 40"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "EMA 80"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

input int InpEMA21Period = 21;
input int InpEMA40Period = 40;
input int InpEMA80Period = 80;

double g_ema_21_buffer[];
double g_ema_40_buffer[];
double g_ema_80_buffer[];

int g_ema_21_handle = INVALID_HANDLE;
int g_ema_40_handle = INVALID_HANDLE;
int g_ema_80_handle = INVALID_HANDLE;
int g_bars_calculated = 0;

void ReleaseHandles(void)
  {
   if(g_ema_21_handle != INVALID_HANDLE)
     {
      IndicatorRelease(g_ema_21_handle);
      g_ema_21_handle = INVALID_HANDLE;
     }

   if(g_ema_40_handle != INVALID_HANDLE)
     {
      IndicatorRelease(g_ema_40_handle);
      g_ema_40_handle = INVALID_HANDLE;
     }

   if(g_ema_80_handle != INVALID_HANDLE)
     {
      IndicatorRelease(g_ema_80_handle);
      g_ema_80_handle = INVALID_HANDLE;
     }
  }

int OnInit(void)
  {
   if(InpEMA21Period <= 0 ||
      InpEMA40Period <= InpEMA21Period ||
      InpEMA80Period <= InpEMA40Period)
     {
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0, g_ema_21_buffer, INDICATOR_DATA);
   SetIndexBuffer(1, g_ema_40_buffer, INDICATOR_DATA);
   SetIndexBuffer(2, g_ema_80_buffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpEMA21Period - 1);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpEMA40Period - 1);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpEMA80Period - 1);

   IndicatorSetString(
      INDICATOR_SHORTNAME,
      StringFormat(
         "EMA 21/40/80 (%d,%d,%d)",
         InpEMA21Period,
         InpEMA40Period,
         InpEMA80Period
      )
   );
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   g_ema_21_handle = iMA(
      _Symbol,
      PERIOD_CURRENT,
      InpEMA21Period,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   g_ema_40_handle = iMA(
      _Symbol,
      PERIOD_CURRENT,
      InpEMA40Period,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   g_ema_80_handle = iMA(
      _Symbol,
      PERIOD_CURRENT,
      InpEMA80Period,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   if(g_ema_21_handle == INVALID_HANDLE ||
      g_ema_40_handle == INVALID_HANDLE ||
      g_ema_80_handle == INVALID_HANDLE)
     {
      PrintFormat(
         "Falha ao criar handles das EMAs. erro=%d",
         GetLastError()
      );

      ReleaseHandles();
      return INIT_FAILED;
     }

   return INIT_SUCCEEDED;
  }

bool FillBuffer(double &buffer[],
                const int handle,
                const int amount)
  {
   ResetLastError();
   const int copied = CopyBuffer(handle, 0, 0, amount, buffer);

   if(copied != amount)
     {
      PrintFormat(
         "CopyBuffer incompleto. esperado=%d recebido=%d erro=%d",
         amount,
         copied,
         GetLastError()
      );

      return false;
     }

   return true;
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpEMA80Period)
      return 0;

   const int calculated_21 = BarsCalculated(g_ema_21_handle);
   const int calculated_40 = BarsCalculated(g_ema_40_handle);
   const int calculated_80 = BarsCalculated(g_ema_80_handle);

   if(calculated_21 <= 0 || calculated_40 <= 0 || calculated_80 <= 0)
      return 0;

   int calculated = calculated_21;
   if(calculated_40 < calculated)
      calculated = calculated_40;
   if(calculated_80 < calculated)
      calculated = calculated_80;

   int values_to_copy = 0;

   if(prev_calculated == 0 ||
      calculated != g_bars_calculated ||
      rates_total > prev_calculated + 1)
     {
      values_to_copy = (calculated < rates_total ? calculated : rates_total);
     }
   else
     {
      values_to_copy = (rates_total - prev_calculated) + 1;
     }

   if(values_to_copy <= 0)
      return prev_calculated;

   if(!FillBuffer(g_ema_21_buffer, g_ema_21_handle, values_to_copy) ||
      !FillBuffer(g_ema_40_buffer, g_ema_40_handle, values_to_copy) ||
      !FillBuffer(g_ema_80_buffer, g_ema_80_handle, values_to_copy))
     {
      return 0;
     }

   g_bars_calculated = calculated;
   return rates_total;
  }

void OnDeinit(const int reason)
  {
   ReleaseHandles();
  }
//+------------------------------------------------------------------+
