-- Correção: dá à função de administração (service_role) acesso às tabelas do painel.
-- Cole no SQL Editor do Supabase e clique em Run.
grant usage on schema public to service_role;
grant all on public.profiles, public.user_data, public.leads to service_role;
grant execute on function public.is_admin(), public.is_ativo() to service_role;
