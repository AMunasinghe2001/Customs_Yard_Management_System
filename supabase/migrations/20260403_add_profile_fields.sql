alter table profiles
  add column if not exists mobile_number text,
  add column if not exists job_role text,
  add column if not exists department text,
  add column if not exists profile_image_url text;
