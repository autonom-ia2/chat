// Roteiro do vídeo de trajeto do artigo 07.02 — "Criar a caixa de WhatsApp
// Oficial: cadastro incorporado ou manual". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json (chaves
// INBOX_MGMT.ADD.WHATSAPP.* e INBOX_MGMT.ADD.WHATSAPP.MANUAL_SETUP.*).
//
// Trajeto (roteiro manual — sem app id do WhatsApp configurado neste
// ambiente de dev, o cadastro incorporado com a Meta não aparece e o
// caminho cai direto no manual): WhatsApp Oficial → Cloud do WhatsApp →
// app da Meta pronto → IDs → Próximo → token.
//
// Serviço de fora (Meta): o vídeo pára com o token preenchido, sem clicar
// em "Verificar detalhes" — esse clique chama a Graph API da Meta de
// verdade (WhatsappChannelAPI.previewManualSetup).
//
// Teto de zoom 2,5×: todo este assistente (InboxChannels.vue) tem, na
// coluna da esquerda, um resumo com marca proibida — medido com
// scripts/central-de-ajuda/../diag, a coluna de conteúdo começa em x≈482
// CSS. Os DOIS primeiros cliques da versão anterior deste roteiro (cartão
// "WhatsApp Oficial" no grid de canais, cx≈625; cartão "Cloud do WhatsApp"
// na tela de provedor, cx≈595) ficam perto demais dessa borda — nenhum
// zoom ≤2,5 centralizado neles escapa da coluna. Em vez de "mover e
// clicar" apertado nesses dois, o roteiro troca de tela com "ir para"
// direto pra URL de destino (é a mesma troca de tela que o clique real
// faria; só a demonstração do clique em si que não cabe com segurança).
// O campo "ID do Número de Telefone" (cx≈704) tem o mesmo problema — o
// roteiro mostra só o ID da WABA (cx≈1034, longe da borda) e a legenda
// cobre os dois campos, como o artigo já descreve ("cole os três dados
// coletados").

export const id = '07.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada é criado (o formulário nunca é enviado) — não há estado para
// preparar nem para limpar.
export const preparar = null;

export const cenas = [
  {
    // Abertura fundida com a navegação — mesma razão de 07.08: a página
    // pousada após o login não é confiável.
    legenda: 'Cadastrar o WhatsApp Oficial da Meta',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/new`,
    aguardarTexto: 'WhatsApp Oficial',
    zoom: 2.2,
    duracaoMs: 1800,
  },
  {
    // Troca de tela em vez de clique apertado no cartão — ver nota acima.
    legenda: 'Escolha WhatsApp Oficial',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/new/whatsapp`,
    aguardarTexto: 'Selecione seu provedor de API',
    zoom: 2.2,
    duracaoMs: 1300,
  },
  {
    // Mesma troca de tela — o cartão "Cloud do WhatsApp" também cola na
    // coluna de marca (cx≈595).
    legenda: 'Escolha Cloud do WhatsApp',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/new/whatsapp?provider=whatsapp_manual`,
    aguardarTexto: 'Crie ou selecione um aplicativo da Meta',
    zoom: 2.2,
    duracaoMs: 1300,
  },
  {
    legenda: 'Clique em Meu app está pronto',
    acao: 'mover e clicar',
    alvo: { texto: 'Meu aplicativo da Meta está pronto' },
    zoom: 2.2,
  },
  {
    legenda: 'Cole o ID do número de telefone',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Informe o ID do número de telefone"]',
    },
    texto: ['1234567890123456'],
    zoom: 2.5,
  },
  {
    legenda: 'Cole o ID da conta do WhatsApp Business',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Informe o ID da WABA"]' },
    texto: ['9876543210987654'],
    zoom: 2.2,
  },
  {
    legenda: 'Clique em Próximo',
    acao: 'mover e clicar',
    alvo: { texto: 'Próximo' },
    zoom: 2.2,
  },
  {
    legenda: 'Gere um token de acesso',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Colar token de acesso"]' },
    texto: ['EXEMPLOtoken000111222333444555'],
    zoom: 2.2,
  },
  {
    // Fecho: mostra o botão "Verificar detalhes" em destaque, sem clicar
    // (chamaria a Graph API da Meta de verdade).
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Verificar detalhes' },
    zoom: 2.2,
    duracaoMs: 2200,
  },
];
