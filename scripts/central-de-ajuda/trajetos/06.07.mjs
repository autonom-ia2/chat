// Roteiro do vídeo de trajeto do artigo 06.07 — "Conectar Slack, Linear,
// Notion e a loja Shopify". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/integrations.json (chaves
// INTEGRATION_SETTINGS.{SLACK,LINEAR,NOTION,SHOPIFY}.*).
//
// Pedido do Rodrigo: só os cartões e o formulário — nada de OAuth de
// verdade. Slack, Linear e Notion abrem direto a janela de autorização do
// serviço ao clicar Conectar (sem formulário no meio) — por isso o vídeo só
// MOSTRA os três cartões, sem clicar. Shopify é diferente: "Conectar" abre
// um diálogo local (Shopify.vue) com o campo da URL da loja, e só o
// SUBMIT desse diálogo chama a API de verdade (connectShopify, que devolve
// um redirect_url da Shopify) — por isso dá pra clicar em "Conectar" e
// preencher a URL da loja, sem clicar no envio do diálogo.
//
// Cada página de integração é aberta por URL direta (não pela grade
// Index.vue) — mesma razão de 06.01/06.04: a grade é lenta pra carregar e
// tem texto de marca colado no topo; a tela de uma integração aberta não
// tem esse problema (conferido nos vídeos anteriores do lote).

export const id = '06.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

// Vídeo só de leitura + formulário não enviado — nada é criado nem
// conectado de verdade.
export const preparar = null;

export const cenas = [
  {
    legenda: 'Conectar Slack, Linear, Notion e Shopify',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/slack`,
    aguardarTexto: 'Slack',
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Slack recebe uma cópia das conversas',
    acao: 'parar',
    alvo: { texto: 'Slack' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    // Sem alvo, "ir para" recorta centrado no meio do viewport (retângulo
    // nulo) — o card fica perto do topo da página, então zoom > 1 aqui
    // cortaria o conteúdo pra fora do quadro. zoom 1 mostra a tela inteira.
    legenda: 'Linear cria tarefas a partir delas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/linear`,
    aguardarTexto: 'Linear',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Notion dá acesso a documentos ao Capitão',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/notion`,
    aguardarTexto: 'Notion',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Shopify traz dados da loja pro atendimento',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/shopify`,
    aguardarTexto: 'Shopify',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    // Só em Shopify o clique em "Conectar" abre formulário local (as
    // outras três abririam OAuth real).
    legenda: 'Em Shopify, clique em Conectar',
    acao: 'mover e clicar',
    alvo: { texto: 'Conectar' },
    zoom: 1.8,
    aguardarTextoDepois: 'URL da Loja',
  },
  {
    legenda: 'Digite o endereço da loja',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="your-store.myshopify.com"]' },
    texto: ['corretora-desnorteada.myshopify.com'],
    zoom: 1.8,
  },
  {
    // O diálogo usa o rótulo padrão de confirmação do componente Dialog
    // ("Confirmar", DIALOG.BUTTONS.CONFIRM) — não clicado, chamaria a API
    // de conexão de verdade (connectShopify, que devolve redirect_url da
    // Shopify).
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Confirmar' },
    zoom: 1.6,
    duracaoMs: 2200,
  },
];
