-- ============================================================================
-- Painel de Assembleias ARVIA · estrutura do banco no Supabase
-- Cole tudo no SQL Editor do Supabase e clique em Run. Pode rodar mais de uma
-- vez sem problema: o script só cria o que ainda não existe.
-- ============================================================================

-- 1) Perfis: um por usuário com acesso ao painel -----------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  nome       text,
  role       text not null default 'consultor' check (role in ('admin','consultor')),
  ativo      boolean not null default true,
  created_at timestamptz not null default now()
);

-- 2) Dados do painel: cada usuário guarda as próprias chaves -----------------
--    (clientesImoveis, clientesVeiculos, gruposImoveis, radarSorteio, parcelasEmDia...)
create table if not exists public.user_data (
  user_id    uuid not null references auth.users(id) on delete cascade,
  chave      text not null,
  valor      jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, chave)
);

-- 3) Funções auxiliares das regras de acesso ---------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and ativo);
$$;

create or replace function public.is_ativo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and ativo);
$$;

-- updated_at sempre com o relógio do servidor
create or replace function public.tocar_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists user_data_updated_at on public.user_data;
create trigger user_data_updated_at before insert or update on public.user_data
for each row execute function public.tocar_updated_at();

-- 4) Perfil criado automaticamente quando alguém é convidado -----------------
--    O primeiro usuário cadastrado vira administrador.
create or replace function public.criar_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, nome, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)),
    case when exists (select 1 from public.profiles) then 'consultor' else 'admin' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
for each row execute function public.criar_perfil();

-- Perfis para usuários que já existiam antes deste script
insert into public.profiles (id, email, nome, role)
select u.id, u.email, split_part(u.email, '@', 1), 'consultor'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);

update public.profiles set role = 'admin'
where id = (select id from public.profiles order by created_at limit 1)
  and not exists (select 1 from public.profiles where role = 'admin');

-- 5) Regras de acesso (RLS) --------------------------------------------------
alter table public.profiles  enable row level security;
alter table public.user_data enable row level security;

drop policy if exists "perfil: ver o próprio ou admin vê todos" on public.profiles;
create policy "perfil: ver o próprio ou admin vê todos" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());

drop policy if exists "perfil: admin edita" on public.profiles;
create policy "perfil: admin edita" on public.profiles
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "dados: ler os próprios ou admin lê todos" on public.user_data;
create policy "dados: ler os próprios ou admin lê todos" on public.user_data
  for select to authenticated using ((user_id = auth.uid() and public.is_ativo()) or public.is_admin());

drop policy if exists "dados: criar os próprios" on public.user_data;
create policy "dados: criar os próprios" on public.user_data
  for insert to authenticated with check (user_id = auth.uid() and public.is_ativo());

drop policy if exists "dados: editar os próprios" on public.user_data;
create policy "dados: editar os próprios" on public.user_data
  for update to authenticated using (user_id = auth.uid() and public.is_ativo())
  with check (user_id = auth.uid() and public.is_ativo());

drop policy if exists "dados: apagar os próprios" on public.user_data;
create policy "dados: apagar os próprios" on public.user_data
  for delete to authenticated using (user_id = auth.uid() and public.is_ativo());

-- 6) Sinal de vida (evita que o projeto grátis pause por inatividade) --------
create or replace function public.ping() returns text
language sql security definer set search_path = public as $$ select 'ok'::text $$;
grant execute on function public.ping() to anon, authenticated;
