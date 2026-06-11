//+------------------------------------------------------------------+
//| AtrUtils.mqh — ATR helpers                                       |
//+------------------------------------------------------------------+
#ifndef __RLVR_ATR_UTILS_MQH__
#define __RLVR_ATR_UTILS_MQH__

double RLVR_GetAtr(const string symbol,
                   const ENUM_TIMEFRAMES tf,
                   const int period,
                   const int shift = 1)
  {
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
     {
      IndicatorRelease(handle);
      return 0.0;
     }
   IndicatorRelease(handle);
   return buffer[0];
  }

#endif
