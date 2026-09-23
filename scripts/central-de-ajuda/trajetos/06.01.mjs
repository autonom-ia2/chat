// Roteiro do vídeo de trajeto do artigo 06.01 — "Abrir Integrações e ler
// um cartão". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{integrations,integrationApps}.json.
//
// Servidor: este vídeo precisa de CRM_AI_ENABLED, que só está ligado no
// servidor auxiliar da porta 3005 (mesmo banco, mesmo Vite) — combinado
// com o coordenador. Não mexe no hook crm_kanban_ai existente (id 1); ele
// já está conectado nesta conta, então o cartão aparece "Conectado e
// funcionando" em vez de "Comece por aqui" (os dois estados são reais,
// o artigo descreve ambos).
//
// Recorte: a tela de Integrações (Index.vue) tem uma descrição visível no
// topo ("Autonom.ia se integra com..." — texto de marca de verdade, não
// artefato invisível) ocupando y≈56–98 em toda a largura útil, e os
// cartões da grade começam colados na borda esquerda (x≈224). Medido com
// scripts/central-de-ajuda/../diag: não existe zoom ≤2,5× que centralize
// no cartão "CRM Kanban IA" (cx≈295) sem incluir a coluna da esquerda, e
// nenhum que mostre a busca (cx≈340, y≈130) sem tocar a descrição do
// topo.
//
// Grade de canais precisa de motor: essa mesma tela de Integrações
// (Index.vue) demorou de 4 a 9s reais pra sair do spinner de carregamento
// em todo teste (gravado e conferido quadro a quadro — tela em branco com
// spinner do início ao fim da cena, mesmo depois do "ir para" já ter
// achado o texto do cartão no innerText). Não é o motor de gravação (ele
// não toca nesse comportamento) — parece ser a própria tela de
// Integrações demorando bem mais que as outras telas do painel pra
// buscar a lista. Por isso o vídeo pula a grade e abre direto na URL do
// cartão (o mesmo destino que o clique em "Configurar" levaria), que
// carrega rápido e limpo — conferido. A tela do cartão aberto
// (SingleIntegrationHooks.vue) não tem nenhum texto de marca — por isso o
// resto do vídeo usa zoom solto.

export const id = '06.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

// Vídeo só de leitura — nada é criado, alterado nem desconectado.
export const preparar = null;

export const cenas = [
  {
    // Abertura fundida com a navegação, direto no cartão — ver nota acima
    // sobre a grade de canais (Index.vue) precisar de motor.
    legenda: 'Abrir Integrações e ler um cartão',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/crm_kanban_ai`,
    aguardarTexto: 'CRM Kanban IA',
    zoom: 1,
    duracaoMs: 3600,
  },
  {
    legenda: 'Leia o nome e a descrição',
    acao: 'parar',
    alvo: { texto: 'CRM Kanban IA' },
    zoom: 1.8,
    duracaoMs: 3800,
  },
  {
    // Esta conta já está conectada (hook existente, não mexemos nele) —
    // o selo real aqui é "Conectado e funcionando", não "Comece por aqui".
    legenda: 'O selo mostra se já está ligado',
    acao: 'parar',
    alvo: { texto: 'Conectado e funcionando' },
    zoom: 1.8,
    duracaoMs: 3200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Desconectar' },
    zoom: 1.8,
    duracaoMs: 4200,
  },
];
