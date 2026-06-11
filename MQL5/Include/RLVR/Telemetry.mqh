//+------------------------------------------------------------------+
//| Telemetry.mqh — CSV event log (spec §20)                          |
//+------------------------------------------------------------------+
#ifndef __RLVR_TELEMETRY_MQH__
#define __RLVR_TELEMETRY_MQH__

#include "Types.mqh"

class CRLVRTelemetry
  {
private:
   int      m_handle;
   string   m_filename;
   bool     m_enabled;

public:
            CRLVRTelemetry(): m_handle(INVALID_HANDLE), m_filename(""), m_enabled(false) {}

   bool     Open(const string filename, const bool enabled)
     {
      m_enabled  = enabled;
      m_filename = filename;
      if(!m_enabled)
         return true;

      m_handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(m_handle == INVALID_HANDLE)
        {
         Print("RLVR Telemetry: failed to open ", filename, " err=", GetLastError());
         return false;
        }
      FileWrite(m_handle,
                "timestamp",
                "event_type",
                "level_id",
                "level_price",
                "bar_index",
                "atr_m5",
                "sweep_extreme",
                "void_midpoint",
                "direction",
                "penetration",
                "message");
      return true;
     }

   void     Close()
     {
      if(m_handle != INVALID_HANDLE)
        {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
        }
     }

   void     LogEvent(const SReplayEvent &event)
     {
      if(!m_enabled || m_handle == INVALID_HANDLE)
         return;

      FileWrite(m_handle,
                TimeToString(event.timestamp, TIME_DATE | TIME_SECONDS),
                event.event_type,
                event.level_id,
                DoubleToString(event.level_price, _Digits),
                IntegerToString(event.bar_index),
                DoubleToString(event.atr_m5, _Digits),
                (event.sweep_extreme > 0.0 ? DoubleToString(event.sweep_extreme, _Digits) : ""),
                (event.void_midpoint > 0.0 ? DoubleToString(event.void_midpoint, _Digits) : ""),
                event.direction,
                (event.penetration > 0.0 ? DoubleToString(event.penetration, _Digits) : ""),
                event.message);
      FileFlush(m_handle);
     }

   void     LogPrint(const SReplayEvent &event)
     {
      Print("RLVR|", event.event_type,
            "|", event.level_id,
            "|bar=", event.bar_index,
            "|", event.message);
     }
  };

#endif
