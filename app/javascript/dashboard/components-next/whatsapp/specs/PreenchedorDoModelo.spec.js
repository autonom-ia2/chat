import { mount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import formatos from '../../../../../../spec/fixtures/whatsapp_templates/formatos_da_conversa.json';
import PreenchedorDoModelo from '../PreenchedorDoModelo.vue';

// #1705: o preenchedor da conversa só libera o envio com o código do cupom e,
// na oferta com contagem, com a validade no fuso da conta.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (chave, valores) => `${chave}${JSON.stringify(valores || {})}` }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ id: 1, timezone: 'America/Sao_Paulo' }),
  }),
}));

const modeloDo = nome =>
  formatos.casos.find(caso => caso.nome === nome).template;

const montar = template =>
  mount(PreenchedorDoModelo, {
    props: { template },
    global: { mocks: { $t: chave => chave } },
    slots: {
      actions: `<template #actions="{ disabled, sendMessage }">
        <button data-enviar :disabled="disabled" @click="sendMessage">x</button>
      </template>`,
    },
  });

describe('PreenchedorDoModelo', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-16T12:00:00Z'));
  });
  afterEach(() => vi.useRealTimers());

  it('cupom sem campo no texto: enviar só libera com o código', async () => {
    const wrapper = montar(modeloDo('cupom_com_codigo'));
    await nextTick();
    const enviar = wrapper.find('[data-enviar]');

    expect(enviar.attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-conversa-cupom-falta]').exists()).toBe(true);

    await wrapper.find('input').setValue('CUPOM10');

    expect(enviar.attributes('disabled')).toBeUndefined();
    expect(wrapper.find('[data-conversa-cupom-falta]').exists()).toBe(false);
    await enviar.trigger('click');
    expect(
      wrapper.emitted('sendMessage')[0][0].templateParams.processed_params
    ).toEqual({ buttons: [{ type: 'copy_code', parameter: 'CUPOM10' }] });
  });

  it('cupom com mais de 15 letras não libera', async () => {
    const wrapper = montar(modeloDo('cupom_com_codigo'));
    await nextTick();
    await wrapper.find('input').setValue('CUPOMDEZESSEISXX');

    expect(wrapper.find('[data-enviar]').attributes('disabled')).toBeDefined();
  });

  it('oferta com contagem: pede a validade no fuso da conta e a manda em ms', async () => {
    const wrapper = montar(modeloDo('oferta_com_validade_preenchida'));
    await nextTick();
    const validade = wrapper.find('[data-conversa-validade] input');

    expect(validade.exists()).toBe(true);
    expect(wrapper.text()).toContain('"zona":"America/Sao Paulo"');
    expect(wrapper.text()).not.toContain('Brasília');

    const [corpo, cupom] = wrapper.findAll('input[type="text"]');
    await corpo.setValue('Ana');
    await cupom.setValue('HOJE25');
    const enviar = wrapper.find('[data-enviar]');
    expect(enviar.attributes('disabled')).toBeDefined();

    await validade.setValue('2026-10-15T18:00');
    expect(enviar.attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('MODELOS_WHATSAPP.CONVERSA.VALIDADE_PASSADA');

    await validade.setValue('2026-10-20T18:00');
    expect(enviar.attributes('disabled')).toBeUndefined();
    await enviar.trigger('click');

    // 18:00 em São Paulo (UTC-3) = 21:00 UTC.
    expect(
      wrapper.emitted('sendMessage')[0][0].templateParams.processed_params
    ).toEqual({
      body: { 1: 'Ana' },
      buttons: [{ type: 'copy_code', parameter: 'HOJE25' }],
      limited_time_offer: {
        expiration_time_ms: Date.UTC(2026, 9, 20, 21, 0),
      },
    });
  });

  it('modelo sem cupom nem oferta não pede nada a mais', async () => {
    const wrapper = montar(modeloDo('texto_simples'));
    await nextTick();

    expect(wrapper.find('[data-conversa-validade]').exists()).toBe(false);
    expect(wrapper.find('[data-conversa-cupom-falta]').exists()).toBe(false);
    expect(wrapper.find('[data-enviar]').attributes('disabled')).toBeUndefined();
  });
});
