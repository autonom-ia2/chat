// #1149 — adaptador em memória da tela Caixas no CRM, só para o protótipo.
// Mesmo contrato que o endpoint terá: listar(), buscar(inboxId) e
// salvar(inboxId, caixa). `?demo=vazio` na URL simula a conta sem caixas.

const ESPERA_MS = 250;

const FUNIS = [
  {
    id: 1,
    name: 'Vendas',
    kind: 'sales',
    when_to_use: 'Quem quer comprar, pede preço ou orçamento.',
    stages: [
      { id: 11, name: 'Novo' },
      { id: 12, name: 'Em conversa' },
      { id: 13, name: 'Proposta' },
      { id: 14, name: 'Fechamento' },
    ],
  },
  {
    id: 2,
    name: 'Pós-venda',
    kind: 'service',
    when_to_use: 'Quem já é cliente e precisa de ajuda com o que comprou.',
    stages: [
      { id: 21, name: 'Novo' },
      { id: 22, name: 'Em atendimento' },
      { id: 23, name: 'Aguardando o cliente' },
    ],
  },
  {
    id: 3,
    name: 'Financeiro',
    kind: 'service',
    when_to_use: 'Boleto, segunda via, nota fiscal ou pagamento.',
    stages: [
      { id: 31, name: 'Novo' },
      { id: 32, name: 'Em análise' },
    ],
  },
  {
    id: 4,
    name: 'Parcerias',
    kind: 'sales',
    when_to_use: 'Empresa que quer revender ou fazer parceria.',
    stages: [
      { id: 41, name: 'Novo' },
      { id: 42, name: 'Reunião' },
    ],
  },
];

const pessoa = (id, name, extra = {}) => ({
  id,
  name,
  administrator: false,
  triage: true,
  all_pipelines: true,
  pipeline_ids: [],
  only_own: false,
  ...extra,
});

const MARTA = { administrator: true };

const CAIXAS = [
  {
    inbox: { id: 11, name: 'WhatsApp Comercial', channel_type: 'whatsapp' },
    crm_enabled: true,
    pipeline_ids: [1, 2, 3],
    default_stage_id: null,
    subject_ai_mode: 'auto',
    auto_create_card: true,
    visibility_mode: 'all_inbox_cards',
    people: [
      pessoa(1, 'Marta Alves', MARTA),
      pessoa(2, 'Ana Ribeiro', { all_pipelines: false, pipeline_ids: [1] }),
      pessoa(3, 'Léo Martins', {
        triage: false,
        all_pipelines: false,
        pipeline_ids: [1],
      }),
      pessoa(4, 'Carla Souza', {
        triage: false,
        all_pipelines: false,
        pipeline_ids: [2],
        only_own: true,
      }),
      pessoa(5, 'Paula Lima', {
        triage: false,
        all_pipelines: false,
        pipeline_ids: [2, 3],
      }),
      pessoa(6, 'Bruno Costa', {
        triage: false,
        all_pipelines: false,
        pipeline_ids: [3],
      }),
    ],
  },
  {
    inbox: { id: 12, name: 'Instagram', channel_type: 'instagram' },
    crm_enabled: true,
    pipeline_ids: [1],
    default_stage_id: 11,
    subject_ai_mode: 'off',
    auto_create_card: true,
    visibility_mode: 'all_inbox_cards',
    people: [
      pessoa(1, 'Marta Alves', MARTA),
      pessoa(2, 'Ana Ribeiro'),
      pessoa(3, 'Léo Martins'),
    ],
  },
  {
    inbox: { id: 14, name: 'E-mail de contato', channel_type: 'email' },
    crm_enabled: true,
    pipeline_ids: [2],
    default_stage_id: 21,
    subject_ai_mode: 'off',
    auto_create_card: false,
    // Caixa que hoje está em "Agente vê apenas atribuídos" e ninguém revisou.
    visibility_mode: 'assigned_only',
    people: [
      pessoa(1, 'Marta Alves', MARTA),
      pessoa(4, 'Carla Souza'),
      pessoa(5, 'Paula Lima'),
    ],
  },
  {
    inbox: { id: 13, name: 'Chat do site', channel_type: 'web_widget' },
    crm_enabled: false,
    pipeline_ids: [],
    default_stage_id: null,
    subject_ai_mode: 'off',
    auto_create_card: false,
    visibility_mode: 'all_inbox_cards',
    people: [
      pessoa(1, 'Marta Alves', MARTA),
      pessoa(2, 'Ana Ribeiro'),
      pessoa(6, 'Bruno Costa'),
    ],
  },
];

const copia = valor => JSON.parse(JSON.stringify(valor));
const esperar = valor =>
  new Promise(resolve => {
    setTimeout(() => resolve(copia(valor)), ESPERA_MS);
  });

const contaVazia = () =>
  new URLSearchParams(window.location.search).get('demo') === 'vazio';

let caixas = copia(CAIXAS);

export default {
  listar() {
    return esperar({ caixas: contaVazia() ? [] : caixas, funis: FUNIS });
  },
  buscar(inboxId) {
    const caixa = caixas.find(item => item.inbox.id === Number(inboxId));
    if (!caixa) return Promise.reject(new Error('not_found'));
    return esperar({ caixa, funis: FUNIS });
  },
  salvar(inboxId, dados) {
    caixas = caixas.map(item =>
      item.inbox.id === Number(inboxId)
        ? { ...copia(dados), visibility_mode: 'all_inbox_cards' }
        : item
    );
    return esperar(caixas.find(item => item.inbox.id === Number(inboxId)));
  },
};
