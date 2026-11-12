import { shallowMount } from '@vue/test-utils';
import { computed } from 'vue';
import AutomationRuleRow from './AutomationRuleRow.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2448: sem integration_manage, a regra com webhook ou transcrição por e-mail não liga, não desliga e não é copiada;
// a linha diz por quê. Apagar e abrir para ler continuam.
// #2473: com a flag da fundação, a regra que mexe no funil pede também a chave de funis para ligar, desligar e copiar.
let podeIntegrar = false;
let chavesDeFunil = [];
let fundacaoLigada = true;
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => computed(() => true),
  usePermissionGranted: key =>
    computed(() =>
      key === 'integration_manage' ? podeIntegrar : chavesDeFunil.includes(key)
    ),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => fundacaoLigada }),
}));

const regra = (actions, conditions = []) => ({
  id: 1,
  name: 'Avisa o sistema',
  description: '',
  active: true,
  created_on: 1730000000,
  actions,
  conditions,
});

const montar = automation =>
  shallowMount(AutomationRuleRow, {
    props: { automation },
    global: {
      stubs: {
        BaseTableRow: { template: '<div><slot /></div>' },
        BaseTableCell: { template: '<div><slot /></div>' },
      },
      directives: { tooltip: {} },
    },
  });

const botaoCopiar = wrapper =>
  wrapper
    .findAllComponents(Button)
    .find(botao => botao.props('icon') === 'i-woot-clone');

describe('AutomationRuleRow e as ações que saem da plataforma', () => {
  it('sem integration_manage, a regra com webhook não liga nem copia, e diz por quê', () => {
    podeIntegrar = false;
    const wrapper = montar(
      regra([{ action_name: 'send_webhook_event', action_params: [] }])
    );

    expect(wrapper.findComponent(ToggleSwitch).vm.$attrs.disabled).toBe(true);
    expect(botaoCopiar(wrapper).vm.$attrs.disabled).toBe(true);
    expect(wrapper.find('p.text-n-amber-11').exists()).toBe(true);
  });

  it('sem integration_manage, a regra sem saída para fora segue normal', () => {
    podeIntegrar = false;
    const wrapper = montar(
      regra([{ action_name: 'add_label', action_params: ['lead'] }])
    );

    expect(wrapper.findComponent(ToggleSwitch).vm.$attrs.disabled).toBe(false);
    expect(botaoCopiar(wrapper).vm.$attrs.disabled).toBe(false);
    expect(wrapper.find('p.text-n-amber-11').exists()).toBe(false);
  });

  it('com integration_manage, a regra com webhook liga e copia', () => {
    podeIntegrar = true;
    const wrapper = montar(
      regra([{ action_name: 'send_email_transcript', action_params: [] }])
    );

    expect(wrapper.findComponent(ToggleSwitch).vm.$attrs.disabled).toBe(false);
    expect(botaoCopiar(wrapper).vm.$attrs.disabled).toBe(false);
  });
});

describe('AutomationRuleRow e a regra que mexe no funil', () => {
  const moveCard = [{ action_name: 'crm_move_card_stage', action_params: [3] }];
  const avisoDoFunil = wrapper =>
    wrapper
      .findAll('p.text-n-amber-11')
      .some(p => p.text() === 'AUTOMATION.RULE_FUNNEL_MANAGE_ONLY');

  beforeEach(() => {
    podeIntegrar = true;
    chavesDeFunil = [];
    fundacaoLigada = true;
  });

  it('sem a chave de funis, a regra que move card não liga nem copia, e diz por quê', () => {
    const wrapper = montar(regra(moveCard));

    expect(wrapper.findComponent(ToggleSwitch).vm.$attrs.disabled).toBe(true);
    expect(botaoCopiar(wrapper).vm.$attrs.disabled).toBe(true);
    expect(avisoDoFunil(wrapper)).toBe(true);
  });

  it('sem a chave de funis, a condição de funil também trava a linha', () => {
    const condicao = [{ attribute_key: 'crm_stage_id', values: [3] }];
    const wrapper = montar(
      regra([{ action_name: 'add_label', action_params: ['lead'] }], condicao)
    );

    expect(wrapper.findComponent(ToggleSwitch).vm.$attrs.disabled).toBe(true);
    expect(botaoCopiar(wrapper).vm.$attrs.disabled).toBe(true);
  });

  it('com crm_admin, a regra que move card liga e copia', () => {
    chavesDeFunil = ['crm_admin'];
    const wrapper = montar(regra(moveCard));

    expect(wrapper.findComponent(ToggleSwitch).vm.$attrs.disabled).toBe(false);
    expect(botaoCopiar(wrapper).vm.$attrs.disabled).toBe(false);
    expect(avisoDoFunil(wrapper)).toBe(false);
  });

  it('sem a flag da fundação, a regra que move card segue normal', () => {
    fundacaoLigada = false;
    const wrapper = montar(regra(moveCard));

    expect(wrapper.findComponent(ToggleSwitch).vm.$attrs.disabled).toBe(false);
    expect(botaoCopiar(wrapper).vm.$attrs.disabled).toBe(false);
  });
});
