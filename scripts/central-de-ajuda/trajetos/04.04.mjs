// Roteiro do vídeo de trajeto do artigo 04.04 — "Editar, redefinir senha e
// definir horário (SLA) de um agente". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agentMgmt.json e crm.json
// (CRM_SLA.AGENT, CRM_SLA.SCHEDULES.EDITOR).
//
// Regra do lote: NUNCA clicar em "Redefinir a senha" de verdade (dispara
// e-mail real) — o vídeo mostra até o botão, destacado, sem clicar.
//
// Edita Camila Souza (usuária de teste, sem vínculo com outro vídeo do
// lote). O nome volta ao original no próprio preparar, então a edição do
// texto é sempre a mesma, idempotente.

export const id = '04.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const AGENTE_NOME = 'Camila Souza';
const AGENTE_EMAIL = 'camila.souza@desnorteada.test'; // estável — o nome é o que o vídeo edita

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(email: ${JSON.stringify(AGENTE_EMAIL)})
raise "usuária #{${JSON.stringify(AGENTE_EMAIL)}} não encontrada" unless usuaria
usuaria.update!(name: ${JSON.stringify(AGENTE_NOME)}) unless usuaria.name == ${JSON.stringify(AGENTE_NOME)}
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Editar, redefinir senha e SLA de um agente',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Configurações → Agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/agents/list`,
    aguardarTexto: AGENTE_NOME,
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Pesquise pelo nome da pessoa',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[placeholder="Pesquisar agentes..."]' },
    zoom: 1.6,
  },
  {
    legenda: 'Digite o nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar agentes..."]' },
    texto: ['Camila'],
    zoom: 1.6,
  },
  {
    legenda: 'Clique no lápis da linha',
    acao: 'mover e clicar',
    alvo: { seletor: 'span[class*="i-woot-edit-pen"]' },
    zoom: 1.8,
    aguardarTextoDepois: 'Nome do Agente',
  },
  {
    legenda: 'Ajuste o Nome do Agente',
    acao: 'digitar',
    alvo: { seletor: 'form input[type="text"]' },
    limparAntes: true,
    texto: ['Camila Souza Ferreira'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Editar agente',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[type="submit"]' },
    zoom: 1.6,
    // O clique salva e fecha o modal — espera o nome novo aparecer na
    // lista antes de seguir (senão a cena de depois pega o modal fechando).
    aguardarTextoDepois: 'Camila Souza Ferreira',
  },
  {
    // Reabre o modal (mesmo lápis, mesma linha filtrada) só para mostrar o
    // botão de redefinir a senha — sem clicar nele.
    legenda: 'Reabra a edição da pessoa',
    acao: 'mover e clicar',
    alvo: { seletor: 'span[class*="i-woot-edit-pen"]' },
    zoom: 1.8,
    aguardarTextoDepois: 'Redefinir a senha',
  },
  {
    legenda: 'O botão Redefinir a senha fica aqui',
    acao: 'parar',
    alvo: { texto: 'Redefinir a senha' },
    zoom: 1.8,
    duracaoMs: 2000,
  },
  {
    legenda: 'Clique em Definir horário de atendimento',
    acao: 'mover e clicar',
    alvo: { texto: 'Definir horário de atendimento' },
    zoom: 1.6,
    aguardarTextoDepois: 'Calendário ativo',
  },
  {
    // Achado na gravação: dentro deste modal (EditAgent) + editor de
    // calendário empilhado (2 diálogos ao mesmo tempo), o clique
    // sintético no interruptor do dia não chega a alternar o dia de
    // verdade com confiabilidade — sem erro, só sem efeito. Em vez de um
    // clique frágil, a cena mostra o formulário completo (fuso horário,
    // dias, blocos) parado — o mesmo conteúdo que 10.15 já mostra
    // clicando de verdade, num contexto sem esse empilhamento.
    legenda: 'Escolha o fuso e os dias',
    acao: 'parar',
    alvo: { texto: 'Calendário ativo' },
    zoom: 1.3,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
