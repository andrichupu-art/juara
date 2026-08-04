-- PT Juara Portal v2. Jalankan seluruh file ini di Supabase SQL Editor.
-- Prasyarat untuk login QR: Dashboard Supabase > Authentication > Providers
-- > Anonymous Sign-Ins: aktifkan.

create table if not exists public.participants_v2 (
  id uuid primary key default gen_random_uuid(),
  google_user_id uuid unique references auth.users(id) on delete set null,
  nama text not null check (char_length(trim(nama)) >= 2),
  nik text not null unique check (nik ~ '^[0-9]{16}$'),
  telepon text not null,
  kota text not null,
  qr_token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.participant_qr_sessions_v2 (
  participant_id uuid not null references public.participants_v2(id) on delete cascade,
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.documents_v2 (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.participants_v2(id) on delete cascade,
  jenis text not null check (jenis in ('ktp','kk','paspor','ijazah','sertifikat','medis','foto')),
  file_name text not null,
  size bigint not null default 0,
  storage_path text not null,
  status text not null default 'menunggu' check (status in ('menunggu','terverifikasi','ditolak')),
  uploaded_at timestamptz not null default now(),
  unique(participant_id, jenis)
);

create table if not exists public.progress_v2 (
  participant_id uuid primary key references public.participants_v2(id) on delete cascade,
  tahap integer not null default 0 check (tahap between 0 and 5),
  updated_at timestamptz not null default now()
);

create or replace function public.can_access_participant_v2(p_participant_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.participants_v2 p
    where p.id = p_participant_id and p.google_user_id = auth.uid()
  ) or exists (
    select 1 from public.participant_qr_sessions_v2 s
    where s.participant_id = p_participant_id and s.auth_user_id = auth.uid()
  );
$$;

create or replace function public.login_with_qr_v2(p_qr_token uuid)
returns public.participants_v2 language plpgsql security definer set search_path = public as $$
declare p public.participants_v2;
begin
  if auth.uid() is null then raise exception 'Sesi QR tidak valid'; end if;
  select * into p from public.participants_v2 where qr_token = p_qr_token;
  if p.id is null then raise exception 'QR tidak ditemukan atau sudah tidak berlaku'; end if;
  insert into public.participant_qr_sessions_v2(participant_id, auth_user_id)
  values (p.id, auth.uid())
  on conflict (auth_user_id) do update set participant_id = excluded.participant_id, created_at = now();
  return p;
end;
$$;

grant execute on function public.login_with_qr_v2(uuid) to anon, authenticated;

alter table public.participants_v2 enable row level security;
alter table public.participant_qr_sessions_v2 enable row level security;
alter table public.documents_v2 enable row level security;
alter table public.progress_v2 enable row level security;

create policy "v2 peserta baca profil sendiri" on public.participants_v2 for select
  using (public.can_access_participant_v2(id));
create policy "v2 google membuat profil sendiri" on public.participants_v2 for insert to authenticated
  with check (google_user_id = auth.uid() and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false);
create policy "v2 peserta ubah profil sendiri" on public.participants_v2 for update
  using (public.can_access_participant_v2(id)) with check (public.can_access_participant_v2(id));

create policy "v2 peserta baca dokumen sendiri" on public.documents_v2 for select
  using (public.can_access_participant_v2(participant_id));
create policy "v2 peserta tambah dokumen sendiri" on public.documents_v2 for insert
  with check (public.can_access_participant_v2(participant_id));
create policy "v2 peserta ubah dokumen sendiri" on public.documents_v2 for update
  using (public.can_access_participant_v2(participant_id)) with check (public.can_access_participant_v2(participant_id));

create policy "v2 peserta baca progres sendiri" on public.progress_v2 for select
  using (public.can_access_participant_v2(participant_id));
create policy "v2 google membuat progres sendiri" on public.progress_v2 for insert to authenticated
  with check (public.can_access_participant_v2(participant_id));

insert into storage.buckets(id, name, public) values ('juara-v2-documents', 'juara-v2-documents', false)
on conflict (id) do update set public = false;

create policy "v2 peserta unggah file sendiri" on storage.objects for insert
  with check (bucket_id = 'juara-v2-documents' and public.can_access_participant_v2((storage.foldername(name))[1]::uuid));
create policy "v2 peserta baca file sendiri" on storage.objects for select
  using (bucket_id = 'juara-v2-documents' and public.can_access_participant_v2((storage.foldername(name))[1]::uuid));
create policy "v2 peserta ganti file sendiri" on storage.objects for update
  using (bucket_id = 'juara-v2-documents' and public.can_access_participant_v2((storage.foldername(name))[1]::uuid));
