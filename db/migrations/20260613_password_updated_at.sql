alter table public.profiles
  add column if not exists password_updated_at timestamptz default now();

-- Update existing rows to have password_updated_at = created_at to be safe
update public.profiles
set password_updated_at = created_at
where password_updated_at is null;

-- Function to track password updates
create or replace function public.handle_password_update()
returns trigger as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    update public.profiles
    set password_updated_at = now()
    where id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

-- Trigger for auth.users
drop trigger if exists on_auth_user_password_update on auth.users;
create trigger on_auth_user_password_update
  after update on auth.users
  for each row execute procedure public.handle_password_update();
