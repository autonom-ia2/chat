// Roteiro do vídeo de trajeto do artigo 07.08 — "Criar uma caixa de
// WhatsApp API (QR Code / WAHA)". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json (chave
// INBOX_MGMT.ADD.WHATSAPP_API e INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP_API).
//
// Trajeto: Configurações → Caixas de Entrada → Adicionar Caixa de Entrada →
// WhatsApp API → nome da caixa → telefone. "Atendimento humano" já vem
// selecionado por padrão (não precisa clicar) — ver nota na cena 3.
//
// Serviço de fora (QR Code / WAHA): o vídeo pára com o formulário
// preenchido, sem clicar em "Criar caixa de WhatsApp" — esse clique chama a
// WahaInboxAPI de verdade e cria uma sessão de QR Code.
//
// Teto de zoom 2,5×: todo o assistente de nova caixa (InboxChannels.vue) tem,
// na coluna da esquerda (sempre visível nos 1280px da gravação), um resumo
// com marca proibida — medido com scripts/central-de-ajuda/../diag, a
// coluna de conteúdo começa em x≈482 CSS, e o parágrafo com a marca ocupa
// y≈148–228. O cabeçalho da página e os botões "Atendimento humano"/"Agente
// de IA" ficam bem em cima dessa faixa (y≈105–232) e perto demais da borda
// (x≈510–870) — não existe zoom ≤2,5 que mostre esses dois sem incluir a
// coluna. Por isso o roteiro pula os dois: não há cena parada no cabeçalho
// nem clique no toggle (que já está no valor certo por padrão). O clique
// no cartão "WhatsApp API" e os dois campos de texto ficam mais à direita
// (cx≈869) e cabem com folga a 1,8×.

export const id = '07.08';

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
    // Cena de abertura FUNDIDA com a navegação: a página pousada logo após
    // o login não é confiável (às vezes cai direto num assistente em vez
    // da Central de conversas). Um "parar" de abertura ANTES de qualquer
    // "ir para" arriscaria gravar essa página incerta em zoom 1 (tela
    // cheia), que sempre mostra a coluna de marca. Por isso a abertura já
    // navega direto pro destino, com zoom 2,2 centralizado na grade de
    // canais (a coluna de marca fica acima, fora do recorte).
    legenda: 'Criar caixa de WhatsApp por QR Code',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/new`,
    aguardarTexto: 'WhatsApp API',
    zoom: 2.2,
    duracaoMs: 2600,
  },
  {
    legenda: 'Clique em WhatsApp API',
    acao: 'mover e clicar',
    alvo: { texto: 'WhatsApp API' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o nome da caixa',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: Suporte Viagem"]' },
    texto: ['WhatsApp Atendimento Sul'],
    zoom: 1.8,
  },
  {
    legenda: 'Digite o telefone com DDI 55',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="5511987654321"]' },
    texto: ['5511998765432'],
    zoom: 1.8,
  },
  {
    // Fecho no campo de telefone (já preenchido, seguro a 1,8×) — o botão
    // "Criar caixa de WhatsApp" aparece visível logo abaixo no mesmo
    // recorte, sem anel de destaque (ele está perto demais da coluna de
    // marca pra um zoom ≤2,5 centralizar nele sem incluí-la).
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { seletor: 'input[placeholder="5511987654321"]' },
    zoom: 1.8,
    duracaoMs: 3000,
  },
];
