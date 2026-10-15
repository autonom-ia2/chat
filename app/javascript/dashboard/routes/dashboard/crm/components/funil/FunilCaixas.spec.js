import { mount, RouterLinkStub } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import FunilCaixas from './FunilCaixas.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1149 (R16) — o Editar funil só mostra onde o funil está ligado; mudar é em
// Canais de cada funil.
const etapas = [
  { id: 10, name: 'Cotação', color: '#2563eb' },
  { id: 11, name: 'Proposta', color: '#0891b2' },
];
const ligadas = [
  {
    inbox_id: 2,
    inbox: { name: 'WhatsApp Vendas', channel_type: 'Channel::Api' },
    default_stage_id: 10,
    auto_create_card: true,
  },
  {
    inbox_id: 3,
    inbox: { name: 'Instagram da loja', channel_type: 'Channel::Api' },
    default_stage_id: null,
    auto_create_card: false,
  },
];

const montar = props =>
  mount(FunilCaixas, {
    props: { caixas: [], ligadas, etapas, ...props },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'pt_BR', messages: { en, pt_BR } }),
      ],
      stubs: { RouterLink: RouterLinkStub, CaixaIcone: true },
    },
  });

describe('FunilCaixas — só leitura', () => {
  it('lista onde o funil está ligado, com o caminho de cada caixa', () => {
    const wrapper = montar();
    const [whats, insta] = wrapper.findAll('[data-caixa]');

    expect(wrapper.text()).toContain('Ligado em');
    expect(whats.text()).toContain('WhatsApp Vendas');
    expect(whats.text()).toContain('Cotação');
    expect(insta.text()).toContain(
      'O card nasce quando a IA ou a equipe escolhe este funil'
    );
  });

  it('não liga nem desliga nada: cada caixa leva à página dela em Canais de cada funil', () => {
    const wrapper = montar();
    const links = wrapper.findAllComponents(RouterLinkStub);

    expect(wrapper.find('button').exists()).toBe(false);
    expect(links.map(link => link.props('to'))).toEqual([
      { name: 'crm_caixa', params: { inboxId: 2 } },
      { name: 'crm_caixa', params: { inboxId: 3 } },
      { name: 'crm_caixas' },
    ]);
    expect(links[0].text()).toBe('Mudar em Canais de cada funil');
  });

  it('card automático sem etapa escolhida mostra a primeira, como o sistema faz', () => {
    const wrapper = montar({
      ligadas: [{ ...ligadas[0], default_stage_id: null }],
    });

    expect(wrapper.get('[data-caixa]').text()).toContain('Cotação');
  });

  it('sem caixa ligada, diz que nenhuma traz conversas e mostra onde ligar', () => {
    const wrapper = montar({ ligadas: [] });

    expect(wrapper.findAll('[data-caixa]')).toHaveLength(0);
    expect(wrapper.text()).toContain(
      'Nenhuma caixa de entrada traz conversas para cá.'
    );
    expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
      name: 'crm_caixas',
    });
  });
});
