//+------------------------------------------------------------------+
//| TradeUtils.mqh — order helpers                                   |
//+------------------------------------------------------------------+
#ifndef __RLVR_TRADE_UTILS_MQH__
#define __RLVR_TRADE_UTILS_MQH__

#include <Trade/Trade.mqh>
#include "Types.mqh"

class CRLVRTradeUtils
  {
private:
   CTrade    m_trade;
   string    m_symbol;
   ulong     m_magic;
   bool      m_dry_run;

   double TickValuePerLot() const
     {
      const double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0)
         return 0.0;
      return tick_value / tick_size;
     }

public:
   void Init(const string symbol, const ulong magic, const bool dry_run)
     {
      m_symbol  = symbol;
      m_magic   = magic;
      m_dry_run = dry_run;
      m_trade.SetExpertMagicNumber((long)magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFillingBySymbol(symbol);
     }

   double NormalizeLot(const double lots) const
     {
      const double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      const double max_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      const double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(lot_step <= 0.0)
         return lots;
      double normalized = MathFloor(lots / lot_step) * lot_step;
      if(normalized < min_lot)
         normalized = min_lot;
      if(normalized > max_lot)
         normalized = max_lot;
      return normalized;
     }

   bool OpenMarket(const ENUM_RLVR_FADE_DIR direction,
                   const double lots,
                   const string comment,
                   ulong &ticket_out,
                   double &fill_price_out)
     {
      ticket_out     = 0;
      fill_price_out = 0.0;
      const double vol = NormalizeLot(lots);
      if(vol <= 0.0)
         return false;

      if(m_dry_run)
        {
         ticket_out = (ulong)MathRound((double)TimeCurrent() + vol * 1000.0);
         fill_price_out = (direction == RLVR_FADE_BUY)
                          ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(m_symbol, SYMBOL_BID);
         return true;
        }

      bool ok = false;
      if(direction == RLVR_FADE_BUY)
         ok = m_trade.Buy(vol, m_symbol, 0.0, 0.0, 0.0, comment);
      else
         ok = m_trade.Sell(vol, m_symbol, 0.0, 0.0, 0.0, comment);

      if(!ok)
         return false;

      ticket_out     = m_trade.ResultOrder();
      fill_price_out = m_trade.ResultPrice();
      return true;
     }

   bool CloseTicket(const ulong ticket, const double volume)
     {
      if(m_dry_run)
         return true;
      if(!PositionSelectByTicket(ticket))
         return false;
      return m_trade.PositionClose(ticket, volume);
     }

   int CloseAllByMagic(double &closed_volume_out)
     {
      closed_volume_out = 0.0;
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         const ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         const double vol = PositionGetDouble(POSITION_VOLUME);
         if(m_dry_run)
           {
            closed_volume_out += vol;
            closed++;
            continue;
           }
         if(m_trade.PositionClose(ticket))
           {
            closed_volume_out += vol;
            closed++;
           }
        }
      return closed;
     }

   double EstimateLossPerLot(const double price_distance) const
     {
      return price_distance * TickValuePerLot();
     }

   bool IsDryRun() const { return m_dry_run; }
   ulong Magic() const { return m_magic; }
  };

#endif
