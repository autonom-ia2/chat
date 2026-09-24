// Roteiro do vídeo de trajeto do artigo 04.06 — "Criar, aplicar e editar
// uma função personalizada". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/customRole.json.
//
// Trajeto: Configurações → Funções Personalizadas → Adicionar função
// personalizada → nome/descrição → modelo "Atendente" (preenche a matriz
// sozinho) → Enviar.

export const id = '04.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_FUNCAO = 'Atendimento Sinistros Norte';

// Idempotente: apaga a função anterior com esse nome exato antes de
// recriar. Nunca mexe em outra função personalizada da conta.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.custom_roles.where(name: ${JSON.stringify(NOME_FUNCAO)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar uma função personalizada',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Configurações → Funções Personalizadas',
    acao: 'ir para',
    // Achado: o path 'raiz' desta seção só redireciona para /list em
    // navegação normal (clique) — via pushState direto o Vue Router não
    // refaz o redirect, e a tela fica presa na Caixa de Entrada. Navega
    // direto para o path final.
    url: `/app/accounts/${login.contaId}/settings/custom-roles/list`,
    aguardarTexto: 'Funções Personalizadas',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Adicionar função personalizada',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar função personalizada' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o nome da função',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Por favor, insira um nome."]' },
    texto: [NOME_FUNCAO],
    zoom: 1.8,
  },
  {
    legenda: 'Escreva a descrição',
    acao: 'digitar',
    alvo: { seletor: 'textarea[placeholder="Por favor, insira uma descrição."]' },
    texto: ['Atende sinistros da regional Norte, sem acesso a faturamento'],
    zoom: 1.8,
  },
  {
    legenda: 'Comece do modelo Atendente',
    acao: 'mover e clicar',
    alvo: { texto: 'Atendente' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Enviar',
    acao: 'mover e clicar',
    alvo: { texto: 'Enviar' },
    zoom: 1.8,
    aguardarTextoDepois: NOME_FUNCAO,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
