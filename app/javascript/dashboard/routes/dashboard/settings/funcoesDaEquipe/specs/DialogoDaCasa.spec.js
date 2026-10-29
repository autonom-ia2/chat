import { mount } from '@vue/test-utils';
import DialogoDaCasa from '../guiada/DialogoDaCasa.vue';
import { espiarDialogo, global } from './montar';

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

let espiao = null;
afterEach(() => {
  espiao?.soltar();
  espiao = null;
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

  // Rodada 4: abrir de novo com o diálogo aberto troca o conteúdo; o foco vai ao primeiro campo marcado ou ao título,
  // para o leitor de tela dizer o que mudou.
  it('abrir com ele aberto põe o foco no campo marcado ou, sem campo, no título', async () => {
    espiao = espiarDialogo({ marcarAberto: true });
    const wrapper = montar();
    await wrapper.vm.abrir();
    await wrapper.vm.abrir();
    expect(document.activeElement).toBe(wrapper.find('h2').element);
    wrapper.unmount();

    const comCampo = mount(DialogoDaCasa, {
      attachTo: document.body,
      props: { titulo: 'Para onde vão?', seguro: 'Manter', acao: 'Mover' },
      slots: { default: '<button id="destino" type="button">Escolha</button>' },
      global: global(),
    });
    await comCampo.vm.abrir();
    await comCampo.setProps({ focoAoReabrir: '#destino' });
    await comCampo.vm.abrir();
    expect(document.activeElement?.id).toBe('destino');
    comCampo.unmount();
  });

  it('focarTitulo põe o foco no título', async () => {
    const wrapper = montar();
    await wrapper.vm.focarTitulo();
    expect(document.activeElement).toBe(wrapper.find('h2').element);
    wrapper.unmount();
  });

  // Rodada 4: no Chrome, o segundo Esc fecha o <dialog> sem "cancel"; ocupado, o Esc não chega a ele.
  it('ocupado, o Esc é barrado no teclado; livre, segue para o "cancel"', () => {
    const esc = () =>
      new KeyboardEvent('keydown', { key: 'Escape', cancelable: true });
    const ocupado = montar({ ocupado: true });
    const naOcupada = esc();
    ocupado.find('dialog').element.dispatchEvent(naOcupada);
    expect(naOcupada.defaultPrevented).toBe(true);
    ocupado.unmount();

    const livre = montar();
    const naLivre = esc();
    livre.find('dialog').element.dispatchEvent(naLivre);
    expect(naLivre.defaultPrevented).toBe(false);
    livre.unmount();
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
