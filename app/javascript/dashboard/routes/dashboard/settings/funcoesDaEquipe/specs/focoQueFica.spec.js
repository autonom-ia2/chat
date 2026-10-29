import { flushPromises, mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import AjustesDaFuncao from '../guiada/AjustesDaFuncao.vue';
import { devolverFoco } from '../guiada/focoQueFica';
import { global } from './montar';
import { CARLA } from './quemMonta';

// #2308, especificação 14 › Acessibilidade: quando a linha muda de lugar ou some, o foco não cai no body.
afterEach(() => {
  document.body.innerHTML = '';
});

describe('devolverFoco', () => {
  it('o elemento focado sumiu: o foco vai ao primeiro alvo que existir', async () => {
    document.body.innerHTML =
      '<div id="raiz"><h1 tabindex="-1">Título</h1><button id="some">x</button></div>';
    const raiz = document.getElementById('raiz');
    document.getElementById('some').focus();
    document.getElementById('some').remove();

    await devolverFoco(raiz, ['[data-nao-existe]', 'h1']);
    expect(document.activeElement).toBe(raiz.querySelector('h1'));
  });

  it('o foco continua num elemento vivo: não mexe', async () => {
    document.body.innerHTML =
      '<div id="raiz"><h1 tabindex="-1">Título</h1><button id="fica">x</button></div>';
    const fica = document.getElementById('fica');
    fica.focus();

    await devolverFoco(document.getElementById('raiz'), ['h1']);
    expect(document.activeElement).toBe(fica);
  });
});

describe('Ajustes: a área que sobe leva o foco junto', () => {
  it('escolher "Só olha" nos relatórios tira a área da recolhida, e o foco fica no nível escolhido', async () => {
    const atendente = PRESETS.AGENT();
    const wrapper = mount(AjustesDaFuncao, {
      attachTo: document.body,
      props: {
        titulo: 'Ajustes',
        dica: 'Dica',
        permissions: atendente,
        inicial: atendente,
        giver: CARLA,
        'onUpdate:permissions': novas =>
          wrapper.setProps({ permissions: novas }),
      },
      global: global(),
    });
    await wrapper.find('[data-recolhida]').trigger('click');
    const olhar = wrapper.find('[data-area="REPORTS"] [data-nivel="view"]');
    olhar.element.focus();
    await olhar.trigger('click');
    await flushPromises();

    expect(document.activeElement).not.toBe(document.body);
    expect(document.activeElement.closest('[data-area]').dataset.area).toBe(
      'REPORTS'
    );
    expect(document.activeElement.getAttribute('aria-checked')).toBe('true');
    wrapper.unmount();
  });
});
