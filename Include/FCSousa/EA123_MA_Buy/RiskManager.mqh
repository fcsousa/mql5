#ifndef FCSOUSA_EA123_MA_BUY_RISK_MANAGER_MQH
#define FCSOUSA_EA123_MA_BUY_RISK_MANAGER_MQH

#include <FCSousa/EA123_MA_Buy/Types.mqh>

class CRiskManager
{
private:
   int VolumeDigits(const double volume_step) const
   {
      for(int digits = 0; digits <= 8; ++digits)
      {
         if(MathAbs(
            volume_step - NormalizeDouble(volume_step, digits)
         ) < 1e-10)
         {
            return digits;
         }
      }

      return 8;
   }

public:
   bool CalculateVolume(
      const string symbol,
      const double entry_price,
      const double stop_price,
      const double risk_percent,
      double &volume,
      double &risk_amount,
      string &error
   ) const
   {
      volume      = 0.0;
      risk_amount = 0.0;
      error       = "";

      if(risk_percent <= 0.0 || risk_percent > 100.0)
      {
         error = "Percentual de risco fora do intervalo (0, 100].";
         return false;
      }

      if(entry_price <= stop_price)
      {
         error = "Entrada deve ser maior que o stop em operação de compra.";
         return false;
      }

      const double balance =
         AccountInfoDouble(ACCOUNT_BALANCE);

      if(balance <= 0.0)
      {
         error = "ACCOUNT_BALANCE inválido.";
         return false;
      }

      risk_amount =
         balance * (risk_percent / 100.0);

      double profit_one_lot = 0.0;

      ResetLastError();

      if(!OrderCalcProfit(
         ORDER_TYPE_BUY,
         symbol,
         1.0,
         entry_price,
         stop_price,
         profit_one_lot
      ))
      {
         error = StringFormat(
            "OrderCalcProfit falhou. erro=%d",
            GetLastError()
         );
         return false;
      }

      const double loss_one_lot =
         MathAbs(profit_one_lot);

      if(loss_one_lot <= 0.0)
      {
         error = "Perda estimada por lote inválida.";
         return false;
      }

      const double volume_min =
         SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      const double volume_max =
         SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

      const double volume_step =
         SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(volume_min <= 0.0 ||
         volume_max <= 0.0 ||
         volume_step <= 0.0)
      {
         error = "Propriedades de volume do símbolo são inválidas.";
         return false;
      }

      const double raw_volume =
         risk_amount / loss_one_lot;

      const double capped_volume =
         MathMin(raw_volume, volume_max);

      const double stepped_volume =
         MathFloor((capped_volume / volume_step) + 1e-12) *
         volume_step;

      const int volume_digits =
         VolumeDigits(volume_step);

      volume =
         NormalizeDouble(stepped_volume, volume_digits);

      if(volume < volume_min - 1e-12)
      {
         error = StringFormat(
            "Volume calculado abaixo do mínimo sem elevar risco. calculado=%.*f mínimo=%.*f",
            volume_digits,
            volume,
            volume_digits,
            volume_min
         );

         volume = 0.0;
         return false;
      }

      if(volume > volume_max + 1e-12)
      {
         error = "Volume calculado excede SYMBOL_VOLUME_MAX.";
         volume = 0.0;
         return false;
      }

      return true;
   }
};

#endif
