// Roteiro do vídeo de trajeto do artigo 02.07 — "Segurança da conta: sessões
// ativas e trocar de conta". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (SESSIONS_SECTION, SIDEBAR_ITEMS.SWITCH_ACCOUNT).
//
// REGRA DO PEDIDO (P2): não encerre sessão de outra usuária — mostra só a
// lista. Na prática, `lib/login.mjs` zera TODAS as sessões da usuária antes
// de cada gravação (`user_sessions.destroy_all` + `tokens: {}`, depois de
// `preparar` rodar) — então Sessões Ativas SEMPRE mostra exatamente 1
// aparelho (o desta gravação, marcado "Sessão atual"), nunca um de verdade
// pra revogar. Isso bate com o próprio "O que dá errado" do artigo: "Não
// consigo revogar a minha própria sessão" — o botão Revogar não aparece na
// Sessão atual.
//
// Para "Trocar de conta" aparecer, a usuária precisa ter mais de uma conta
// (`userAccounts.length > 1`, ver SidebarAccountSwitcher.vue). Duda Admin só
// tinha a conta 9; o preparar garante também um vínculo com a conta 6 (conta
// de smoke test já existente no banco de dev, não uma conta criada e apagada
// por este vídeo) — é a única forma de mostrar o seletor sem inventar uma
// conta nova. O nome original dela no banco, "Tenant Smoke Test", tinha cara
// de teste na tela — o preparar renomeia só no banco de dev (idempotente)
// para "Corretora Litoral Sul", um nome fictício de corretora como o resto
// do dado de teste (pedido do Rodrigo, 24/09/2026). O vídeo abre a lista e
// NÃO clica em nenhuma conta (mudar de conta recarregaria a página no meio
// da gravação).
//
// Trajeto: foto → Configurações do Perfil → Sessões Ativas → nome da conta
// no topo da barra lateral → lista "Alterar conta".

export const id = '02.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
usuaria = Account.find(${login.contaId}).users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
AccountUser.find_or_create_by!(account_id: 6, user_id: usuaria.id) do |au|
  au.role = "agent"
end
# Só no banco de dev: renomeia a conta 6 de "Tenant Smoke Test" (cara de
# teste) para um nome fictício de corretora, como o resto do dado de teste.
Account.find(6).update!(name: "Corretora Litoral Sul")
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Segurança da conta: sessões e contas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Clique na sua foto',
    acao: 'mover e clicar',
    alvo: { seletor: '.border-t.border-n-weak button' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Configurações do Perfil',
    acao: 'mover e clicar',
    alvo: { texto: 'Configurações do Perfil' },
    aguardarTextoDepois: 'Seu nome completo',
    zoom: 1.8,
  },
  {
    legenda: 'Vá até Sessões Ativas',
    acao: 'parar',
    alvo: { texto: 'Sessões Ativas', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Veja o aparelho e a Sessão atual',
    acao: 'parar',
    alvo: { texto: 'Sessão atual' },
    zoom: 1.6,
    duracaoMs: 2000,
  },
  {
    legenda: 'Clique no nome da conta',
    acao: 'mover e clicar',
    alvo: { seletor: '#sidebar-account-switcher' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja a lista Alterar conta',
    acao: 'parar',
    alvo: { texto: 'Alterar conta' },
    zoom: 1.5,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
