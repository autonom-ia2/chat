// Roteiro do vídeo de trajeto do artigo 05.07 — "Escolher como as
// conversas são distribuídas: atribuição e capacidade". Rótulos conferidos
// em app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (ASSIGNMENT_POLICY.*).
//
// Trajeto: Configurações → Atribuição de Agentes → cartão Política de
// atribuição → Nova política → nome/descrição → Criar política (a tela já
// leva para a edição, com as Caixas de entrada adicionadas).

export const id = '05.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const POLICY_NAME = 'Rodízio comercial Sul';

// Idempotente: apaga a política anterior com esse nome antes de recriar.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.assignment_policies.where(name: ${JSON.stringify(POLICY_NAME)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Escolher como as conversas são distribuídas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Configurações → Atribuição de Agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/assignment-policy`,
    aguardarTexto: 'Política de atribuição',
    zoom: 1,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Política de atribuição',
    acao: 'mover e clicar',
    alvo: { texto: 'Política de atribuição' },
    zoom: 1.6,
    aguardarTextoDepois: 'Nova política',
  },
  {
    legenda: 'Clique em Nova política',
    acao: 'mover e clicar',
    alvo: { texto: 'Nova política' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o nome da política',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Informe o nome da política"]' },
    texto: [POLICY_NAME],
    zoom: 1.8,
  },
  {
    legenda: 'Escreva a descrição',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Insira a descrição"]' },
    texto: ['Rodízio das conversas do time comercial da região Sul'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar política',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[type="submit"]' },
    zoom: 1.6,
    aguardarTextoDepois: 'Caixas de entrada adicionadas',
  },
  {
    legenda: 'Vincule as caixas de entrada aqui',
    acao: 'parar',
    alvo: { texto: 'Caixas de entrada adicionadas' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
