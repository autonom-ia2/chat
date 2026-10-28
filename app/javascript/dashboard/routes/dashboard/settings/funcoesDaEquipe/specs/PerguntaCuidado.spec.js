import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import PerguntaCuidado from '../guiada/PerguntaCuidado.vue';
import { global } from './montar';
import { CARLA, CARLA_SEM_DISPARO } from './quemMonta';

// #2308, especificação 5.B3 e 7.7: o Cuidado da Carla para o Atendente.
const ATENDENTE = PRESETS.AGENT();

const montar = (giver = CARLA, permissions = ATENDENTE) =>
  mount(PerguntaCuidado, {
    props: {
      permissions,
      inicial: ATENDENTE,
      giver,
      quem: 'o Atendente',
      quemSujeito: 'O Atendente',
    },
    global: global(),
  });

const ultimo = wrapper => wrapper.emitted('update:permissions').at(-1)[0];

describe('PerguntaCuidado', () => {
  it('5 linhas na ordem, tudo desligado, e o cadeado com 2 coisas', async () => {
    const wrapper = montar();

    expect(wrapper.find('h1').text()).toBe(
      'O Atendente pode fazer alguma destas coisas?'
    );
    expect(
      wrapper.findAll('[data-cuidado]').map(l => l.attributes('data-cuidado'))
    ).toEqual([
      'contact_export',
      'conversation_message_delete',
      'crm_manage_ai',
      'contact_delete',
      'campaign_send',
    ]);
    expect(
      wrapper.findAll('[role="switch"]').map(s => s.attributes('aria-checked'))
    ).toEqual(['false', 'false', 'false', 'false', 'false']);
    expect(wrapper.find('[data-cuidado="campaign_send"]').text()).toContain(
      'Ao ligar, o Atendente também passa a criar campanhas.'
    );
    const cadeado = wrapper.find('[data-recolhida]');
    expect(cadeado.text()).toContain('Mais 2 coisas que você não pode dar');
    expect(cadeado.text()).toContain(
      'Levar as vendas para uma planilha e definir as metas do mês'
    );
    await cadeado.trigger('click');
    expect(wrapper.find('[data-cadeado="crm_export"]').text()).toContain(
      'Você não tem isto, então não pode dar.'
    );
    expect(wrapper.find('[data-cadeado="crm_metas_manage"]').text()).toContain(
      'Só o administrador dá isto.'
    );
  });

  it('"Ligar as duas" grava exatamente campaign_manage e campaign_send; "Desfazer" volta', async () => {
    const wrapper = montar();
    await wrapper
      .find('[data-cuidado="campaign_send"] [role="switch"]')
      .trigger('click');
    expect(wrapper.emitted('update:permissions')).toBeUndefined();
    expect(wrapper.find('dialog h2').text()).toBe('Ligar também as campanhas?');

    await wrapper.find('[data-acao]').trigger('click');
    const depois = ultimo(wrapper);
    expect(depois.filter(chave => !ATENDENTE.includes(chave))).toEqual([
      'campaign_manage',
      'campaign_send',
    ]);

    await wrapper.setProps({ permissions: depois });
    expect(wrapper.find('[data-faixa-junto]').text()).toContain(
      'Agora o Atendente cria, muda e dispara as campanhas.'
    );
    const linha = wrapper.find('[data-cuidado="campaign_send"]');
    expect(linha.find('[role="switch"]').attributes('aria-checked')).toBe(
      'true'
    );
    expect(linha.text()).toContain('você mudou');

    await wrapper.find('[data-desfazer]').trigger('click');
    expect(ultimo(wrapper)).toEqual(ATENDENTE);
  });

  it('"Agora não" deixa tudo igual', async () => {
    const wrapper = montar();
    await wrapper
      .find('[data-cuidado="contact_delete"] [role="switch"]')
      .trigger('click');
    expect(wrapper.find('dialog h2').text()).toBe('Ligar também os contatos?');
    await wrapper.find('[data-seguro]').trigger('click');
    expect(wrapper.emitted('update:permissions')).toBeUndefined();
  });

  it('(a) liga direto, sem diálogo', async () => {
    const wrapper = montar();
    await wrapper
      .find('[data-cuidado="contact_export"] [role="switch"]')
      .trigger('click');
    expect(ultimo(wrapper)).toEqual([...ATENDENTE, 'contact_export']);
  });

  it('sem disparar campanhas, a linha sai e o cadeado vira 3', () => {
    const wrapper = montar(CARLA_SEM_DISPARO);
    expect(wrapper.find('[data-cuidado="campaign_send"]').exists()).toBe(false);
    expect(wrapper.find('[data-recolhida]').text()).toContain(
      'Mais 3 coisas que você não pode dar'
    );
    expect(wrapper.find('[data-recolhida]').text()).toContain(
      'Disparar campanhas, levar as vendas para uma planilha e definir as metas do mês'
    );
  });
});
