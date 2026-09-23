// Roteiro do vídeo de trajeto do artigo 00.09 — "Passo 8 — Preparar a
// primeira campanha". Grava no servidor com os flags de campanha ligados
// (http://localhost:3005). Caminho por E-MAIL: o seletor de caixa do
// WhatsApp Oficial continua vazio mesmo com CRM_AI/EMAIL/WHATSAPP_API
// habilitados (nenhuma inbox aparece na lista, em nenhum dos dois
// servidores) — o artigo permite o caminho alternativo por e-mail, que
// funciona neste servidor (EMAIL_CAMPAIGN_ENABLED=true).
//
// Cria a campanha como RASCUNHO (botão "Salvar rascunho") e NUNCA clica em
// Enviar agora/Agendar — esses botões só existem DEPOIS, na lista de
// campanhas, e não são alcançados aqui.

export const id = '00.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3005';

// Fixture fica no repositório (não no scratchpad da sessão): o roteiro
// precisa continuar reproduzível em outra sessão/agente.
const CSV_BASE_CAMPANHA = new URL(
  '../fixtures/base-campanha-teste.csv',
  import.meta.url
).pathname;

// Nada a preparar: cria uma campanha nova (rascunho) a cada gravação; não
// precisa de estado prévio. Não haverá acúmulo de rascunhos-fantasma
// relevante para o vídeo (cada um só mostra o formulário preenchido).

export const cenas = [
  {
    legenda: 'Preparar a primeira campanha',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Campanhas de e-mail',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/campaigns/email_campaigns`,
    aguardarTexto: 'Nova campanha de e-mail',
    zoom: 1.2,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Nova campanha de e-mail',
    acao: 'mover e clicar',
    alvo: { texto: 'Nova campanha de e-mail' },
    aguardarTextoDepois: 'Nome da campanha',
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o nome da campanha',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: Boletim de junho"]' },
    texto: ['Renovação de seguro auto'],
    zoom: 1.8,
  },
  {
    // "Domínio de envio" é um <select> nativo (achado na prática, não no
    // código — violação da regra "sem select nativo" que não é deste
    // vídeo para arrumar). <option> não tem retângulo próprio pra clicar;
    // usa a ação "selecionar" em vez de "mover e clicar".
    legenda: 'Escolha o domínio de envio',
    acao: 'selecionar',
    alvo: { seletor: 'select' },
    valor: 'ses:1',
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o nome do remetente',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: Marketing Acme"]' },
    texto: ['Corretora Desnorteada'],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o e-mail do remetente',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: promo@suaempresa.com"]' },
    texto: ['renovacao@desnorteada.test'],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha Responder para',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: suporte@suaempresa.com"]' },
    texto: ['atendimento@desnorteada.test'],
    zoom: 1.8,
  },
  {
    legenda: 'Suba a base de contatos',
    acao: 'anexarArquivo',
    alvo: { texto: 'Escolher arquivo' },
    seletorArquivo: 'input[type="file"]',
    arquivo: CSV_BASE_CAMPANHA,
    zoom: 1.8,
  },
  {
    legenda: 'Confira o formulário preenchido',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    // "Salvar rascunho" cria a campanha (o passo do artigo termina aqui);
    // não é "Enviar agora" nem "Agendar" — esses ficam para depois, na
    // etapa de destinatários, fora deste vídeo.
    legenda: 'Clique em Salvar rascunho',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar rascunho' },
    aguardarTextoDepois: 'salva',
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
