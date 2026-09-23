// Roteiro do vídeo de trajeto do artigo 05.02 — "Criar um time". Rótulos
// conferidos em app/javascript/dashboard/i18n/locale/pt_BR/teamsSettings.json.
//
// Trajeto: Configurações → Times → Criar novo time → nome/descrição →
// Criar novo time → marcar agentes → Adicionar agentes → Finalizar.
//
// Diferente do assistente de caixas (07.02/07.08), o texto do assistente de
// times (TEAMS_SETTINGS.CREATE_FLOW) não menciona marca nenhuma — conferido
// direto no JSON de i18n. Por isso os zooms aqui seguem o padrão do modelo
// (1,5–2×), sem precisar de nenhuma medição apertada.
//
// Tudo aqui é API da própria plataforma (criar time, adicionar agentes) —
// sem serviço de fora, o roteiro completa o fluxo de verdade, até o fim.

export const id = '05.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_TIME = 'Vendas Sul';

// Idempotente: apaga o time anterior (só o nosso, pelo nome — o modelo
// salva em minúsculo) antes de gravar de novo. Não toca em nenhum outro
// time nem em agentes existentes.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_TIME)}
existente = conta.teams.find_by(name: nome.downcase)
existente&.destroy!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar um time',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/teams/new`,
    aguardarTexto: 'Nome do Time',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Escreva o nome do time',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Exemplo: Vendas, Suporte ao Cliente"]',
    },
    texto: [NOME_TIME],
    zoom: 1.6,
  },
  {
    legenda: 'Escreva a descrição',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Breve descrição sobre este time."]' },
    texto: ['Atendimento comercial da região Sul'],
    zoom: 1.6,
  },
  {
    // Por texto, "Criar novo time" bate tanto no título da seção quanto no
    // botão — os dois têm o mesmo texto exato, e o título vem primeiro no
    // DOM. O seletor por type=submit garante o botão certo.
    legenda: 'Clique em Criar novo time',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[type="submit"]' },
    zoom: 1.8,
  },
  {
    // O clique sintético (CDP) no checkbox "marcar todos" do cabeçalho
    // não propagou a seleção pras linhas (confirmado no quadro gravado:
    // caixas de cada agente continuavam vazias). Marca a primeira pessoa
    // da lista em vez disso — mesma ação da tela ("Marque as pessoas que
    // entram no time"), só que uma de cada vez.
    legenda: 'Marque a primeira pessoa da lista',
    acao: 'mover e clicar',
    alvo: { seletor: 'tbody tr:nth-child(1) input[type="checkbox"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Marque a segunda pessoa',
    acao: 'mover e clicar',
    alvo: { seletor: 'tbody tr:nth-child(2) input[type="checkbox"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Adicionar agentes',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar agentes' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Finalizar',
    acao: 'mover e clicar',
    alvo: { texto: 'Finalizar' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1800,
  },
];
