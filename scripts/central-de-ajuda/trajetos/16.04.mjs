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
// Chaves do Google: os campos são `type="password"` de origem
// (ProspectingSettingsPage.vue) — já nascem mascarados, então digitar uma
// chave de exemplo aqui não viola a regra de "nenhuma chave legível". O
// vídeo NÃO clica em Rodar busca nem em nada que chame o Google — Salvar
// só grava a chave (texto) no banco local da conta, não testa contra a
// API do Google.
//
// ACHADO DE PRODUTO: "Funil CRM padrão", "Etapa CRM padrão", "Forma
// padrão de pesquisa" e "Perfil de score" são `<select>` nativos —
// proibido pela regra do Rodrigo (18/09/2026). O roteiro usa a ação
// `selecionar` do motor só no primeiro (Funil CRM padrão); os outros três
// continuam escondidos no DOM quando a aba Score está ativa (a troca de
// aba é só CSS, v-show) — sem seletor CSS único para distingui-los do
// select da aba Geral, este roteiro só os MOSTRA, sem interagir.
//
// Trajeto: Configurações → Prospecção → aba Geral → Funil CRM padrão →
// chave de busca de locais → chave de mapa → Limite diário → Enriquecimento
// manual → Consumo → aba Score → Perfil de score e pesos → Salvar.

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
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Configurar chaves, limites e score da Prospecção',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/prospecting`,
    aguardarTexto: 'Chave para busca de locais',
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Escolha o Funil CRM padrão',
    acao: 'selecionar',
    alvo: { seletor: 'select' },
    valor: 'Funil Comercial',
    zoom: 1.8,
  },
  {
    legenda: 'Cole a chave para busca de locais',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Cole a chave de busca do Google"]' },
    texto: ['AIzaSyDESNORTEADA-exemplo-places-0001'],
    zoom: 1.8,
  },
  {
    legenda: 'Cole a chave para exibir o mapa',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Cole a chave do mapa"]' },
    texto: ['AIzaSyDESNORTEADA-exemplo-maps-0002'],
    zoom: 1.8,
  },
  {
    legenda: 'Ajuste o Limite diário de buscas',
    acao: 'digitar',
    alvo: { seletor: 'input[min="1"]' },
    limparAntes: true,
    texto: ['20'],
    zoom: 1.8,
  },
  {
    legenda: 'Marque Enriquecimento manual',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[type="checkbox"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Confira o Consumo diário e mensal',
    acao: 'parar',
    alvo: { texto: 'Consumo diário', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    // A troca de aba é só CSS (v-show), então os <select> da aba Geral
    // continuam no DOM, escondidos — document.querySelector('select')
    // sempre acharia o primeiro (Funil CRM), não o desta aba. Por isso
    // esta cena só observa o perfil de score, sem interagir com o
    // <select> — evitar um seletor ambíguo é melhor que um alvo errado.
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
