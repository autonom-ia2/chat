// Roteiro do vídeo de trajeto do artigo 07.10 — "Criar uma caixa dos outros
// canais". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json (chaves
// INBOX_MGMT.ADD.AUTH.CHANNEL.TELEGRAM e INBOX_MGMT.ADD.TELEGRAM_CHANNEL.*).
//
// Trajeto: Configurações → Caixas de Entrada → Adicionar Caixa de Entrada →
// cartão Telegram → formulário com Bot Token de exemplo. O vídeo PARA aí —
// não clica em "Criar canal do Telegram" (pedido do Rodrigo: até o
// formulário preenchido, sem criar/conectar).
//
// Por que Telegram e não outro cartão do artigo: é o único, dos sete
// cartões que o artigo lista (Instagram, Facebook, SMS, Telegram, API,
// Line, Voz), com um formulário de página inteira (sem pop-up/OAuth real)
// e um único campo de credencial — cabe inteiro no vídeo sem precisar de
// serviço externo nenhum. Facebook/Instagram abririam OAuth de verdade;
// SMS e Line têm formulário maior demais para 40s com folga.
//
// Bot Token: "123456:EXEMPLO-nao-e-uma-chave-real" é claramente fictício
// (a regra que proíbe token legível vale para token DE VERDADE — aqui não
// existe nenhum, é dado de exemplo como o artigo pede).

export const id = '07.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Bia Admin',
};

export const baseUrl = 'http://localhost:3005';

const BOT_TOKEN_EXEMPLO = '123456:EXEMPLO-nao-e-uma-chave-real';

// Idempotente: nada é criado neste roteiro (o vídeo para antes do clique
// que criaria o canal) — preparar só existe para o padrão do lote, sem
// nada a limpar.
export async function preparar() {
  // nada a preparar: o vídeo não cria estado nenhum na conta.
}

export const cenas = [
  {
    legenda: 'Criar uma caixa dos outros canais',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/new`,
    aguardarTexto: 'Telegram',
    zoom: 1.6,
    duracaoMs: 3200,
  },
  {
    legenda: 'Clique no cartão Telegram',
    acao: 'mover e clicar',
    alvo: { texto: 'Telegram' },
    zoom: 1.8,
    aguardarTextoDepois: 'Bot Token',
  },
  {
    legenda: 'Cole o Bot Token do BotFather',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Bot Token"]' },
    texto: [BOT_TOKEN_EXEMPLO],
    zoom: 1.8,
  },
  {
    legenda: 'Veja o campo preenchido',
    acao: 'parar',
    alvo: { seletor: 'input[placeholder="Bot Token"]' },
    zoom: 1.8,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Criar canal do Telegram' },
    zoom: 1.6,
    duracaoMs: 3200,
  },
];
