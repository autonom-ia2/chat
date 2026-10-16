import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EtapaConfira from '../components/EtapaConfira.vue';
import { formularioDaCaixa } from '../helpers/agentesIa';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

vi.mock(
  'dashboard/routes/dashboard/autonomia/agentes/composables/useAgenteIaPorCaixa',
  async () => {
    const { computed } = await import('vue');
    return { useAgenteIaPorCaixa: () => computed(() => false) };
  }
);
// #1676 — a flag da IA de assunto em 1 funil vem da conta (desligada aqui).
vi.mock('../helpers/iaDeAssunto', async importOriginal => {
  const { computed } = await import('vue');
  const original = await importOriginal();
  return { ...original, useIaDeAssunto: () => computed(() => false) };
});

const CAIXA = {
  inbox: { id: 7, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
  crm_enabled: true,
  pipeline_ids: [1],
  default_stage_id: 11,
  subject_ai_mode: 'off',
  auto_create_card: true,
  visibility_mode: 'all_inbox_cards',
  agent_bot: null,
  people: [],
  ai_agents: null,
};

// #1140 (decisão 7) — tirar um funil com conversas em aberto avisa antes de
// salvar, com a contagem do servidor; ficar com um funil só também avisa.
describe('EtapaConfira: aviso antes de salvar', () => {
  const DOIS_FUNIS = [
    { id: 1, name: 'Vendas', stages: [{ id: 11, name: 'Novo' }] },
    { id: 2, name: 'Pós-venda', stages: [{ id: 21, name: 'Aberto' }] },
  ];
  const montar = (marcados, abertas) => {
    const original = formularioDaCaixa(
      {
        ...CAIXA,
        pipeline_ids: [1, 2],
        subject_ai_mode: 'auto',
        auto_create_card: false,
        agent_bot: null,
        conversas_abertas: abertas,
      },
      false
    );
    const form = { ...original, pipeline_ids: marcados, modo: 'off' };
    return mount(EtapaConfira, {
      props: { form, original, funis: DOIS_FUNIS },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            fallbackLocale: false,
            messages: { en, pt_BR },
          }),
        ],
      },
    });
  };

  it('says how many open conversations the funnel that leaves has, and that the one left takes everything', () => {
    const wrapper = montar([1], { 1: 4, 2: 3 });

    expect(
      wrapper.findAll('[data-aviso-antes-de-salvar] p').map(p => p.text())
    ).toEqual([
      'Há 3 conversas abertas em Pós-venda nesta caixa.',
      'Com um funil só nesta caixa, quem cuida de Vendas e vê todas as conversas passa a cuidar também das que ainda não têm assunto. Quem só vê as dele continua assim.',
    ]);
  });

  it('uses the singular for one conversation', () => {
    const wrapper = montar([1], { 2: 1 });

    expect(wrapper.find('[data-aviso-antes-de-salvar] p').text()).toBe(
      'Há 1 conversa aberta em Pós-venda nesta caixa.'
    );
  });

  it('has no warning when no funnel leaves', () => {
    const wrapper = montar([1, 2], { 1: 4, 2: 3 });

    expect(wrapper.find('[data-aviso-antes-de-salvar]').exists()).toBe(false);
  });
});
