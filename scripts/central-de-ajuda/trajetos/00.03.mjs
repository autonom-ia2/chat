// Roteiro do vídeo de trajeto do artigo 00.03 — "Passo 2 — Conectar a
// chave da OpenAI". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{onboardingTrail,integrations,integrationApps}.json
// e config/onboarding/trilha.yml (passo "chave_ia").
//
// Servidor: precisa de CRM_AI_ENABLED, só ligado no servidor auxiliar da
// porta 3005 (mesmo banco, mesmo Vite, agora também com
// CAMPAIGN_IMPORT) — combinado com o coordenador.
//
// PARCIAL, mesmo esquema do 06.02: o hook crm_kanban_ai (id 1) já está
// conectado nesta conta, e o roteiro NÃO mexe nele. Na tela Primeiros
// Passos o passo "Conectar a chave da OpenAI" já aparece "Feito" — sem
// botão "Fazer agora" pra clicar (só passo pendente tem botão). Por isso
// o vídeo lê o passo feito em Primeiros Passos e troca de tela pro cartão
// de verdade (mesmo destino que o passo levaria, settings_applications_
// integration com integration_id=crm_kanban_ai — conferido em
// config/onboarding/trilha.yml), onde mostra "Conectado e funcionando" e
// destaca o botão "Desconectar" (é ali que se troca a chave) sem clicar.
//
// Recorte: nem a tela Primeiros Passos nem o cartão do CRM Kanban IA têm
// texto de marca visível — conferido com scripts/central-de-ajuda/../diag
// (só achei um artefato invisível, 0×0, que a checagem real ignora) — zoom
// solto em tudo.

export const id = '00.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

// Só leitura — não cria, não altera e não desconecta o hook existente.
export const preparar = null;

export const cenas = [
  {
    legenda: 'Passo 2 — Conectar a chave da OpenAI',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/primeiros-passos`,
    aguardarTexto: 'Conectar a chave da OpenAI',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'O passo já está feito nesta conta',
    acao: 'parar',
    alvo: { texto: 'Conectar a chave da OpenAI' },
    zoom: 1.8,
    duracaoMs: 2400,
  },
  {
    // Troca de tela pro cartão de verdade — mesmo destino que o passo
    // levaria (rota settings_applications_integration, integration_id
    // crm_kanban_ai), só que sem precisar de um botão "Fazer agora" que
    // não existe pra passo já feito.
    legenda: 'Abra o cartão CRM Kanban IA',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/crm_kanban_ai`,
    aguardarTexto: 'CRM Kanban IA',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'A chave já está conectada',
    acao: 'parar',
    alvo: { texto: 'Conectado e funcionando' },
    zoom: 1.8,
    duracaoMs: 2600,
  },
  {
    legenda: 'É aqui que se troca a chave',
    acao: 'parar',
    alvo: { texto: 'Desconectar' },
    zoom: 1.8,
    duracaoMs: 4200,
  },
];
