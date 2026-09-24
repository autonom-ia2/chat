// Roteiro do vídeo de trajeto do artigo 10.12 — "Origem do lead e
// conversões para Meta e Google Ads". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json (chaves
// CRM_KANBAN.ORIGIN.*, CRM_KANBAN.GOOGLE_SYNC.*,
// CRM_KANBAN.PIPELINE_DRAWER.META_SYNC_*) e no componente
// CrmPipelineDrawer.vue.
//
// Selo de origem: card.campaigns vem de
// Crm::Cards::PayloadBuilder.aggregated_campaigns_for, que lê
// conversation.additional_attributes['campaign_touches'] — um array de
// toques {source, source_id, source_type, headline, source_url,
// touched_at}. `preparar` grava um toque "meta_ctwa" na conversa
// primária de um card já existente (pipeline "Funil Comercial", conta 9),
// só para o vídeo ter o que mostrar. Idempotente: sempre substitui pelo
// mesmo toque de exemplo.
//
// Conversões: liga só o toggle da Meta Ads (checkbox) e preenche o
// Dataset ID com dado de exemplo — campo de formulário local (só
// persiste quando o funil inteiro é salvo). O vídeo NÃO clica em Salvar o
// funil: evita qualquer efeito colateral na automação de stages de quem
// usa essa conta.
//
// CUIDADO (achado do Rodrigo, 24/09, 2ª revisão): a versão anterior deste
// roteiro ligava TAMBÉM o toggle do Google Ads, e a cena seguinte (o
// toggle da Meta) saiu com um recorte largo — não o zoom apertado de
// sempre — que incluía a "URL da importação programada" do Google Ads
// LEGÍVEL, com "localhost" e o token do feed. Causa: o checkbox real por
// trás desses dois toggles é `class="peer sr-only"` (oculto visualmente,
// só a <span> ao lado desenha o botão) — o motor mede o retângulo do
// próprio <input>, não da <span> visível, e essa medição saiu maior que o
// esperado (por isso o recorte não ficou apertado). Isso é um limite do
// motor com toggle acessível (sr-only); registrado, mas não mexido aqui
// (motor CONGELADO no P3).
//
// Correção estrutural, não um recorte mais apertado: este roteiro NUNCA
// LIGA o toggle do Google Ads — o painel com a URL simplesmente não
// existe no DOM (é `v-if="form.googleSync.enabled"`) se a chave continua
// desligada, então nenhum recorte, apertado ou largo, pode expor uma URL
// que não foi renderizada. O vídeo só MOSTRA o título da seção Google Ads
// (parar, sem tocar no toggle) e completa de verdade só a metade da Meta
// Ads, que não tem nenhum dado secreto — Dataset ID é um identificador
// que o próprio administrador cola, não um link com token de acesso.
//
// Trajeto: CRM Kanban → ver o selo de origem no card → passar o mouse →
// Editar funil → mostrar a seção Google Ads (sem ligar) → ligar Enviar
// conversões para a Meta → Dataset ID → parar antes de salvar.

export const id = '10.12';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const CARD_ID = 33; // card no pipeline "Funil Comercial" (id 12), conta 9 — o único com conversa principal

export async function preparar({ rodarRails }) {
  await rodarRails(`
card = Crm::Card.find(${CARD_ID})
raise "card não pertence à conta ${login.contaId}" unless card.account_id == ${login.contaId}
conversa = card.primary_conversation
raise "card sem conversa principal" unless conversa

attrs = (conversa.additional_attributes || {}).dup
attrs['campaign_touches'] = [
  {
    'source' => 'meta_ctwa',
    'source_id' => 'exemplo-desnorteada-001',
    'source_type' => 'ad',
    'headline' => 'Seguro Auto - clique para WhatsApp',
    'source_url' => 'https://www.facebook.com/ads/exemplo-desnorteada',
    'touched_at' => 2.days.ago.iso8601,
  },
]
conversa.update!(additional_attributes: attrs)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ver a origem do lead e as conversões',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/crm`,
    aguardarTexto: 'Novo card',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    // Achado de produto: o seletor de funil (CRM_KANBAN.FILTERS.PIPELINE)
    // é um <select> nativo do navegador — proibido pela regra do Rodrigo
    // (18/09/2026). Usa a ação "selecionar" do motor, sem alternativa hoje.
    legenda: 'Escolha o funil Funil Comercial',
    acao: 'selecionar',
    alvo: { seletor: 'select' },
    valor: 'Funil Comercial',
    zoom: 1.8,
  },
  {
    legenda: 'O selo de origem fica abaixo das etiquetas',
    acao: 'parar',
    alvo: { texto: 'Meta clique para WhatsApp: Seguro Auto - clique para WhatsApp' },
    zoom: 1.6,
    duracaoMs: 2200,
  },
  {
    legenda: 'Passe o mouse para ver a URL de origem',
    acao: 'passar o mouse',
    alvo: { texto: 'Meta clique para WhatsApp: Seguro Auto - clique para WhatsApp' },
    zoom: 1.8,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Editar funil',
    acao: 'mover e clicar',
    alvo: { texto: 'Editar funil' },
    zoom: 1.8,
    aguardarTextoDepois: 'Enviar conversões para a Meta (Ads)',
  },
  {
    // Só observa o título — NUNCA liga esta chave (ver o comentário do
    // topo do arquivo: ligá-la abriria o painel com a URL secreta do
    // feed do Google Ads).
    legenda: 'Google Ads também recebe conversões',
    acao: 'parar',
    alvo: { texto: 'Google Ads (conversões offline)', blocoRolagem: 'start' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Ligue Enviar conversões para a Meta',
    acao: 'mover e clicar',
    alvo: { seletor: 'input.peer.sr-only:not([aria-label])' },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o Dataset ID da Meta',
    acao: 'digitar',
    alvo: {
      seletor:
        'input[placeholder="Preenchido automaticamente após a verificação da conexão"]',
    },
    texto: ['987654321098765'],
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui, antes de salvar o funil',
    acao: 'parar',
    zoom: 1.5,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
];
