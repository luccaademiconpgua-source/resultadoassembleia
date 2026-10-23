// Painel de Assembleias ARVIA · função "admin-usuarios"
// Convida, bloqueia e desbloqueia consultores. Só o administrador pode chamar.
// Publicar no Supabase: Edge Functions > Deploy a new function > Via Editor,
// nome "admin-usuarios", colar este arquivo inteiro e clicar em Deploy.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, service, { auth: { persistSession: false } });

    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: quem, error: errQuem } = await admin.auth.getUser(token);
    if (errQuem || !quem?.user) return json({ erro: "Sessão inválida. Entre de novo no painel." }, 401);

    const { data: perfil } = await admin.from("profiles").select("role, ativo").eq("id", quem.user.id).single();
    if (!perfil || perfil.role !== "admin" || !perfil.ativo) {
      return json({ erro: "Só o administrador pode gerenciar acessos." }, 403);
    }

    const body = await req.json();
    const acao = String(body.acao ?? "");

    if (acao === "convidar") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const nome = String(body.nome ?? "").trim();
      if (!/^\S+@\S+\.\S+$/.test(email)) return json({ erro: "E-mail inválido." }, 400);
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { nome },
        redirectTo: body.redirectTo,
      });
      if (error) return json({ erro: error.message }, 400);
      if (nome && data?.user) await admin.from("profiles").update({ nome }).eq("id", data.user.id);
      return json({ ok: true });
    }

    if (acao === "bloquear" || acao === "desbloquear") {
      const id = String(body.id ?? "");
      if (!id) return json({ erro: "Usuário não informado." }, 400);
      if (id === quem.user.id) return json({ erro: "Você não pode bloquear a própria conta." }, 400);
      const bloquear = acao === "bloquear";
      await admin.from("profiles").update({ ativo: !bloquear }).eq("id", id);
      const { error } = await admin.auth.admin.updateUserById(id, { ban_duration: bloquear ? "876000h" : "none" });
      if (error) return json({ erro: error.message }, 400);
      return json({ ok: true });
    }

    return json({ erro: "Ação desconhecida." }, 400);
  } catch (e) {
    return json({ erro: String((e as Error)?.message ?? e) }, 500);
  }
});
