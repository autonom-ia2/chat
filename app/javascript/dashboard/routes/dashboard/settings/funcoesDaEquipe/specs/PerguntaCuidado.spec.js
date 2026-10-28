import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import PerguntaCuidado from '../guiada/PerguntaCuidado.vue';
import { global } from './montar';
import { escolherNivelDeVendas } from '../nivelDeVendas';
import { ADMIN, CARLA, CARLA_SEM_DISPARO } from './quemMonta';

// #2308, especificação 5.B3 e 7.7: o Cuidado da Carla para o Atendente.
const ATENDENTE = PRESETS.AGENT();

const montar = (giver = CARLA, permissions = ATENDENTE) =>
  mount(PerguntaCuidado, {
    props: { permissions, inicial: ATENDENTE, giver, nome: 'Atendente' },
    global: global(),
  });

const ultimo = wrapper => wrapper.emitted('update:permissions').at(-1)[0];

describe('PerguntaCuidado', () => {
  it('5 linhas na ordem, tudo desligado, e o cadeado com 2 coisas', async () => {
    const wrapper = montar();

    expect(wrapper.find('h1').text()).toBe(
      'Quem for Atendente pode fazer alguma destas coisas?'
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
      'Ao ligar, quem for Atendente também passa a criar campanhas.'
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
    expect(depois).toEqual([...ATENDENTE, 'campaign_manage', 'campaign_send']);

    await wrapper.setProps({ permissions: depois });
    expect(wrapper.find('[data-faixa-junto]').text()).toContain(
      'Agora quem for Atendente cria, muda e dispara as campanhas.'
    );
    const linha = wrapper.find('[data-cuidado="campaign_send"]');
    expect(linha.find('[role="switch"]').attributes('aria-checked')).toBe(
      'true'
    );
    expect(linha.text()).toContain('você mudou');

    await wrapper.find('[data-desfazer]').trigger('click');
    expect(ultimo(wrapper)).toEqual(ATENDENTE);
  });

  it('"Desfazer" tira só o que o "Ligar as duas" pôs: o que a pessoa ligou depois fica', async () => {
    const wrapper = montar();
    await wrapper
      .find('[data-cuidado="campaign_send"] [role="switch"]')
      .trigger('click');
    await wrapper.find('[data-acao]').trigger('click');
    await wrapper.setProps({
      permissions: [...ultimo(wrapper), 'contact_export'],
    });

    await wrapper.find('[data-desfazer]').trigger('click');
    expect(ultimo(wrapper)).toEqual([...ATENDENTE, 'contact_export']);
  });

  it('a faixa "Agora…" some quando a pessoa desliga o que ela anunciou', async () => {
    const wrapper = montar();
    await wrapper
      .find('[data-cuidado="campaign_send"] [role="switch"]')
      .trigger('click');
    await wrapper.find('[data-acao]').trigger('click');
    const depois = ultimo(wrapper);
    await wrapper.setProps({ permissions: depois });
    expect(wrapper.find('[data-faixa-junto]').exists()).toBe(true);

    await wrapper.setProps({
      permissions: depois.filter(chave => chave !== 'campaign_send'),
    });
    expect(wrapper.find('[data-faixa-junto]').exists()).toBe(false);
    expect(wrapper.find('[role="status"]').exists()).toBe(true);
  });

  it('com "Cuida de tudo", a IA das vendas fica ligada e travada, e as metas sem R$ não aparecem', async () => {
    const tudo = escolherNivelDeVendas('tudo', ATENDENTE);
    const wrapper = montar(ADMIN, tudo);
    const ia = wrapper.find('[data-cuidado="crm_manage_ai"]');
    const interruptor = ia.find('[role="switch"]');
    expect(interruptor.attributes('aria-checked')).toBe('true');
    expect(interruptor.attributes('aria-disabled')).toBe('true');
    expect(ia.text()).toContain('Vem com "Cuida de tudo nas vendas".');
    await interruptor.trigger('click');
    expect(wrapper.emitted('update:permissions')).toBeUndefined();

    expect(wrapper.find('[data-cuidado="crm_metas_manage"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('metas');
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
