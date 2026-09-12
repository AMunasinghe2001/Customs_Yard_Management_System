-- Sale END time for tender sales and destructions.
--
-- A sale has a start moment (sale_date + sale_time) that unlocks Mark Sold /
-- Mark Destroyed, and now an END moment that closes bidding. The valuation is
-- the RESERVE PRICE, so it stays sealed until the sale has ENDED — not merely
-- started. Without this the reserve became visible the moment bidding opened,
-- which is exactly when it must not be.
--
-- Nullable on purpose: existing rows have no end time and fall back to the
-- start moment, so their behaviour is unchanged.
alter table if exists public.tender_sales
  add column if not exists sale_end_time text;

alter table if exists public.destructions
  add column if not exists sale_end_time text;

comment on column public.tender_sales.sale_end_time is
  'Sale close time, "HH:mm". The valuation stays sealed until this passes.';
comment on column public.destructions.sale_end_time is
  'Sale close time, "HH:mm". The valuation stays sealed until this passes.';
