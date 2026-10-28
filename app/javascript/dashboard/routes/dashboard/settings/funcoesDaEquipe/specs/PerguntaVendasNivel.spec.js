import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import NivelDeVendas from '../guiada/NivelDeVendas.vue';
import { global } from './montar';
import { ADMIN, CARLA } from './quemMonta';

// #2308, especificação 5.B3, 5.F e decisão 14A.
const montar = giver =>
  mount(NivelDeVendas, {
    props: { permissions: PRESETS.AGENT(), giver, quem: 'o Atendente' },
    global: global(),
  });

describe('NivelDeVendas', () => {
  it('para a Carla, "Cuida de tudo" fica tracejado com "Só o administrador dá isto."', () => {
    const tudo = montar(CARLA).find('[data-nivel="tudo"]');
    expect(tudo.attributes('aria-disabled')).toBe('true');
    expect(tudo.text()).toContain('Só o administrador dá isto.');
  });

  it('para o administrador, pede confirmação sem falar em metas nem em R$', async () => {
    const wrapper = montar(ADMIN);
    await wrapper.find('[data-nivel="tudo"]').trigger('click');
    expect(wrapper.emitted('update:permissions')).toBeUndefined();

    const dialogo = wrapper.find('dialog');
    expect(dialogo.find('h2').text()).toBe(
      'Deixar o Atendente cuidar de tudo nas vendas?'
    );
    expect(dialogo.text()).not.toContain('metas');
    expect(dialogo.text()).not.toContain('R$');

    await wrapper.find('[data-acao]').trigger('click');
    const [permissoes] = wrapper.emitted('update:permissions')[0];
    expect(permissoes).toContain('crm_admin');
    expect(permissoes).not.toContain('sales_value_view');
  });

  it('os outros níveis trocam direto', async () => {
    const wrapper = montar(CARLA);
    await wrapper.find('[data-nivel="view"]').trigger('click');
    const [permissoes] = wrapper.emitted('update:permissions')[0];
    expect(permissoes).not.toContain('crm_manage_cards');
    expect(permissoes).toContain('crm_view');
  });
});
