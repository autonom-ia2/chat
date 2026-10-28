import { mount } from '@vue/test-utils';
import DialogoDaCasa from '../guiada/DialogoDaCasa.vue';
import { global } from './montar';

// #2308, especificação 9 e 14: uma anatomia; o seguro tem o foco e responde ao Esc; ação nunca é vermelha no cuidado.
const montar = (props = {}) =>
  mount(DialogoDaCasa, {
    attachTo: document.body,
    props: {
      titulo: 'Ligar também as campanhas?',
      texto:
        'Para disparar, o Atendente também vai criar e mudar as campanhas.',
      risco: 'Disparar manda mensagem para muita gente de uma vez.',
      seguro: 'Agora não',
      acao: 'Ligar as duas',
      ...props,
    },
    global: global(),
  });

describe('DialogoDaCasa', () => {
  it('mostra título, texto, risco e o quadrado âmbar no cuidado', () => {
    const wrapper = montar();
    expect(wrapper.find('h2').text()).toBe('Ligar também as campanhas?');
    expect(wrapper.find('[data-risco]').text()).toContain('muita gente');
    expect(wrapper.html()).toContain('bg-n-amber-3');
    expect(wrapper.find('[data-acao]').classes().join(' ')).not.toContain(
      'ruby'
    );
    wrapper.unmount();
  });

  it('o botão seguro recebe o foco ao abrir', async () => {
    const wrapper = montar();
    await wrapper.vm.abrir();
    expect(document.activeElement).toBe(wrapper.find('[data-seguro]').element);
    wrapper.unmount();
  });

  it('Esc vira a ação segura; os botões emitem cada um o seu', async () => {
    const wrapper = montar();
    const cancel = new Event('cancel', { cancelable: true });
    wrapper.find('dialog').element.dispatchEvent(cancel);
    expect(cancel.defaultPrevented).toBe(true);
    expect(wrapper.emitted('seguro')).toHaveLength(1);

    await wrapper.find('[data-acao]').trigger('click');
    expect(wrapper.emitted('acao')).toHaveLength(1);
    wrapper.unmount();
  });

  it('no celular, o rodapé empilha com o seguro em cima; sem ação, só o seguro', () => {
    const wrapper = montar();
    const botoes = wrapper.findAll('dialog button');
    expect(
      botoes.map(botao => botao.attributes('data-seguro') !== undefined)
    ).toEqual([true, false]);
    expect(botoes[0].element.parentElement.className).toContain('flex-col');
    wrapper.unmount();

    const aviso = montar({ tipo: 'aviso', acao: '' });
    expect(aviso.find('[data-acao]').exists()).toBe(false);
    expect(aviso.html()).toContain('i-lucide-info');
    aviso.unmount();
  });

  it('destrutivo usa ruby e a porta quando pedida', () => {
    const wrapper = montar({ tipo: 'destrutivo', icone: 'i-lucide-door-open' });
    expect(wrapper.html()).toContain('bg-n-ruby-3');
    expect(wrapper.html()).toContain('i-lucide-door-open');
    wrapper.unmount();
  });
});
