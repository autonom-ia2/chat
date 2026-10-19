import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NovaConversaEntrada from '../NovaConversaEntrada.vue';

// #1459 — a ponte escolhe a tela pela flag de conta `nova_conversa_tela`:
// ligada, a gaveta nova; desligada, o popover antigo. Props, slot e evento
// passam direto para a que estiver montada.
const estado = vi.hoisted(() => ({
  features: null,
  pedidos: [],
  permissoes: [],
}));

// Um dublê por tela, com a mesma interface pública das duas de verdade: props
// `contactId` e `align`, evento `close` e o slot `trigger`, que recebe o
// estado de aberto (aqui, um estado de verdade, que o botão interno muda).
const { tela } = vi.hoisted(() => ({
  tela: nome => ({
    name: nome,
    props: ['contactId', 'align'],
    emits: ['close'],
    data: () => ({ aberta: false }),
    template: `<div data-tela="${nome}" :data-contato="contactId" :data-align="align">
      <slot name="trigger" :is-open="aberta" />
      <button data-alternar @click="aberta = !aberta" />
      <button data-fechar @click="$emit('close')" />
    </div>`,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome => {
    const getters = {
      getCurrentAccountId: 7,
      getCurrentUser: {
        accounts: [{ id: 7, permissions: estado.permissoes }],
      },
      'accounts/isFeatureEnabledonAccount': (contaId, flag) => {
        estado.pedidos.push([contaId, flag]);
        return estado.features.value[flag] || false;
      },
    };
    return ref(getters[nome]);
  },
}));

vi.mock('../NovaConversaGaveta.vue', () => ({ default: tela('nova') }));
vi.mock(
  'dashboard/components-next/NewConversation/ComposeConversation.vue',
  () => ({ default: tela('antiga') })
);

const montar = (attrs = {}) =>
  mount(NovaConversaEntrada, {
    attrs,
    slots: {
      trigger: `<template #trigger="{ isOpen }">
        <button data-abrir :data-aberta="String(isOpen)">Enviar</button>
      </template>`,
    },
  });

describe('NovaConversaEntrada', () => {
  beforeEach(() => {
    estado.features = ref({});
    estado.pedidos = [];
    estado.permissoes = [];
  });

  // #1804: quem só lê conversas não vê "Nova conversa" em nenhum ponto de entrada.
  it('não aparece para quem só lê conversas; aparece se ela também atende', () => {
    estado.permissoes = ['conversation_view', 'contact_view'];
    expect(montar().find('[data-tela]').exists()).toBe(false);

    estado.permissoes = [
      'conversation_view',
      'conversation_participating_manage',
    ];
    expect(montar().find('[data-tela="antiga"]').exists()).toBe(true);
  });

  it('monta a gaveta nova com a flag ligada na conta atual', () => {
    estado.features.value = { [FEATURE_FLAGS.NOVA_CONVERSA_TELA]: true };
    const wrapper = montar();

    expect(wrapper.find('[data-tela="nova"]').exists()).toBe(true);
    expect(wrapper.find('[data-tela="antiga"]').exists()).toBe(false);
    expect(estado.pedidos).toContainEqual([7, 'nova_conversa_tela']);
  });

  it('monta o popover antigo com a flag desligada', () => {
    const wrapper = montar();

    expect(wrapper.find('[data-tela="antiga"]').exists()).toBe(true);
    expect(wrapper.find('[data-tela="nova"]').exists()).toBe(false);
  });

  it('troca de tela quando a flag muda, sem recarregar', async () => {
    const wrapper = montar();

    estado.features.value = { [FEATURE_FLAGS.NOVA_CONVERSA_TELA]: true };
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-tela="nova"]').exists()).toBe(true);
  });

  it.each([
    ['nova', true],
    ['antiga', false],
  ])('passa props, slot e evento para a tela %s', async (nome, ligada) => {
    const fechou = vi.fn();
    estado.features.value = { [FEATURE_FLAGS.NOVA_CONVERSA_TELA]: ligada };
    const wrapper = montar({ contactId: '9', align: 'start', onClose: fechou });

    const montada = wrapper.find(`[data-tela="${nome}"]`);
    expect(montada.attributes('data-contato')).toBe('9');
    expect(montada.attributes('data-align')).toBe('start');
    // O escopo do slot atravessa a ponte: o botão de quem usa vê o estado.
    const botao = () => montada.find('[data-abrir]').attributes('data-aberta');
    expect(botao()).toBe('false');
    await montada.find('[data-alternar]').trigger('click');
    expect(botao()).toBe('true');
    await montada.find('[data-fechar]').trigger('click');
    expect(fechou).toHaveBeenCalledTimes(1);
  });
});
