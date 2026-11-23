-- RUANG SETARA — Supabase schema (v3)
-- Run the whole file in Supabase SQL Editor. Review with a security professional before collecting real survivor stories.
-- Public feeds expose snapshot display labels only; raw account IDs are not granted to public feed readers.

create extension if not exists pgcrypto;

-- 1) Account profile. A signup request NEVER grants a privileged role.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Member',
  role text not null default 'community' check (role in ('community','volunteer','professional','admin')),
  requested_role text not null default 'community' check (requested_role in ('community','volunteer','professional')),
  professional_status text not null default 'none' check (professional_status in ('none','pending','verified','rejected')),
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists requested_role text not null default 'community';

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, auth as $$
declare req text;
begin
  req := coalesce(new.raw_user_meta_data->>'requested_role','community');
  if req not in ('community','volunteer','professional') then req := 'community'; end if;
  insert into public.profiles(id,display_name,role,requested_role,professional_status)
  values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''),'Member'),'community',req,
         case when req in ('volunteer','professional') then 'pending' else 'none' end)
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Users may edit only their own display name through this RPC; role/status cannot be self-edited.
create or replace function public.update_my_display_name(new_display_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if new_display_name is null or char_length(trim(new_display_name)) not between 2 and 40 then
    raise exception 'Display name must be 2–40 characters';
  end if;
  update public.profiles set display_name=trim(new_display_name) where id=auth.uid();
end; $$;

-- 2) Public community posts and replies. Identity is snapshotted by a trigger.
create table if not exists public.community_posts (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check (char_length(body) between 1 and 5000),
 is_anonymous boolean not null default false,
 author_label text not null default 'Community member',
 created_at timestamptz not null default now()
);
alter table public.community_posts add column if not exists is_anonymous boolean not null default false;
alter table public.community_posts add column if not exists author_label text not null default 'Community member';

create table if not exists public.post_replies (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.community_posts(id) on delete cascade,
 author_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check (char_length(body) between 1 and 2000),
 is_anonymous boolean not null default false,
 author_label text not null default 'Community member',
 created_at timestamptz not null default now()
);
alter table public.post_replies add column if not exists is_anonymous boolean not null default false;
alter table public.post_replies add column if not exists author_label text not null default 'Community member';

-- 3) Public place observations and replies. Only non-sensitive public-place photos belong in this bucket.
create table if not exists public.place_observations (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.profiles(id) on delete cascade,
 title text not null check (char_length(title) between 1 and 180),
 kind text not null,
 description text not null check (char_length(description) between 1 and 3000),
 photo_url text,
 is_anonymous boolean not null default false,
 author_label text not null default 'Community member',
 created_at timestamptz not null default now()
);
alter table public.place_observations add column if not exists is_anonymous boolean not null default false;
alter table public.place_observations add column if not exists author_label text not null default 'Community member';

create table if not exists public.observation_replies (
 id uuid primary key default gen_random_uuid(),
 observation_id uuid not null references public.place_observations(id) on delete cascade,
 author_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check (char_length(body) between 1 and 2000),
 is_anonymous boolean not null default false,
 author_label text not null default 'Community member',
 created_at timestamptz not null default now()
);
alter table public.observation_replies add column if not exists is_anonymous boolean not null default false;
alter table public.observation_replies add column if not exists author_label text not null default 'Community member';

-- Server-side identity stamping prevents a client from impersonating another display name.
create or replace function public.stamp_public_identity()
returns trigger language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if new.is_anonymous then new.author_label := 'Anonymous member';
  else
    select display_name into nm from public.profiles where id=new.author_id;
    new.author_label := coalesce(nm,'Community member');
  end if;
  return new;
end; $$;
drop trigger if exists stamp_post_identity on public.community_posts;
create trigger stamp_post_identity before insert on public.community_posts for each row execute procedure public.stamp_public_identity();
drop trigger if exists stamp_post_reply_identity on public.post_replies;
create trigger stamp_post_reply_identity before insert on public.post_replies for each row execute procedure public.stamp_public_identity();
drop trigger if exists stamp_observation_identity on public.place_observations;
create trigger stamp_observation_identity before insert on public.place_observations for each row execute procedure public.stamp_public_identity();
drop trigger if exists stamp_observation_reply_identity on public.observation_replies;
create trigger stamp_observation_reply_identity before insert on public.observation_replies for each row execute procedure public.stamp_public_identity();

-- 4) Private support stories and messages. Stories are NEVER in public feeds.
create table if not exists public.support_stories (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 display_name text,
 is_anonymous boolean not null default true,
 category text not null,
 body text not null check (char_length(body) between 1 and 12000),
 consent_at timestamptz not null,
 status text not null default 'open' check(status in ('open','assigned','closed')),
 created_at timestamptz not null default now()
);
alter table public.support_stories add column if not exists is_anonymous boolean not null default true;

create or replace function public.stamp_story_identity()
returns trigger language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if new.is_anonymous then new.display_name := null;
  else
    select display_name into nm from public.profiles where id=new.user_id;
    new.display_name := coalesce(nm,'Member');
  end if;
  return new;
end; $$;
drop trigger if exists stamp_story_identity_trigger on public.support_stories;
create trigger stamp_story_identity_trigger before insert on public.support_stories for each row execute procedure public.stamp_story_identity();

create table if not exists public.story_messages (
 id uuid primary key default gen_random_uuid(),
 story_id uuid not null references public.support_stories(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check (char_length(body) between 1 and 8000),
 created_at timestamptz not null default now()
);

-- Helper check runs as a protected function; a signup selection alone is never sufficient.
create or replace function public.is_verified_helper()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id=auth.uid()
      and (p.role='admin' or (p.role in ('professional','volunteer') and p.professional_status='verified'))
  );
$$;
revoke all on function public.is_verified_helper() from public;
grant execute on function public.is_verified_helper() to authenticated;
revoke all on function public.update_my_display_name(text) from public;
grant execute on function public.update_my_display_name(text) to authenticated;

-- 5) RLS
alter table public.profiles enable row level security;
alter table public.community_posts enable row level security;
alter table public.post_replies enable row level security;
alter table public.place_observations enable row level security;
alter table public.observation_replies enable row level security;
alter table public.support_stories enable row level security;
alter table public.story_messages enable row level security;

drop policy if exists "profiles visible" on public.profiles;
drop policy if exists "profile owner read" on public.profiles;
create policy "profile owner read" on public.profiles for select to authenticated using (id=auth.uid());

-- Public can read feed content. Column grants below hide author_id from public API reads.
drop policy if exists "posts public read" on public.community_posts;
create policy "posts public read" on public.community_posts for select using (true);
drop policy if exists "signed in create own post" on public.community_posts;
create policy "signed in create own post" on public.community_posts for insert to authenticated with check (auth.uid()=author_id);
drop policy if exists "author delete own post" on public.community_posts;
create policy "author delete own post" on public.community_posts for delete to authenticated using (auth.uid()=author_id);

drop policy if exists "post replies public read" on public.post_replies;
create policy "post replies public read" on public.post_replies for select using (true);
drop policy if exists "signed in create own post reply" on public.post_replies;
create policy "signed in create own post reply" on public.post_replies for insert to authenticated with check (auth.uid()=author_id);
drop policy if exists "reply author delete" on public.post_replies;
create policy "reply author delete" on public.post_replies for delete to authenticated using (auth.uid()=author_id);

drop policy if exists "observations public read" on public.place_observations;
create policy "observations public read" on public.place_observations for select using (true);
drop policy if exists "signed in create observation" on public.place_observations;
create policy "signed in create observation" on public.place_observations for insert to authenticated with check (auth.uid()=author_id);
drop policy if exists "observation author delete" on public.place_observations;
create policy "observation author delete" on public.place_observations for delete to authenticated using (auth.uid()=author_id);

drop policy if exists "observation replies public read" on public.observation_replies;
create policy "observation replies public read" on public.observation_replies for select using (true);
drop policy if exists "signed in create observation reply" on public.observation_replies;
create policy "signed in create observation reply" on public.observation_replies for insert to authenticated with check (auth.uid()=author_id);
drop policy if exists "observation reply author delete" on public.observation_replies;
create policy "observation reply author delete" on public.observation_replies for delete to authenticated using (auth.uid()=author_id);

-- Story owner and verified helpers can read; public/ordinary members cannot.
drop policy if exists "story owner and verified helpers read" on public.support_stories;
create policy "story owner and verified helpers read" on public.support_stories for select to authenticated using (auth.uid()=user_id or public.is_verified_helper());
drop policy if exists "owner creates story with consent" on public.support_stories;
create policy "owner creates story with consent" on public.support_stories for insert to authenticated with check (auth.uid()=user_id and consent_at is not null);
drop policy if exists "owner or admin updates story status" on public.support_stories;
drop policy if exists "admin updates story status" on public.support_stories;
create policy "admin updates story status" on public.support_stories for update to authenticated using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')) with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'));

-- Messages are visible only to the story owner and verified helpers. Owner can reply in the same private thread.
drop policy if exists "story messages visible to participants" on public.story_messages;
create policy "story messages visible to participants" on public.story_messages for select to authenticated using (
 exists(select 1 from public.support_stories s where s.id=story_id and (s.user_id=auth.uid() or public.is_verified_helper()))
);
drop policy if exists "verified helpers reply to story" on public.story_messages;
drop policy if exists "participants reply privately" on public.story_messages;
create policy "participants reply privately" on public.story_messages for insert to authenticated with check (
 auth.uid()=sender_id and exists(select 1 from public.support_stories s where s.id=story_id and (s.user_id=auth.uid() or public.is_verified_helper()))
);

-- 6) Explicit table/column grants. Public feed reads cannot retrieve author account UUIDs.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
revoke all on public.community_posts from anon, authenticated;
grant select (id,body,is_anonymous,author_label,created_at) on public.community_posts to anon, authenticated;
grant insert (author_id,body,is_anonymous) on public.community_posts to authenticated;
grant delete on public.community_posts to authenticated;
revoke all on public.post_replies from anon, authenticated;
grant select (id,post_id,body,is_anonymous,author_label,created_at) on public.post_replies to anon, authenticated;
grant insert (post_id,author_id,body,is_anonymous) on public.post_replies to authenticated;
grant delete on public.post_replies to authenticated;
revoke all on public.place_observations from anon, authenticated;
grant select (id,title,kind,description,photo_url,is_anonymous,author_label,created_at) on public.place_observations to anon, authenticated;
grant insert (author_id,title,kind,description,photo_url,is_anonymous) on public.place_observations to authenticated;
grant delete on public.place_observations to authenticated;
revoke all on public.observation_replies from anon, authenticated;
grant select (id,observation_id,body,is_anonymous,author_label,created_at) on public.observation_replies to anon, authenticated;
grant insert (observation_id,author_id,body,is_anonymous) on public.observation_replies to authenticated;
grant delete on public.observation_replies to authenticated;
revoke all on public.support_stories from anon, authenticated;
grant select (id,user_id,display_name,is_anonymous,category,body,consent_at,status,created_at) on public.support_stories to authenticated;
grant insert (user_id,is_anonymous,category,body,consent_at) on public.support_stories to authenticated;
grant update (status) on public.support_stories to authenticated;
revoke all on public.story_messages from anon, authenticated;
grant select, insert on public.story_messages to authenticated;

-- 7) Public bucket only for non-sensitive place observation photos.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('place-photos','place-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "signed-in upload own place photos" on storage.objects;
create policy "signed-in upload own place photos" on storage.objects for insert to authenticated with check (
 bucket_id='place-photos' and (storage.foldername(name))[1]=auth.uid()::text
);
drop policy if exists "public read place photos" on storage.objects;
create policy "public read place photos" on storage.objects for select using (bucket_id='place-photos');
drop policy if exists "owner delete own place photos" on storage.objects;
create policy "owner delete own place photos" on storage.objects for delete to authenticated using (
 bucket_id='place-photos' and (storage.foldername(name))[1]=auth.uid()::text
);

-- 8) ADMIN ONLY: after offline verification of identity, credentials, safeguarding training and references,
-- promote the approved account using its auth.users UUID:
-- update public.profiles set role='professional', professional_status='verified' where id='AUTH_USER_UUID';
-- or role='volunteer'. Do not promote applicants based only on their signup choice.
