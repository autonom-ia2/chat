// Roteiro do vídeo de trajeto do artigo 04.06 — "Criar, aplicar e editar
// uma função personalizada". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/customRole.json.
//
// Trajeto: Configurações → Funções Personalizadas → Nova função → perfil
// "Atendente" → Continuar → nome/para quem é → Criar função → Fazer depois.

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
    legenda: 'Clique em Nova função',
    acao: 'mover e clicar',
    alvo: { texto: 'Nova função' },
    zoom: 1.8,
    aguardarTextoDepois: 'Para quem é esta função?',
  },
  {
    legenda: 'Escolha o perfil mais parecido',
    acao: 'mover e clicar',
    alvo: { texto: 'Atendente' },
    zoom: 1.6,
  },
  {
    legenda: 'Continue com o perfil',
    acao: 'mover e clicar',
    alvo: { texto: 'Continuar com Atendente' },
    zoom: 1.6,
    aguardarTextoDepois: 'Ajuste o que for diferente',
  },
  {
    legenda: 'Dê um nome à função',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: Atendente noturno"]' },
    limparAntes: true,
    texto: [NOME_FUNCAO],
    zoom: 1.8,
  },
  {
    legenda: 'Diga para quem é',
    acao: 'digitar',
    alvo: {
      seletor:
        'input[placeholder="Ex.: Equipe de plantão que atende só as próprias conversas"]',
    },
    texto: ['Atende sinistros da regional Norte, sem acesso a faturamento'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar função',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar função' },
    zoom: 1.8,
    aguardarTextoDepois: 'Quem vai usar esta função?',
  },
  {
    legenda: 'Atribua depois, em Configurações → Agentes',
    acao: 'mover e clicar',
    alvo: { texto: 'Fazer depois' },
    zoom: 1.6,
    aguardarTextoDepois: NOME_FUNCAO,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
