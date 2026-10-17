import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import formatos from '../../../../../../spec/fixtures/whatsapp_templates/formatos_da_conversa.json';
import PreenchedorDoModelo from '../PreenchedorDoModelo.vue';

// #1705: o preenchedor da conversa só libera o envio com o código do cupom e,
// na oferta com contagem, com a validade no fuso da conta.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) => `${chave}${JSON.stringify(valores || {})}`,
  }),
}));
// A conta de cada teste (a com fuso, ou sem fuso para o aviso).
const conta = vi.hoisted(() => ({ value: null }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: conta }),
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
    conta.value = { id: 1, timezone: 'America/Sao_Paulo' };
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

  it('cupom só com espaços não libera; com espaços em volta, vai limpo', async () => {
    const wrapper = montar(modeloDo('cupom_com_codigo'));
    await nextTick();
    const enviar = wrapper.find('[data-enviar]');

    await wrapper.find('input').setValue('   ');
    expect(enviar.attributes('disabled')).toBeDefined();

    await wrapper.find('input').setValue(' CUPOM10 ');
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
    expect(wrapper.text()).toContain(
      'MODELOS_WHATSAPP.CONVERSA.VALIDADE_PASSADA'
    );

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
    expect(
      wrapper.find('[data-enviar]').attributes('disabled')
    ).toBeUndefined();
  });

  it('código digitado na caixa do Chatwoot (com campo no texto) também vai sem espaços', async () => {
    const link = modeloDo('link_com_fim_preenchido');
    const wrapper = montar({
      ...link,
      components: [
        { type: 'BODY', text: 'Oi, {{1}}. Seu pedido saiu.' },
        link.components[1],
      ],
    });
    await nextTick();

    const [corpo, fimDoLink] = wrapper.findAll('input[type="text"]');
    await corpo.setValue('Ana');
    await fimDoLink.setValue('  AB12 ');
    await wrapper.find('[data-enviar]').trigger('click');

    const [botao] =
      wrapper.emitted('sendMessage')[0][0].templateParams.processed_params
        .buttons;
    expect(botao).toMatchObject({ type: 'url', parameter: 'AB12' });
  });

  it('link com o fim variável e sem campo no texto: só libera preenchido', async () => {
    const wrapper = montar(modeloDo('link_com_fim_preenchido'));
    await nextTick();
    const enviar = wrapper.find('[data-enviar]');

    expect(enviar.attributes('disabled')).toBeDefined();
    await wrapper.find('[data-conversa-botao="0"] input').setValue('AB12');
    expect(enviar.attributes('disabled')).toBeUndefined();
  });

  it('botão sem campo antes do cupom (posição vazia na lista) não quebra a tela', async () => {
    const wrapper = montar({
      name: 'cupom_com_resposta',
      language: 'pt_BR',
      components: [
        { type: 'BODY', text: 'Oi, {{1}}. Use o cupom.' },
        {
          type: 'BUTTONS',
          buttons: [
            { type: 'QUICK_REPLY', text: 'Parar' },
            { type: 'COPY_CODE', example: ['X1'] },
          ],
        },
      ],
    });
    await nextTick();

    const caixas = wrapper.findAll('input[type="text"]');
    expect(caixas).toHaveLength(2);
    await caixas[0].setValue('Ana');
    await caixas[1].setValue(' X1 ');
    await wrapper.find('[data-enviar]').trigger('click');

    const { buttons } =
      wrapper.emitted('sendMessage')[0][0].templateParams.processed_params;
    expect(buttons[0]).toBeUndefined();
    expect(buttons[1]).toEqual({ type: 'copy_code', parameter: 'X1' });
  });

  it('conta sem fuso: avisa o motivo e não deixa enviar a oferta', async () => {
    conta.value = { id: 1 };
    const wrapper = montar(modeloDo('oferta_com_validade_preenchida'));
    await nextTick();

    expect(wrapper.text()).toContain(
      'MODELOS_WHATSAPP.CONVERSA.VALIDADE_SEM_FUSO'
    );
    expect(wrapper.text()).toContain(
      'MODELOS_WHATSAPP.CONVERSA.VALIDADE_TITULO'
    );
    expect(
      wrapper.find('[data-conversa-validade] input').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-enviar]').attributes('disabled')).toBeDefined();
  });

  it('validade que vence com a tela aberta desliga o envio em até 30 s', async () => {
    const wrapper = montar(modeloDo('oferta_com_validade_preenchida'));
    await nextTick();
    const [corpo, cupom] = wrapper.findAll('input[type="text"]');
    await corpo.setValue('Ana');
    await cupom.setValue('HOJE25');
    // 09:05 em São Paulo = 12:05 UTC, 5 minutos à frente.
    await wrapper
      .find('[data-conversa-validade] input')
      .setValue('2026-10-16T09:05');
    const enviar = wrapper.find('[data-enviar]');
    expect(enviar.attributes('disabled')).toBeUndefined();

    vi.advanceTimersByTime(6 * 60 * 1000);
    await nextTick();

    expect(enviar.attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain(
      'MODELOS_WHATSAPP.CONVERSA.VALIDADE_PASSADA'
    );
  });
});
