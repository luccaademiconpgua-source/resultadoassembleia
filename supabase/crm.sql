-- ============================================================================
-- Painel ARVIA · CRM de leads
-- Cole no SQL Editor do Supabase e clique em Run. Pode rodar mais de uma vez.
-- Requer o setup.sql (tabelas profiles e user_data) já executado.
-- ============================================================================

create table if not exists public.leads (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  origem         text not null default 'site',
  nome           text not null check (char_length(nome) between 2 and 120),
  whatsapp       text not null check (char_length(whatsapp) between 8 and 30),
  email          text check (email is null or char_length(email) <= 160),
  segmento       text check (segmento is null or char_length(segmento) <= 60),
  objetivo       text check (objetivo is null or char_length(objetivo) <= 160),
  valor_mensal   text check (valor_mensal is null or char_length(valor_mensal) <= 60),
  qualificacao   jsonb not null default '{}'::jsonb,
  detalhe        text check (detalhe is null or char_length(detalhe) <= 2000),
  consentimento  boolean not null,
  consentimento_em timestamptz,
  status         text not null default 'novo' check (status in ('novo','contato','proposta','fechado','perdido')),
  responsavel    uuid references auth.users(id) on delete set null,
  notas          text check (notas is null or char_length(notas) <= 8000)
);
create index if not exists leads_created_idx on public.leads (created_at desc);
create index if not exists leads_resp_idx on public.leads (responsavel);

-- Quem envia pelo site não escolhe etapa, responsável nem notas
create or replace function public.leads_antes_inserir() returns trigger
language plpgsql as $$
begin
  if current_user = 'anon' then
    new.status := 'novo';
    new.responsavel := null;
    new.notas := null;
    new.created_at := now();
  end if;
  new.atualizado_em := now();
  return new;
end $$;
drop trigger if exists leads_antes_inserir on public.leads;
create trigger leads_antes_inserir before insert on public.leads
for each row execute function public.leads_antes_inserir();

create or replace function public.leads_antes_atualizar() returns trigger
language plpgsql as $$
begin
  new.atualizado_em := now();
  new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists leads_antes_atualizar on public.leads;
create trigger leads_antes_atualizar before update on public.leads
for each row execute function public.leads_antes_atualizar();

-- Regras de acesso
alter table public.leads enable row level security;

drop policy if exists "leads: site envia com consentimento" on public.leads;
create policy "leads: site envia com consentimento" on public.leads
  for insert to anon, authenticated with check (consentimento = true);

drop policy if exists "leads: admin vê todos, consultor vê os seus" on public.leads;
create policy "leads: admin vê todos, consultor vê os seus" on public.leads
  for select to authenticated using (public.is_admin() or (responsavel = auth.uid() and public.is_ativo()));

drop policy if exists "leads: admin edita todos, consultor edita os seus" on public.leads;
create policy "leads: admin edita todos, consultor edita os seus" on public.leads
  for update to authenticated
  using (public.is_admin() or (responsavel = auth.uid() and public.is_ativo()))
  with check (public.is_admin() or (responsavel = auth.uid() and public.is_ativo()));

drop policy if exists "leads: só admin apaga" on public.leads;
create policy "leads: só admin apaga" on public.leads
  for delete to authenticated using (public.is_admin());

-- Permissões explícitas: visitante só insere (não lê nada)
revoke all on public.leads from anon;
grant insert on public.leads to anon;
grant select, insert, update, delete on public.leads to authenticated;
grant all on public.leads to service_role;
