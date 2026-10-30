import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import PerguntaCuidado from '../guiada/PerguntaCuidado.vue';
import { global } from './montar';
import { escolherNivelDeVendas } from '../nivelDeVendas';
import { ADMIN, CARLA, CARLA_SEM_DISPARO, TUDO_SEM_MEXER } from './quemMonta';

// #2308, especificação 5.B3 e 7.7: o Cuidado da Carla para o Atendente.
const ATENDENTE = PRESETS.AGENT();

const montar = (giver = CARLA, permissions = ATENDENTE, inicial = ATENDENTE) =>
  mount(PerguntaCuidado, {
    props: { permissions, inicial, giver, nome: 'Atendente' },
    global: global(),
  });

const ultimo = wrapper => wrapper.emitted('update:permissions').at(-1)[0];

describe('PerguntaCuidado', () => {
  it('5 linhas na ordem, tudo desligado, e o cadeado com 2 coisas', async () => {
    const wrapper = montar();

    expect(wrapper.find('h1').text()).toBe(
      'Com a função Atendente, a pessoa pode fazer alguma destas coisas?'
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
      'Ao ligar, a pessoa também passa a criar campanhas.'
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
      'Agora a pessoa cria, muda e dispara as campanhas.'
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

  it('metas sem R$ (administrador): pergunta pelo R$, liga os dois e, ao desligar as metas, o R$ fica', async () => {
    const semRs = PRESETS.SDR().filter(chave => chave !== 'sales_value_view');
    const wrapper = montar(ADMIN, semRs, semRs);
    const metas = () =>
      wrapper.find('[data-cuidado="crm_metas_manage"] [role="switch"]');

    await metas().trigger('click');
    expect(wrapper.emitted('update:permissions')).toBeUndefined();
    expect(wrapper.find('dialog h2').text()).toBe(
      'Ligar também os valores em R$?'
    );
    await wrapper.find('[data-acao]').trigger('click');
    const ligadas = ultimo(wrapper);
    expect([...ligadas].sort()).toEqual(
      [...semRs, 'crm_metas_manage', 'sales_value_view'].sort()
    );

    await wrapper.setProps({ permissions: ligadas });
    await metas().trigger('click');
    expect([...ultimo(wrapper)].sort()).toEqual(
      [...semRs, 'sales_value_view'].sort()
    );
  });

  // Rodada 3: desligar uma linha "liga junto" tem um comportamento só (tira só a chave da linha).
  it('desligar "Disparar campanhas" tira só o disparo: campaign_manage fica e a faixa com "Desfazer" some', async () => {
    const wrapper = montar();
    await wrapper
      .find('[data-cuidado="campaign_send"] [role="switch"]')
      .trigger('click');
    await wrapper.find('[data-acao]').trigger('click');
    await wrapper.setProps({ permissions: ultimo(wrapper) });

    await wrapper
      .find('[data-cuidado="campaign_send"] [role="switch"]')
      .trigger('click');
    const depois = ultimo(wrapper);
    expect(depois).toEqual([...ATENDENTE, 'campaign_manage']);
    await wrapper.setProps({ permissions: depois });
    expect(wrapper.find('[data-faixa-junto]').exists()).toBe(false);

    // Religar não traz de volta o "Desfazer" velho.
    await wrapper.setProps({ permissions: [...depois, 'campaign_send'] });
    expect(wrapper.find('[data-faixa-junto]').exists()).toBe(false);
  });

  // Função antiga com crm_admin sem as seis gravadas: o servidor dá tudo (CrmPermissions#crm_permission?).
  it('crm_admin sem as seis gravadas: IA e planilha das vendas aparecem ligadas e travadas, como na prévia', () => {
    const legada = [...ATENDENTE, 'crm_view', 'crm_admin'];
    const wrapper = montar(ADMIN, legada, legada);
    ['crm_manage_ai', 'crm_export'].forEach(chave => {
      const linha = wrapper.find(`[data-cuidado="${chave}"]`);
      expect(linha.find('[role="switch"]').attributes('aria-checked')).toBe(
        'true'
      );
      expect(linha.text()).toContain('Vem com "Cuida de tudo nas vendas".');
      expect(linha.text()).not.toContain('você mudou');
    });
    expect(wrapper.find('[data-cuidado="crm_metas_manage"]').exists()).toBe(
      false
    );
  });

  // Rodada 4: quem tem "Cuida de tudo" sem crm_manage_cards altera outra função com crm_admin. O alcance é o das
  // chaves gravadas (mais as implicadas), como no servidor; antes, o que o crm_admin dá punha "Apagar contatos" no
  // cadeado sem motivo (FUNCOES_EQUIPE.TRAVA.undefined).
  it('alcance pelas chaves gravadas: apagar contatos liga junto, e o cadeado sempre diz o motivo', async () => {
    const outra = ['contact_view', 'crm_view', 'crm_admin'];
    const wrapper = montar(TUDO_SEM_MEXER, outra, outra);
    expect(wrapper.find('[data-cuidado="contact_delete"]').exists()).toBe(true);
    expect(wrapper.find('[data-cadeado="contact_delete"]').exists()).toBe(
      false
    );
    // Rodada 5: o cadeado existe aqui (o que a Carla não dá); abri-lo é o que mostra os motivos.
    const cadeado = wrapper.find('[data-recolhida]');
    expect(cadeado.exists()).toBe(true);
    await cadeado.trigger('click');
    expect(wrapper.text()).not.toContain('FUNCOES_EQUIPE.TRAVA');
  });
});
