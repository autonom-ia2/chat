// Roteiro do vídeo de trajeto do artigo 13.04 — "Importar, confirmar e
// desfazer uma base de campanha". Gravado em http://localhost:3005
// (CAMPAIGN_IMPORT_ENABLED=true, religado pelo coordenador para este
// vídeo — o recurso estava desligado nos dois servidores até agora).
//
// Usa a ação `anexarArquivo` do motor (adicionada pela Fase A) para subir
// um CSV fictício com nome e telefone brasileiro (com o 9º dígito) —
// diferente do fixture `fixtures/base-campanha-teste.csv`, que tem coluna
// de e-mail em vez de telefone e não serve para Base Campanha (que exige
// telefone, não e-mail — CampaignImports::HeaderMapper, modo :phone).
//
// Sem Sidekiq no ar, a validação da base não sai do estado "Validando":
// grava até aí, sem confirmar a importação nem desfazer nada — não haveria
// contato importado para desfazer de qualquer forma. Nunca clica em nada
// que envie campanha.

export const id = '13.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

const CSV_LOCAL =
  '/private/tmp/claude-501/-Users-rodrigosilva-dev-projetos-noindex-chat2you/a9e1eafb-5894-4277-af99-55ee38fe4e69/scratchpad/base-campanha-13.04.csv';

export const cenas = [
  {
    legenda: 'Importar uma base de campanha',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Abra Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra o menu de três pontinhos',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-ellipsis-vertical' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Base Campanha',
    acao: 'mover e clicar',
    alvo: { texto: 'Base Campanha' },
    zoom: 1.6,
  },
  {
    legenda: 'Dê um nome para a campanha',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: campanha_junho_whatsapp"]' },
    texto: ['campanha_renovacao_outubro'],
    zoom: 1.8,
  },
  {
    legenda: 'Defina a quantidade de lotes',
    acao: 'parar',
    alvo: { seletor: 'input[type="number"]' },
    zoom: 1.8,
    duracaoMs: 1400,
  },
  {
    legenda: 'Escolha o CSV ou XLSX',
    acao: 'anexarArquivo',
    alvo: { texto: 'Escolher arquivo' },
    seletorArquivo: 'input[type="file"]',
    arquivo: CSV_LOCAL,
    zoom: 1.8,
  },
  {
    // Alvo é o nome do arquivo (texto de verdade na tela), não o nome da
    // campanha — esse é valor de campo de formulário, não aparece no
    // textContent que o motor enxerga.
    legenda: 'Confira antes de importar',
    acao: 'parar',
    alvo: { texto: 'base-campanha-13.04.csv' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Validar base',
    acao: 'mover e clicar',
    alvo: { texto: 'Validar base' },
    zoom: 1.8,
    // Some da tela (o diálogo fecha e some) — mesmo ajuste de pausas dos
    // outros vídeos de campanha.
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    // Sem Sidekiq, a base não sai do estado "Enviada" (não chega a
    // "Validando") — é o ponto real onde este ambiente para, sem
    // confirmar nem desfazer nada.
    legenda: 'Sem worker, fica Enviada',
    acao: 'parar',
    alvo: { texto: 'Enviada' },
    zoom: 1.4,
    duracaoMs: 2000,
  },
];
