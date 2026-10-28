import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import NivelDeVendas from '../guiada/NivelDeVendas.vue';
import { espiarDialogo, global } from './montar';
import { ADMIN, CARLA } from './quemMonta';

// #2308, especificação 5.B3, 5.F e decisões 4 e 14A.
const montar = (giver, permissions = PRESETS.AGENT(), inicial = permissions) =>
  mount(NivelDeVendas, {
    props: {
      permissions,
      inicial,
      giver,
      nome: 'Atendente',
      rotulo: 'Vendas',
    },
    global: global(),
  });

const ultimo = wrapper => wrapper.emitted('update:permissions').at(-1)[0];

describe('NivelDeVendas', () => {
  it('para a Carla, "Cuida de tudo" fica tracejado e clique, Espaço e Enter não fazem nada', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const wrapper = montar(CARLA);
    const tudo = wrapper.find('[data-nivel="tudo"]');
    expect(tudo.attributes('aria-disabled')).toBe('true');
    expect(tudo.text()).toContain('Só o administrador dá isto.');

    await tudo.trigger('click');
    await tudo.trigger('keydown', { key: ' ' });
    await tudo.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('update:permissions')).toBeUndefined();
    expect(mostrar).not.toHaveBeenCalled();
    soltar();
  });

  it('para o administrador, pede confirmação sem falar em metas nem em R$, e grava só crm_admin e as 6', async () => {
    const wrapper = montar(ADMIN);
    await wrapper.find('[data-nivel="tudo"]').trigger('click');
    expect(wrapper.emitted('update:permissions')).toBeUndefined();

    const dialogo = wrapper.find('dialog');
    expect(dialogo.find('h2').text()).toBe(
      'Deixar quem for Atendente cuidar de tudo nas vendas?'
    );
    expect(dialogo.text()).not.toContain('metas');
    expect(dialogo.text()).not.toContain('R$');

    await wrapper.find('[data-acao]').trigger('click');
    expect(ultimo(wrapper)).toEqual([
      'conversation_participating_manage',
      'contact_view',
      'knowledge_base_view',
      'crm_view',
      'crm_manage_cards',
      'crm_move_cards',
      'conversation_unassigned_manage',
      'crm_admin',
      'crm_view_reports',
      'crm_manage_pipelines',
      'crm_manage_ai',
      'crm_export',
      'crm_delete_cards',
      'crm_metas_manage',
    ]);
  });

  it('sair de "Cuida de tudo" devolve o que a função tinha antes (Gerente de vendas)', async () => {
    const gerente = PRESETS.SALES_MANAGER();
    const wrapper = montar(ADMIN, gerente);
    await wrapper.find('[data-nivel="tudo"]').trigger('click');
    await wrapper.find('[data-acao]').trigger('click');
    const tudo = ultimo(wrapper);
    expect(tudo.filter(chave => !gerente.includes(chave))).toEqual([
      'crm_admin',
      'crm_manage_ai',
      'crm_delete_cards',
    ]);

    await wrapper.setProps({ permissions: tudo });
    await wrapper.find('[data-nivel="manage"]').trigger('click');
    expect([...ultimo(wrapper)].sort()).toEqual([...gerente].sort());
  });

  it('a função que já abriu com "Cuida de tudo": sair tira as seis', async () => {
    const tudo = [...PRESETS.AGENT(), 'crm_admin', 'crm_metas_manage'];
    const wrapper = montar(ADMIN, tudo, tudo);
    await wrapper.find('[data-nivel="manage"]').trigger('click');
    expect([...ultimo(wrapper)].sort()).toEqual([...PRESETS.AGENT()].sort());
  });

  it('os outros níveis trocam direto', async () => {
    const wrapper = montar(CARLA);
    await wrapper.find('[data-nivel="view"]').trigger('click');
    expect(ultimo(wrapper)).toEqual([
      'conversation_participating_manage',
      'contact_view',
      'knowledge_base_view',
      'crm_move_cards',
      'conversation_unassigned_manage',
      'crm_view',
    ]);
  });
});
