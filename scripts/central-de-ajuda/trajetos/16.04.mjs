// Roteiro do vídeo de trajeto do artigo 16.04 — "Configurações da
// Prospecção". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/prospecting.json (chave
// PROSPECTING.SETTINGS.*) e no componente
// ProspectingSettingsPage.vue.
//
// A Prospecção não vem ligada na conta 9 (flag `autonomia_prospecting`) —
// liga pelo mesmo caminho que o 16.01 já usa:
// `Autonomia::Prospecting::Config.enable_for!`, só em dev, idempotente.
//
// Tela da E0 (#691): a conta não cola chave nem ajusta limite. As chaves do
// Google são da plataforma (ENV); a tela só mostra se estão prontas. Para o
// vídeo mostrar o que o cliente vê em produção ("configuradas"), o servidor
// local de gravação sobe com GOOGLE_PLACES_API_KEY e GOOGLE_MAPS_BROWSER_API_KEY
// FICTÍCIAS e o preparar tira a conta do modo de demonstração. O vídeo não
// dispara busca nem chama o Google.
//
// Trajeto (a ordem da aba Geral, #677): Configurações → Prospecção → Funil CRM
// padrão → País da busca → Chaves do Google → Pesquisa de empresa e decisor →
// Consumo → aba Score → Perfil de score e pesos → Salvar.

export const id = '16.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
Autonomia::Prospecting::Config.enable_for!(conta)
# Tela como o cliente vê em produção: conta fora do modo de demonstração
# (a chave do Google vem do ENV do servidor local de gravação, fictícia).
setting = Autonomia::Prospecting::Setting.find_by!(account_id: conta.id)
setting.update!(provider: 'google_places') unless setting.provider == 'google_places'
# O vídeo mostra o uso do dia a dia: sem o balão de apresentação do Guia (#697).
usuario = conta.users.find_by!(name: '${login.usuarioNome}')
usuario.update!(ui_settings: (usuario.ui_settings || {}).merge('autonomia_guide_intro_seen' => true, 'autonomia_guide_opened' => true))
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Configurar a Prospecção',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/prospecting`,
    aguardarTexto: 'Chaves do Google',
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Escolha o Funil CRM padrão',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="Funil CRM padrão"]' },
    valor: 'Funil Comercial',
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o País da busca',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="País da busca"]' },
    valor: 'BR',
    zoom: 1.8,
  },
  {
    legenda: 'Confira as Chaves do Google',
    acao: 'parar',
    alvo: { texto: 'Chaves do Google' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Confira a Pesquisa de empresa e decisor',
    acao: 'parar',
    alvo: { texto: 'Pesquisa de empresa e decisor' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Confira o Consumo diário e mensal',
    acao: 'parar',
    alvo: { texto: 'Consumo diário', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Abra a aba Score',
    acao: 'mover e clicar',
    alvo: { texto: 'Score' },
    zoom: 1.8,
    aguardarTextoDepois: 'Perfil de score',
  },
  {
    legenda: 'Escolha um Perfil de score, ou Customizado',
    acao: 'parar',
    alvo: { texto: 'Perfil de score', blocoRolagem: 'start' },
    zoom: 1.5,
    duracaoMs: 1800,
  },
  {
    legenda: 'Veja os pesos do perfil escolhido',
    acao: 'parar',
    alvo: { texto: 'Pesos do perfil' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Salvar',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
];
