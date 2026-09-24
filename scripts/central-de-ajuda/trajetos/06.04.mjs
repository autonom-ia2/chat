// Roteiro do vídeo de trajeto do artigo 06.04 — "Trocar a chave e o
// diagnóstico 'a IA parou'". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/integrationApps.json (chave
// INTEGRATION_APPS.STATUS.*) e nos componentes
// routes/dashboard/settings/integrations/IntegrationItem.vue (grade) e
// routes/dashboard/settings/integrations/SingleIntegrationHooks.vue
// (cartão aberto).
//
// Pedido do Rodrigo: a conta já tem uma chave conectada — mostrar ONDE se
// troca, sem desconectar de verdade. Vídeo só de leitura: não mexe no hook
// crm_kanban_ai (id 1) já existente na conta 9.
//
// Servidor: precisa de CRM_AI_ENABLED, ligado nos dois servidores deste
// lote (P2) — sem precisar do combinado do P1 (baseUrl 3005 já dado no
// pedido).
//
// Trajeto: Integrações (grade, primeiro diagnóstico do roteiro do artigo —
// "confira se o cartão está Ativado") → cartão CRM Kanban IA aberto (2º
// diagnóstico — "Conectado e funcionando" ou "Conectado, mas desligado") →
// Desconectar (onde se troca a chave, sem clicar).
//
// Grade de canais (Index.vue) é lenta pra sair do spinner (4-9s, mesma nota
// de 06.01) — aceito aqui só pra mostrar o selo "Ativado", que não existe
// na tela do cartão aberto. O resto do vídeo pula pra URL direta do
// cartão, como 06.01/06.02 já fazem.

export const id = '06.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

// Vídeo só de leitura — nada é criado, alterado nem desconectado.
export const preparar = null;

export const cenas = [
  {
    legenda: 'Trocar a chave da IA, sem perder o histórico',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations`,
    aguardarTexto: 'CRM Kanban IA',
    zoom: 1,
    duracaoMs: 3000,
  },
  {
    legenda: 'Confira se o cartão está Ativado',
    acao: 'parar',
    alvo: { texto: 'CRM Kanban IA' },
    zoom: 1.8,
    duracaoMs: 3400,
  },
  {
    // Pula pra URL direta do cartão — clicar em "Configurar" no cartão
    // fica perto demais da coluna com o texto de marca no topo desta
    // grade (mesma nota de 06.01), sem zoom seguro ≤2,5×.
    legenda: 'Abra o cartão da integração',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/crm_kanban_ai`,
    aguardarTexto: 'CRM Kanban IA',
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Veja se está conectado e funcionando',
    acao: 'parar',
    alvo: { texto: 'Conectado e funcionando' },
    zoom: 1.8,
    duracaoMs: 3200,
  },
  {
    // Fecho: mostra onde se troca (Desconectar → Conectar de novo com a
    // chave nova), sem clicar — não mexe no hook já conectado.
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Desconectar' },
    zoom: 1.8,
    duracaoMs: 3400,
  },
];
