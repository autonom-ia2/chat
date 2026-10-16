import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import PassagemAvisoRegra from './PassagemAvisoRegra.vue';
import { fixasQueNaoRecebem } from './passagem';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1140 (correção 3) — regra salva que não vai rodar como está: a IA do funil desligada e a pessoa fixa que o servidor
// diz não poder receber numa caixa (a regra do motor de entrega).
const PESSOAS = [
  { id: 5, name: 'Ana Ribeiro' },
  { id: 6, name: 'Bruno Lima' },
];
const CAIXAS = [
  { inbox_id: 1, name: 'WhatsApp', user_ids: [5] },
  { inbox_id: 2, name: 'Instagram', user_ids: [5, 6] },
];
const regraFixa = (pessoa, extra = {}) => ({
  enabled: true,
  pool_type: 'user',
  pool_id: pessoa,
  ...extra,
});

describe('fixasQueNaoRecebem', () => {
  it('lists the fixed person of the funnel rule and the inboxes where they cannot receive', () => {
    expect(
      fixasQueNaoRecebem({
        regra: regraFixa(6),
        etapas: [],
        recebemPorCaixa: CAIXAS,
      })
    ).toEqual([{ etapa: null, pessoaId: 6, caixas: ['WhatsApp'] }]);
  });

  it('also checks stages with their own rule, and skips rules that are off, team rules and AI agents', () => {
    const etapas = [
      { nome: 'Proposta', modo: 'propria', regra: regraFixa(6) },
      { nome: 'Fechado', modo: 'desligada', regra: regraFixa(6) },
      { nome: 'Novo', modo: 'propria', regra: regraFixa('ia:4') },
      {
        nome: 'Pós',
        modo: 'propria',
        regra: { enabled: true, pool_type: 'inbox', pool_id: null },
      },
    ];

    expect(
      fixasQueNaoRecebem({
        regra: regraFixa(6, { enabled: false }),
        etapas,
        recebemPorCaixa: CAIXAS,
      })
    ).toEqual([{ etapa: 'Proposta', pessoaId: 6, caixas: ['WhatsApp'] }]);
  });

  it('is empty when the fixed person can receive everywhere', () => {
    expect(
      fixasQueNaoRecebem({
        regra: regraFixa(5),
        etapas: [],
        recebemPorCaixa: CAIXAS,
      })
    ).toEqual([]);
  });
});

describe('PassagemAvisoRegra', () => {
  const montar = props =>
    mount(PassagemAvisoRegra, {
      props: { pessoas: PESSOAS, funilId: 6, ...props },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            fallbackLocale: false,
            messages: { en, pt_BR },
          }),
        ],
        mocks: { $router: { push: vi.fn() } },
      },
    });

  it('says what the AI does not do when it is off, and when the rule still applies', () => {
    const aviso = montar({ semIa: true });

    expect(aviso.findAll('li').map(li => li.text())).toEqual([
      'A IA deste funil está desligada: ela não percebe quando o cliente pede uma pessoa. A regra continua valendo quando o robô ou o agente de IA da caixa passa a conversa e quando a conversa sai da triagem.',
    ]);
    expect(aviso.find('button').exists()).toBe(true);
  });

  it('names the fixed person and the inboxes, for the funnel and for a stage', () => {
    const aviso = montar({
      fixas: [
        { etapa: null, pessoaId: 6, caixas: ['WhatsApp', 'E-mail'] },
        { etapa: 'Proposta', pessoaId: 6, caixas: ['WhatsApp'] },
      ],
    });

    expect(aviso.findAll('li').map(li => li.text())).toEqual([
      'Bruno Lima não pode receber conversas deste funil em WhatsApp e E-mail. Lá, a conversa vai para quem cuida do funil; sem ninguém para receber agora, ela espera.',
      'Na etapa Proposta, Bruno Lima não pode receber conversas em WhatsApp. Lá, a conversa vai para quem cuida do funil; sem ninguém para receber agora, ela espera.',
    ]);
    expect(aviso.find('button').exists()).toBe(false);
  });
});
