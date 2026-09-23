// Roteiro do vídeo de trajeto do artigo 00.04 — "Passo 3 — Conectar um
// canal". Rótulos conferidos em app/javascript/dashboard/i18n/locale/pt_BR/
// {settings,inboxMgmt}.json.
//
// Trajeto: Caixas de Entrada → Adicionar Caixa de Entrada → escolha do
// canal (WhatsApp Oficial / WhatsApp API / E-mail). Para na tela de escolha:
// qualquer canal a partir daqui abre autorização da Meta, QR Code ou domínio
// de e-mail — todos "formulário que chama serviço de fora" (regra 6 das
// instruções comuns).

export const id = '00.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: só navega e olha a tela de escolha de canal, não cria
// caixa nenhuma.

export const cenas = [
  {
    legenda: 'Conectar um canal',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Caixas de Entrada',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/list`,
    aguardarTexto: 'Adicionar Caixa de Entrada',
    zoom: 1.3,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Adicionar Caixa de Entrada',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar Caixa de Entrada' },
    // Primeira visita à tela "Escolha o Canal" nesta gravação: o Vite em
    // dev demora alguns segundos para compilar a rota. Sem isso, a cena
    // seguinte não acha "WhatsApp Oficial" a tempo.
    aguardarTextoDepois: 'WhatsApp Oficial',
    zoom: 1.6,
  },
  {
    // Mira em "WhatsApp API", não em "WhatsApp Oficial": a legenda descreve
    // os três canais (igual ao "Como faz" do artigo), mas o cartão do
    // WhatsApp Oficial fica na primeira coluna da grade, colado no painel
    // dos 4 passos do assistente — o texto do passo 1 ("Escolha o provedor
    // que você deseja integrar com o [instalação]...") sempre entra no
    // recorte por estar do lado, não em cima (rolar a tela não separa os
    // dois: estão na mesma altura). "WhatsApp API" fica mais à direita, já
    // fora do alcance do recorte.
    legenda: 'Escolha WhatsApp Oficial, API ou e-mail',
    acao: 'parar',
    alvo: { texto: 'WhatsApp API' },
    zoom: 2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Cada canal tem seu próprio passo a passo',
    acao: 'passar o mouse',
    alvo: { texto: 'WhatsApp API' },
    zoom: 2,
    duracaoMs: 1600,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'WhatsApp API' },
    zoom: 2,
    duracaoMs: 2400,
  },
];
