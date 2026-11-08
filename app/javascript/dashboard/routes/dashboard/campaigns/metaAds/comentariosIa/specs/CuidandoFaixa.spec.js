import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { describe, expect, it } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import CuidandoFaixa from '../CuidandoFaixa.vue';
import pt from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';

// O Dialog real vai para o body (Teleport) e usa o <dialog> nativo: aqui basta saber que abriu e o que confirma.
const DialogStub = defineComponent({
  props: { title: { type: String, default: '' } },
  emits: ['confirm'],
  setup(props, { emit, expose }) {
    const aberto = ref(false);
    expose({
      open: () => {
        aberto.value = true;
      },
      close: () => {
        aberto.value = false;
      },
    });
    return () =>
      h('div', { 'data-dialog': aberto.value ? 'open' : 'closed' }, [
        h('p', props.title),
        h('button', { 'data-confirm': '', onClick: () => emit('confirm') }),
      ]);
  },
});

const montar = posts =>
  mount(CuidandoFaixa, {
    props: { posts, canManage: true },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: pt } }),
      ],
      stubs: { Dialog: DialogStub },
    },
  });

const pausados = [
  { id: '1', status: 'paused', network: 'instagram', results: {} },
  { id: '2', status: 'paused', network: 'instagram', results: {} },
];

describe('CuidandoFaixa (#2212)', () => {
  it('"Voltar a cuidar de todos" pergunta antes, com a contagem, e só religa ao confirmar', async () => {
    const wrapper = montar(pausados);
    const dialogo = wrapper.findComponent(DialogStub);

    await wrapper.find('[data-ia-resume-all]').trigger('click');

    expect(wrapper.find('[data-dialog]').attributes('data-dialog')).toBe(
      'open'
    );
    expect(dialogo.text()).toContain('Voltar a cuidar de 2 posts?');
    expect(wrapper.emitted('resumeAll')).toBeUndefined();

    await wrapper.find('[data-confirm]').trigger('click');

    expect(wrapper.emitted('resumeAll')).toHaveLength(1);
    expect(wrapper.find('[data-dialog]').attributes('data-dialog')).toBe(
      'closed'
    );
  });

  it('"Pausar todos" continua com um toque, sem perguntar', async () => {
    const wrapper = montar([{ ...pausados[0], status: 'on' }]);

    await wrapper.find('[data-ia-pause-all]').trigger('click');

    expect(wrapper.emitted('pauseAll')).toHaveLength(1);
  });
});
