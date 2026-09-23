// Roteiro do vídeo de trajeto do artigo 04.02 — "Convidar uma pessoa para
// o time". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agentMgmt.json.
//
// Trajeto: Configurações → Agentes → Adicionar Agente → nome → e-mail →
// caixas de entrada.
//
// Este modal (AddAgent.vue) fica sobre a tela normal de Agentes, sem
// nenhum assistente com marca — confirmado com scripts/central-de-ajuda/
// ../diag (nenhum termo proibido na página, e os campos do formulário
// ficam centralizados em x≈640, longe de qualquer coluna de marca). Por
// isso os zooms aqui seguem o padrão do modelo (1,5–2×), bem abaixo do
// teto de 2,5×.
//
// Serviço de fora (convite por e-mail): o vídeo pára com o formulário
// preenchido, sem clicar em "Adicionar agente" — esse clique dispara um
// e-mail de convite de verdade pro endereço digitado.
//
// Achado à parte (não é deste vídeo): o campo "Função" deste mesmo modal
// usa um <select> nativo do navegador, contra a regra do Rodrigo de
// 18/09/2026. Reportado como tarefa separada; o roteiro não interage com
// esse campo (a Função já nasce em "Agente", que é uma escolha válida).

export const id = '04.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

// Não envia nada (o convite nunca é enviado) — não há estado para
// preparar nem para limpar.
export const preparar = null;

export const cenas = [
  {
    legenda: 'Convidar uma pessoa para o time',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/agents/list`,
    aguardarTexto: 'Adicionar Agente',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Adicionar Agente',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar Agente' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o nome da pessoa',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Por favor, insira o nome do agente"]',
    },
    texto: ['Carla Mendes'],
    zoom: 1.6,
  },
  {
    legenda: 'Escreva o e-mail dela',
    acao: 'digitar',
    alvo: {
      seletor:
        'input[placeholder="Por favor, insira um endereço de e-mail do agente"]',
    },
    texto: ['carla.mendes@desnorteada.test'],
    zoom: 1.6,
  },
  {
    legenda: 'Escolha as caixas de entrada',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[placeholder="Selecione caixas de entrada"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Marque a caixa certa',
    acao: 'mover e clicar',
    alvo: { texto: 'WhatsApp Comercial' },
    zoom: 1.6,
  },
  {
    // Fecho: mostra "Adicionar agente" em destaque, sem clicar (dispararia
    // um e-mail de convite de verdade).
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Adicionar agente' },
    zoom: 1.8,
    duracaoMs: 2000,
  },
];
