// Roteiro do vídeo de trajeto do artigo 06.02 — "Conectar a chave da
// OpenAI (CRM Kanban IA)". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{integrations,integrationApps}.json.
//
// Servidor: precisa de CRM_AI_ENABLED, só ligado no servidor auxiliar da
// porta 3005 (mesmo banco, mesmo Vite) — combinado com o coordenador.
//
// PARCIAL, por pedido explícito: o hook crm_kanban_ai (id 1) já está
// conectado nesta conta, e o roteiro NÃO mexe nele (nem desconecta, nem
// troca a chave) — só existe formulário "Conectar" (NewHook.vue) quando
// NÃO há hook conectado; com hook conectado, o cartão mostra só o botão
// "Desconectar" (SingleIntegrationHooks.vue), sem edição — o próprio
// artigo confirma isso em "O que dá errado": "Não existe edição para essa
// integração: desconecte e conecte de novo." Por isso este vídeo mostra o
// cartão como está (conectado) e o caminho real pra trocar a chave
// (Desconectar), em vez do formulário de API Key vazio — não dá pra
// gravar o preenchimento sem alterar um dado que não é nosso.
//
// A tela do cartão (SingleIntegrationHooks.vue) não tem nenhum texto de
// marca — conferido com scripts/central-de-ajuda/../diag — zoom solto.

export const id = '06.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

// Só leitura — não cria, não altera e não desconecta o hook existente.
export const preparar = null;

export const cenas = [
  {
    legenda: 'Conectar a chave da OpenAI (CRM Kanban IA)',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/crm_kanban_ai`,
    aguardarTexto: 'CRM Kanban IA',
    zoom: 1,
    duracaoMs: 3600,
  },
  {
    legenda: 'O formulário fica dentro do cartão',
    acao: 'parar',
    alvo: { texto: 'CRM Kanban IA' },
    zoom: 1.8,
    duracaoMs: 3200,
  },
  {
    legenda: 'Esta conta já tem uma chave conectada',
    acao: 'parar',
    alvo: { texto: 'Conectado e funcionando' },
    zoom: 1.8,
    duracaoMs: 3400,
  },
  {
    legenda: 'Pra trocar, é desconectar e conectar de novo',
    acao: 'parar',
    alvo: { texto: 'Desconectar' },
    zoom: 1.8,
    duracaoMs: 4400,
  },
];
