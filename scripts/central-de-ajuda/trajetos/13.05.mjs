// Roteiro do vídeo de trajeto do artigo 13.05 — "Adicionar e verificar um
// domínio de envio de e-mail". Gravado em http://localhost:3005
// (EMAIL_CAMPAIGN_ENABLED=true).
//
// Para no formulário preenchido, sem clicar em "Adicionar domínio": esse
// clique chama a AWS SES de verdade (Api::V1::.../SenderIdentitiesController
// #create → EmailCampaigns::Ses::IdentityProvisioner), não só o botão
// "Verificar agora" — é um serviço de fora, coberto pela mesma regra do
// coordenador ("não peça a verificação, que chama serviço de fora").
// Domínio de exemplo, nunca enviado.

export const id = '13.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

export const cenas = [
  {
    legenda: 'Adicionar domínio de envio',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1500,
  },
  {
    legenda: 'Abra Domínios de envio de e-mail',
    acao: 'ir para',
    url: `/app/accounts/${9}/campaigns/email_sender`,
    aguardarTexto: 'Domínios de envio de e-mail',
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Um domínio verificado uma vez, vale sempre',
    acao: 'parar',
    alvo: { texto: 'Verificado' },
    zoom: 1.6,
    duracaoMs: 2800,
  },
  {
    legenda: 'Clique em Adicionar domínio de envio',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar domínio de envio' },
    zoom: 1.8,
  },
  {
    legenda: 'Digite o domínio',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: mail.suaempresa.com"]' },
    texto: ['envio.desnorteada.test'],
    zoom: 1.8,
  },
  {
    legenda: 'Remetente padrão é opcional',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: marketing@suaempresa.com"]' },
    texto: ['contato@desnorteada.test'],
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui — não adicione ainda',
    acao: 'parar',
    alvo: { texto: 'Adicionar domínio' },
    zoom: 1.6,
    duracaoMs: 3000,
  },
];
