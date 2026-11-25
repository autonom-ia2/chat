// #1181 — os modelos prontos do herói (T01) e da gaveta "Criar agente", na ordem do protótipo
// (jornada.html, DATA.models e modelOrder). A chave é o `agent_type` do backend (AGENT_TYPES em
// agent.rb) e vai na query `modelo` da rota do Construtor; o PR2 lê de lá. Os textos ficam em
// AGENTS.JORNADA.MODELOS.<I18N>. "Do meu jeito" é o tipo custom, sem cartão.
// #3219: `icone` é o da linha compacta do modelo no passo 2 de quem tem ramos de seguro.
export const MODELO_DO_MEU_JEITO = 'custom';

export const MODELOS = [
  {
    chave: 'support',
    i18n: 'SUPPORT',
    horario: '10:02',
    icone: 'i-lucide-circle-help',
  },
  {
    chave: 'sdr',
    i18n: 'SDR',
    horario: '14:31',
    icone: 'i-lucide-shopping-bag',
  },
  {
    chave: 'reception',
    i18n: 'RECEPTION',
    horario: '09:15',
    icone: 'i-lucide-door-open',
  },
];
