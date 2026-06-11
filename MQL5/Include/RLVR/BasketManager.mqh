//+------------------------------------------------------------------+
//| BasketManager.mqh — basket state + position sync                   |
//+------------------------------------------------------------------+
#ifndef __RLVR_BASKET_MANAGER_MQH__
#define __RLVR_BASKET_MANAGER_MQH__

#include "Types.mqh"

class CBasketManager
  {
private:
   string    m_symbol;
   ulong     m_magic;
   SRlvrBasket m_basket;

   void RecomputeAggregates()
     {
      double sum_px_vol = 0.0;
      m_basket.gross_lots = 0.0;
      m_basket.depth      = -1;
      for(int i = 0; i < RLVR_MAX_LEGS; i++)
        {
         if(!m_dry_has_leg[i])
            continue;
         const double lots = m_basket.legs[i].lots;
         if(lots <= 0.0)
            continue;
         sum_px_vol += m_basket.legs[i].open_price * lots;
         m_basket.gross_lots += lots;
         if(i > m_basket.depth)
            m_basket.depth = i;
        }
      if(m_basket.gross_lots > 0.0)
         m_basket.vwap_price = sum_px_vol / m_basket.gross_lots;
      if(m_basket.depth >= 0)
         m_basket.last_fill_price = m_basket.legs[m_basket.depth].open_price;
     }

   bool     m_dry_has_leg[RLVR_MAX_LEGS];

public:
            CBasketManager(): m_symbol(""), m_magic(0)
     {
      RLVR_InitBasket(m_basket);
      ArrayInitialize(m_dry_has_leg, false);
     }

   void Init(const string symbol, const ulong magic)
     {
      m_symbol = symbol;
      m_magic  = magic;
     }

   bool HasActiveBasket() const
     {
      return m_basket.active;
     }

   SRlvrBasket GetBasket() const { return m_basket; }

   void SetState(const ENUM_RLVR_BASKET_STATE state)
     {
      m_basket.state = state;
     }

   void ApplyPartialClose()
     {
      m_basket.partial_done = true;
      m_basket.trail_active = true;
      m_basket.trail_stop   = m_basket.vwap_price;
     }

   void UpdateTrailStop(const double atr_m5, const double trail_buffer_atr)
     {
      if(!m_basket.trail_active)
         return;
      const double buffer = trail_buffer_atr * atr_m5;
      if(m_basket.direction == RLVR_FADE_SELL)
         m_basket.trail_stop = MathMin(m_basket.trail_stop, m_basket.vwap_price + buffer);
      else
         m_basket.trail_stop = MathMax(m_basket.trail_stop, m_basket.vwap_price - buffer);
     }

   void ClearBasket()
     {
      RLVR_InitBasket(m_basket);
      ArrayInitialize(m_dry_has_leg, false);
     }

   bool StartBasket(const SLiquidityLevel &level,
                    const double u0,
                    const ulong ticket,
                    const double fill_price,
                    const int rung)
     {
      RLVR_InitBasket(m_basket);
      m_basket.active          = true;
      m_basket.basket_id       = StringFormat("B_%s_%d", level.level_id, (int)TimeCurrent());
      m_basket.level_id        = level.level_id;
      m_basket.direction       = level.direction;
      m_basket.state           = RLVR_BASKET_INITIAL_ENTRY;
      m_basket.open_time       = TimeCurrent();
      m_basket.entry_atr_m5    = level.entry_atr_m5;
      m_basket.entry_spread    = level.entry_spread;
      m_basket.level_price     = level.price;
      m_basket.sweep_extreme   = level.sweep_extreme;
      m_basket.void_midpoint   = level.void_midpoint;
      m_basket.sweep_side      = level.sweep_side;
      m_basket.u0              = u0;
      return AddLeg(ticket, rung, u0 * 1.0, fill_price);
     }

   bool AddLeg(const ulong ticket,
               const int rung,
               const double lots,
               const double fill_price)
     {
      if(rung < 0 || rung >= RLVR_MAX_LEGS)
         return false;
      m_basket.legs[rung].ticket     = ticket;
      m_basket.legs[rung].rung       = rung;
      m_basket.legs[rung].lots       = lots;
      m_basket.legs[rung].open_price = fill_price;
      m_basket.legs[rung].open_time  = TimeCurrent();
      m_dry_has_leg[rung]            = true;
      RecomputeAggregates();
      if(rung > 0)
         m_basket.state = RLVR_BASKET_RESCUE_ACTIVE;
      return true;
     }

   void SyncFromMarket(const bool dry_run)
     {
      if(dry_run || !m_basket.active)
         return;

      bool found = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         const ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         found = true;
         const string comment = PositionGetString(POSITION_COMMENT);
         int rung = 0;
         const int pos = StringFind(comment, "|R");
         if(pos >= 0)
           {
            const string rung_str = StringSubstr(comment, pos + 2, 1);
            rung = (int)StringToInteger(rung_str);
           }
         if(rung >= 0 && rung < RLVR_MAX_LEGS)
           {
            m_basket.legs[rung].ticket     = ticket;
            m_basket.legs[rung].rung       = rung;
            m_basket.legs[rung].lots       = PositionGetDouble(POSITION_VOLUME);
            m_basket.legs[rung].open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            m_basket.legs[rung].open_time  = (datetime)PositionGetInteger(POSITION_TIME);
            m_dry_has_leg[rung]            = true;
           }
        }
      if(!found)
        {
         ClearBasket();
         return;
        }
      RecomputeAggregates();
     }

   double FloatingPnl(const bool dry_run) const
     {
      if(!m_basket.active)
         return 0.0;
      if(dry_run)
        {
         const double px = (m_basket.direction == RLVR_FADE_BUY)
                           ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                           : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double pnl = 0.0;
         const double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
         const double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tick_size <= 0.0)
            return 0.0;
         for(int i = 0; i < RLVR_MAX_LEGS; i++)
           {
            if(!m_dry_has_leg[i])
               continue;
            const double diff = (m_basket.direction == RLVR_FADE_BUY)
                                  ? (px - m_basket.legs[i].open_price)
                                  : (m_basket.legs[i].open_price - px);
            pnl += (diff / tick_size) * tick_value * m_basket.legs[i].lots;
           }
         return pnl;
        }

      double pnl = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         const ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
      return pnl;
     }

   int AgeSeconds() const
     {
      if(!m_basket.active)
         return 0;
      return (int)(TimeCurrent() - m_basket.open_time);
     }

   string LegComment(const string level_id, const int rung, const string state_tag) const
     {
      return StringFormat("RLVR|%s|R%d|%s", level_id, rung, state_tag);
     }
  };

#endif
