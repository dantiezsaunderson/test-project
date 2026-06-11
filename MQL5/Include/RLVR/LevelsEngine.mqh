//+------------------------------------------------------------------+
//| LevelsEngine.mqh — spec §5                                       |
//+------------------------------------------------------------------+
#ifndef __RLVR_LEVELS_ENGINE_MQH__
#define __RLVR_LEVELS_ENGINE_MQH__

#include "Types.mqh"
#include "AtrUtils.mqh"

class CLevelsEngine
  {
private:
   string         m_symbol;
   SLevelsConfig  m_cfg;
   SLiquidityLevel m_levels[];
   int            m_count;
   datetime       m_last_d1_bar;
   int            m_last_asia_day;
   int            m_last_london_day;
   bool           m_auto_pdh_pdl;
   bool           m_auto_session;
   bool           m_auto_round;

   int FindIndexById(const string id) const
     {
      for(int i = 0; i < m_count; i++)
         if(m_levels[i].level_id == id)
            return i;
      return -1;
     }

   void UpsertLevel(const SLiquidityLevel &incoming)
     {
      const int existing = FindIndexById(incoming.level_id);
      if(existing >= 0)
        {
         m_levels[existing] = incoming;
         return;
        }
      if(m_count >= RLVR_MAX_LEVELS)
         return;
      m_levels[m_count] = incoming;
      m_count++;
     }

   double MergeDistance(const double atr_m15, const double spread) const
     {
      const double by_atr = m_cfg.level_merge_distance_atr * atr_m15;
      const double by_spread = spread * 5.0;
      return MathMax(by_atr, by_spread);
     }

   void RemoveIndex(const int idx)
     {
      for(int i = idx; i < m_count - 1; i++)
         m_levels[i] = m_levels[i + 1];
      m_count--;
     }

   void ApplyMerge(const double merge_distance)
     {
      for(int i = 0; i < m_count; i++)
        {
         for(int j = i + 1; j < m_count; )
           {
            if(MathAbs(m_levels[i].price - m_levels[j].price) <= merge_distance)
              {
               const int pi = RLVR_LevelTypePriority(m_levels[i].type);
               const int pj = RLVR_LevelTypePriority(m_levels[j].type);
               if(pi < pj)
                  RemoveIndex(j);
               else if(pj < pi)
                 {
                  RemoveIndex(i);
                  i--;
                  break;
                 }
               else if(m_levels[i].quality_score >= m_levels[j].quality_score)
                  RemoveIndex(j);
               else
                 {
                  RemoveIndex(i);
                  i--;
                  break;
                 }
              }
            else
               j++;
           }
        }
     }

   void PruneExpired(const datetime now)
     {
      for(int i = m_count - 1; i >= 0; i--)
        {
         if(m_levels[i].expires_at > 0 && now >= m_levels[i].expires_at)
            RemoveIndex(i);
         else if(m_levels[i].state == RLVR_STATE_EXPIRED)
            RemoveIndex(i);
        }
     }

   datetime EndOfBrokerDay(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 23;
      dt.min  = 59;
      dt.sec  = 59;
      return StructToTime(dt);
     }

   void PublishPDHPDL(const datetime now)
     {
      const double pdh = iHigh(m_symbol, PERIOD_D1, 1);
      const double pdl = iLow(m_symbol, PERIOD_D1, 1);
      if(pdh <= 0.0 || pdl <= 0.0)
         return;

      MqlDateTime dt;
      TimeToStruct(now, dt);
      const string day = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);

      SLiquidityLevel lvl;
      RLVR_InitLevel(lvl);
      lvl.created_at    = now;
      lvl.expires_at    = EndOfBrokerDay(now);
      lvl.quality_score = 0.85;
      lvl.state         = RLVR_STATE_ARMED;

      lvl.type     = RLVR_LEVEL_PDH;
      lvl.price    = pdh;
      lvl.level_id = "PDH_" + day;
      UpsertLevel(lvl);

      RLVR_InitLevel(lvl);
      lvl.created_at    = now;
      lvl.expires_at    = EndOfBrokerDay(now);
      lvl.quality_score = 0.85;
      lvl.state         = RLVR_STATE_ARMED;
      lvl.type          = RLVR_LEVEL_PDL;
      lvl.price         = pdl;
      lvl.level_id      = "PDL_" + day;
      UpsertLevel(lvl);
     }

   bool CopySessionRange(const datetime from,
                         const datetime to,
                         double &hi,
                         double &lo) const
     {
      hi = -DBL_MAX;
      lo = DBL_MAX;
      if(to <= from)
         return false;

      MqlRates rates[];
      const int copied = CopyRates(m_symbol, PERIOD_M5, from, to, rates);
      if(copied <= 0)
         return false;

      for(int i = 0; i < copied; i++)
        {
         if(rates[i].high > hi)
            hi = rates[i].high;
         if(rates[i].low < lo)
            lo = rates[i].low;
        }
      return (hi > lo);
     }

   void PublishSessionHL(const string prefix,
                         const ENUM_RLVR_LEVEL_TYPE type_h,
                         const ENUM_RLVR_LEVEL_TYPE type_l,
                         const double hi,
                         const double lo,
                         const datetime now,
                         const datetime expires)
     {
      SLiquidityLevel lvl;
      RLVR_InitLevel(lvl);
      lvl.created_at    = now;
      lvl.expires_at    = expires;
      lvl.quality_score = 0.75;
      lvl.state         = RLVR_STATE_ARMED;

      lvl.type     = type_h;
      lvl.price    = hi;
      lvl.level_id = prefix + "_H";
      UpsertLevel(lvl);

      RLVR_InitLevel(lvl);
      lvl.type     = type_l;
      lvl.price    = lo;
      lvl.level_id = prefix + "_L";
      UpsertLevel(lvl);
     }

public:
   bool Init(const string symbol, const SLevelsConfig &cfg)
     {
      m_symbol          = symbol;
      m_cfg             = cfg;
      m_count           = 0;
      m_last_d1_bar     = 0;
      m_last_asia_day   = -1;
      m_last_london_day = -1;
      m_auto_pdh_pdl    = true;
      m_auto_session    = true;
      m_auto_round      = true;
      ArrayResize(m_levels, RLVR_MAX_LEVELS);
      return true;
     }

   void SetAutoDiscovery(const bool pdh_pdl,
                         const bool session_levels,
                         const bool round_levels)
     {
      m_auto_pdh_pdl = pdh_pdl;
      m_auto_session = session_levels;
      m_auto_round   = round_levels;
     }

   void OnNewM5Bar(const datetime bar_time,
                   const double bid,
                   const double spread,
                   const double atr_m15,
                   const double atr_h1)
     {
      PruneExpired(bar_time);

      const datetime d1_time = iTime(m_symbol, PERIOD_D1, 0);
      if(m_auto_pdh_pdl && d1_time > 0 && d1_time != m_last_d1_bar)
        {
         m_last_d1_bar = d1_time;
         PublishPDHPDL(bar_time);
        }

      MqlDateTime dt;
      TimeToStruct(bar_time, dt);
      const int day_key = dt.year * 10000 + dt.mon * 100 + dt.day;

      if(m_auto_session && dt.hour == 8 && dt.min < 5 && m_last_asia_day != day_key)
        {
         MqlDateTime start = dt;
         start.hour = 0;
         start.min  = 0;
         start.sec  = 0;
         MqlDateTime end = dt;
         end.hour = 7;
         end.min  = 59;
         end.sec  = 59;
         double hi, lo;
         if(CopySessionRange(StructToTime(start), StructToTime(end), hi, lo))
           {
            const datetime expires = StructToTime(end) + 4 * 3600;
            PublishSessionHL("ASIA", RLVR_LEVEL_ASIA_H, RLVR_LEVEL_ASIA_L,
                             hi, lo, bar_time, expires);
           }
         m_last_asia_day = day_key;
        }

      if(m_auto_session && dt.hour == 13 && dt.min < 5 && m_last_london_day != day_key)
        {
         MqlDateTime start = dt;
         start.hour = 8;
         start.min  = 0;
         start.sec  = 0;
         MqlDateTime end = dt;
         end.hour = 12;
         end.min  = 59;
         end.sec  = 59;
         double hi, lo;
         if(CopySessionRange(StructToTime(start), StructToTime(end), hi, lo))
           {
            const datetime expires = StructToTime(end) + 4 * 3600;
            PublishSessionHL("LONDON", RLVR_LEVEL_LONDON_H, RLVR_LEVEL_LONDON_L,
                             hi, lo, bar_time, expires);
           }
         m_last_london_day = day_key;
        }

      if(m_auto_round && atr_h1 > 0.0)
        {
         const double step = m_cfg.round_step;
         const double nearest = MathRound(bid / step) * step;
         if(MathAbs(bid - nearest) <= 0.5 * atr_h1)
           {
            SLiquidityLevel rnd;
            RLVR_InitLevel(rnd);
            rnd.type          = RLVR_LEVEL_ROUND;
            rnd.price         = nearest;
            rnd.level_id      = StringFormat("ROUND_%.0f", nearest);
            rnd.created_at    = bar_time;
            rnd.expires_at    = bar_time + 12 * 3600;
            rnd.quality_score = 0.60;
            rnd.state         = RLVR_STATE_ARMED;
            UpsertLevel(rnd);
           }
        }

      ApplyMerge(MergeDistance(atr_m15, spread));
     }

   bool AddManualLevel(const SLiquidityLevel &manual)
     {
      if(manual.price <= 0.0)
         return false;
      UpsertLevel(manual);
      return true;
     }

   int GetActiveLevels(SLiquidityLevel &out[],
                       const datetime now) const
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
        {
         const SLiquidityLevel lvl = m_levels[i];
         if(lvl.state != RLVR_STATE_ARMED &&
            lvl.state != RLVR_STATE_SWEEP_DETECTED &&
            lvl.state != RLVR_STATE_RECLAIM_CONFIRMED)
            continue;
         if(lvl.created_at > now || (lvl.expires_at > 0 && now >= lvl.expires_at))
            continue;
         if(lvl.quality_score < m_cfg.level_quality_threshold)
            continue;
         ArrayResize(out, n + 1);
         out[n] = lvl;
         n++;
        }

      for(int a = 0; a < n - 1; a++)
        {
         for(int b = a + 1; b < n; b++)
           {
            bool swap = false;
            if(out[b].quality_score > out[a].quality_score)
               swap = true;
            else if(out[b].quality_score == out[a].quality_score &&
                    out[b].created_at < out[a].created_at)
               swap = true;
            if(swap)
              {
               SLiquidityLevel tmp = out[a];
               out[a] = out[b];
               out[b] = tmp;
              }
           }
        }

      if(n > m_cfg.max_armed_levels)
        {
         ArrayResize(out, m_cfg.max_armed_levels);
         return m_cfg.max_armed_levels;
        }
      return n;
     }

   bool UpdateLevel(const SLiquidityLevel &level)
     {
      const int idx = FindIndexById(level.level_id);
      if(idx < 0)
         return false;
      m_levels[idx] = level;
      return true;
     }

   int RegistryCount() const { return m_count; }
  };

#endif
