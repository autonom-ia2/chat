import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import NivelDeVendas from '../guiada/NivelDeVendas.vue';
import PerguntaVendas from '../guiada/PerguntaVendas.vue';
import { espiarDialogo, global } from './montar';
import { ADMIN, CARLA } from './quemMonta';

// #2308, especificação 5.B3, 5.F e 7.4, decisão 14A da seção 12 e a revisão do #2308.
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

// Escolhe um nível e passa o resultado de volta, como a conversa faz (v-model).
const escolher = async (wrapper, nivel) => {
  await wrapper.find(`[data-nivel="${nivel}"]`).trigger('click');
  if (nivel === 'tudo') await wrapper.find('[data-acao]').trigger('click');
  await wrapper.setProps({ permissions: ultimo(wrapper) });
};

describe('NivelDeVendas', () => {
  // Rodada 4: entrar e sair de "Cuida de tudo" não passa pela memória das trocas; o que ela guardava antes ("arquivar"
  // tirado ao ir para "Só olha") religava depois que a pessoa já o viu desligado em "Pode mexer".
  it('Atendente com arquivar: Só olha, Cuida de tudo, Pode mexer, Só olha, Pode mexer não religa arquivar', async () => {
    const comArquivar = [...PRESETS.AGENT(), 'crm_delete_cards'];
    const wrapper = montar(ADMIN, comArquivar);

    await escolher(wrapper, 'view');
    await escolher(wrapper, 'tudo');
    await escolher(wrapper, 'manage');
    expect(ultimo(wrapper)).not.toContain('crm_delete_cards');
    await escolher(wrapper, 'view');
    await escolher(wrapper, 'manage');
    expect(ultimo(wrapper)).not.toContain('crm_delete_cards');
  });

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
      'Com a função Atendente, a pessoa vai cuidar de tudo nas vendas?'
    );
    expect(dialogo.text()).not.toContain('metas');
    expect(dialogo.text()).not.toContain('R$');

    await wrapper.find('[data-acao]').trigger('click');
    expect(ultimo(wrapper)).toEqual([
      'conversation_participating_manage',
      'contact_view',
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

  // "Só olha" não deixa mover as vendas: o servidor aceita crm_move_cards sozinho (CardPolicy#move?), e a tela diz
  // que a pessoa não cria nem move vendas.
  it('os outros níveis trocam direto, e "Só olha" tira mover as vendas', async () => {
    const wrapper = montar(CARLA);
    await wrapper.find('[data-nivel="view"]').trigger('click');
    expect(ultimo(wrapper)).toEqual([
      'conversation_participating_manage',
      'contact_view',
      'conversation_unassigned_manage',
      'crm_view',
    ]);
    expect(ultimo(wrapper)).not.toContain('crm_move_cards');
  });

  // WCAG 3.2.2 (rodada 3): a seta só leva o foco ao 4º nível; o aviso abre só com clique, Espaço ou Enter.
  it('a seta até "Cuida de tudo" não abre o aviso nem troca o nível; o clique abre', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const mexendo = [...PRESETS.AGENT(), 'crm_manage_cards'];
    const wrapper = mount(NivelDeVendas, {
      attachTo: document.body,
      props: {
        permissions: mexendo,
        inicial: mexendo,
        giver: ADMIN,
        nome: 'Atendente',
        rotulo: 'Vendas',
      },
      global: global(),
    });
    await wrapper
      .find('[data-nivel="manage"]')
      .trigger('keydown', { key: 'ArrowDown' });
    await wrapper.vm.$nextTick();
    expect(document.activeElement.dataset.nivel).toBe('tudo');
    expect(mostrar).not.toHaveBeenCalled();
    expect(wrapper.emitted('update:permissions')).toBeUndefined();

    await wrapper
      .find('[data-nivel="tudo"]')
      .trigger('keydown', { key: 'ArrowDown' });
    expect(ultimo(wrapper)).not.toContain('crm_view');
    expect(mostrar).not.toHaveBeenCalled();

    await wrapper.find('[data-nivel="tudo"]').trigger('click');
    expect(mostrar).toHaveBeenCalledTimes(1);
    wrapper.unmount();
    soltar();
  });

  it('função antiga "Só olha" que move as vendas: o Mais mostra a linha ligada, e desligar tira só ela', async () => {
    const legada = [
      ...PRESETS.AGENT().filter(c => !c.startsWith('crm_')),
      'crm_view',
      'crm_move_cards',
    ];
    const wrapper = mount(PerguntaVendas, {
      props: {
        permissions: legada,
        inicial: legada,
        giver: ADMIN,
        nome: 'Atendente',
      },
      global: global(),
    });
    await wrapper.find('[data-recolhida]').trigger('click');
    const linha = wrapper
      .findAll('[role="switch"]')
      .find(
        item =>
          item.attributes('aria-label') === 'Mover as vendas entre as colunas'
      );
    expect(linha.attributes('aria-checked')).toBe('true');
    await linha.trigger('click');
    expect(ultimo(wrapper)).toEqual(
      legada.filter(chave => chave !== 'crm_move_cards')
    );

    const semMover = mount(PerguntaVendas, {
      props: {
        permissions: ['crm_view'],
        inicial: ['crm_view'],
        giver: ADMIN,
        nome: 'Atendente',
      },
      global: global(),
    });
    await semMover.find('[data-recolhida]').trigger('click');
    expect(semMover.text()).not.toContain('Mover as vendas entre as colunas');
  });
});
