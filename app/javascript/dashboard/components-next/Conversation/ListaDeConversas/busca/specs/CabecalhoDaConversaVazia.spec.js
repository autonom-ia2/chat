import { createStore } from 'vuex';
import { mount, enableAutoUnmount } from '@vue/test-utils';
import CabecalhoDaConversaVazia from '../CabecalhoDaConversaVazia.vue';
import { criarI18n } from '../../specs/apoio';

// #2211 (rodada 5) — o topo da conversa vazia segue o topo da conversa de verdade: a caixa só
// aparece quando a conta tem mais de uma; o WhatsApp pelo celular mostra o ícone do WhatsApp e
// o número; "Trocar" só quando há outra caixa possível.
enableAutoUnmount(afterEach);

const CELULAR = {
  id: 2,
  name: 'WhatsApp do Celular',
  channelType: 'Channel::Api',
  wahaProvider: true,
  wahaPhoneNumber: '+5511900003303',
};

const montar = (props, caixasDaConta = [{ id: 1 }, { id: 2 }]) => {
  const store = createStore({
    getters: { 'inboxes/getInboxes': () => caixasDaConta },
  });
  return mount(CabecalhoDaConversaVazia, {
    props: { nome: 'Maria da Conceição', caixa: CELULAR, ...props },
    global: {
      plugins: [criarI18n(), store],
      stubs: { Avatar: true },
    },
  });
};

describe('CabecalhoDaConversaVazia', () => {
  it('WhatsApp pelo celular: ícone do WhatsApp, o nome da caixa e o número', () => {
    const wrapper = montar();
    const caixa = wrapper.find('[data-caixa-escolhida]');
    expect(caixa.text()).toContain('WhatsApp do Celular');
    expect(caixa.find('.i-woot-whatsapp').exists()).toBe(true);
    expect(wrapper.find('[data-numero-da-caixa]').text()).toBe(
      '• +55 11 90000-3303'
    );
  });

  it('conta com uma caixa só: o topo não repete a caixa', () => {
    const wrapper = montar({}, [{ id: 2 }]);
    expect(wrapper.find('[data-nome]').text()).toBe('Maria da Conceição');
    expect(wrapper.find('[data-caixa-escolhida]').exists()).toBe(false);
  });

  it('"Trocar" e "Anterior" avisam a tela', async () => {
    const wrapper = montar({ comTrocar: true });
    await wrapper.find('[data-trocar-caixa]').trigger('click');
    await wrapper.find('[data-voltar]').trigger('click');
    expect(wrapper.emitted('trocar')).toHaveLength(1);
    expect(wrapper.emitted('voltar')).toHaveLength(1);
  });

  it('sem outra caixa possível, sem "Trocar"', () => {
    expect(montar().find('[data-trocar-caixa]').exists()).toBe(false);
  });
});
