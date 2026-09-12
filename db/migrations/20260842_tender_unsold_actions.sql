-- Explicit UNSOLD and UNDESTROYED status for tender sale items and destruction items.
--
-- Allows officers to manually mark an item unsold/undestroyed immediately after
-- the sale moment, without having to wait for the automatic grace deadline.
alter table if exists public.tender_sale_items
  add column if not exists unsold boolean not null default false,
  add column if not exists unsold_at timestamptz;

alter table if exists public.destruction_items
  add column if not exists undestroyed boolean not null default false,
  add column if not exists undestroyed_at timestamptz;

comment on column public.tender_sale_items.unsold is
  'True when the officer explicitly marks the item unsold in this tender sale.';
comment on column public.destruction_items.undestroyed is
  'True when the officer explicitly marks the item undestroyed in this destruction.';
