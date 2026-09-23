// Roteiro do vídeo de trajeto do artigo 13.06 — "Criar a campanha de
// e-mail e escolher como montar". Gravado em http://localhost:3005
// (EMAIL_CAMPAIGN_ENABLED=true).
//
// Para no formulário preenchido, sem clicar em "Criar e abrir no editor"
// nem em "Salvar rascunho" — regra do coordenador para os vídeos de
// campanha. Não há domínio de envio verificado nesta conta (a verificação
// chama serviço de fora, proibida em 13.05) — o aviso "Nenhum domínio de
// envio verificado ainda" que aparece é o estado real, e também é um dos
// casos que o próprio artigo descreve em "O que dá errado". A "Lista de
// contatos (CSV ou XLSX)" fica só com o botão "Escolher arquivo" à vista,
// sem anexar nada — mesma razão do 13.04 (sem ação de upload no motor).

export const id = '13.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

export const cenas = [
  {
    legenda: 'Criar campanha de e-mail',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 900,
  },
  {
    legenda: 'Abra o menu Campanhas',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Campaigns"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra Campanhas de e-mail',
    acao: 'mover e clicar',
    alvo: { texto: 'Campanhas de e-mail' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Nova campanha de e-mail',
    acao: 'mover e clicar',
    alvo: { texto: 'Nova campanha de e-mail' },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o nome da campanha',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: Boletim de junho"]' },
    texto: ['Renovação de outubro'],
    zoom: 1.8,
  },
  {
    legenda: 'Sem domínio verificado, sem remetente',
    acao: 'parar',
    alvo: { texto: 'Nenhum domínio de envio verificado ainda. Adicione e verifique um em Domínios de envio de e-mail primeiro.' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Preencha o nome do remetente',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: Marketing Acme"]' },
    texto: ['Corretora Desnorteada'],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o remetente',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: promo@suaempresa.com"]' },
    texto: ['contato@desnorteada.test'],
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
    legenda: 'Suba a lista de contatos',
    acao: 'parar',
    alvo: { texto: 'Escolher arquivo' },
    zoom: 1.6,
    duracaoMs: 1400,
  },
  {
    legenda: 'Pare aqui — não envie',
    acao: 'parar',
    zoom: 1.4,
    alvo: { texto: 'Escolher arquivo' },
    duracaoMs: 1200,
  },
];
