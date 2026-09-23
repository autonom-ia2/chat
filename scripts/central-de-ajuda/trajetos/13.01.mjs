// Roteiro do vídeo de trajeto do artigo 13.01 — "Os cinco tipos de
// campanha: qual usar". Cobre só o passo 1 do "Como faz" (abrir o menu
// Campanhas e escolher o tipo) — dos cinco tipos, só três aparecem neste
// ambiente: WhatsApp API exige WHATSAPP_API_CAMPAIGNS_ENABLED e Campanhas
// de e-mail exige EMAIL_CAMPAIGN_ENABLED, nenhuma das duas ligada no
// servidor local (ver relatório). Criar uma campanha de verdade em
// qualquer um dos três tipos disponíveis não dá para gravar: WhatsApp
// Oficial e SMS exigem escolher uma caixa/modelo aprovado por fora
// (Meta/Twilio) antes do envio, e Chat ao vivo exige uma caixa de site, que
// esta conta não tem. Por isso o vídeo é só o giro pelo menu.
//
// A lista de cada aba tem campanhas de exemplo pré-existentes na conta
// (seed do produto, não criadas por este vídeo) com texto em inglês — o
// enquadramento de cada cena mira a barra lateral, não a lista, para não
// aparecerem na gravação. A aba Chat ao vivo ficou de fora do giro: a
// campanha de exemplo dela tem "Chatwoot" no próprio texto da mensagem
// ("Hi! Chatwoot here...") perto o bastante do item do menu para entrar no
// recorte mesmo com zoom baixo — sem exceder os 2,5× permitidos para
// escapar dela, a aba não entra nesta gravação.

export const id = '13.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Os tipos de campanha',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1500,
  },
  {
    legenda: 'Abra o menu Campanhas',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Campaigns"]' },
    zoom: 1.8,
  },
  {
    legenda: 'WhatsApp Oficial usa modelo aprovado',
    acao: 'mover e clicar',
    alvo: { texto: 'WhatsApp Oficial' },
    zoom: 1.8,
  },
  {
    legenda: 'Exige modelo aprovado pela Meta',
    acao: 'parar',
    alvo: { texto: 'WhatsApp Oficial' },
    zoom: 1.8,
    duracaoMs: 2200,
  },
  {
    legenda: 'SMS dispara uma vez, agendado',
    acao: 'mover e clicar',
    alvo: { texto: 'SMS' },
    zoom: 1.8,
  },
  {
    legenda: 'Depois de concluída, só dá para excluir',
    acao: 'parar',
    alvo: { texto: 'SMS' },
    zoom: 1.8,
    duracaoMs: 2200,
  },
  {
    // Sem zoom 1 aqui: a tela cheia mostraria a lista de campanhas de
    // exemplo da conta (dado de seed do produto, em inglês) atrás do menu.
    // Mantém o mesmo recorte fechado na barra lateral do clique anterior.
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'SMS' },
    zoom: 1.8,
    duracaoMs: 1500,
  },
];
