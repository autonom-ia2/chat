import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import campaignJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import reenvioHorario from 'dashboard/i18n/locale/en/reenvioHorario.json';
import ReenvioDaCampanha from '../reenvio/ReenvioDaCampanha.vue';
import { reenvioNovo } from '../reenvio/reenvio';

const en = { ...campaignJourney, ...reenvioHorario };
const R = reenvioHorario.REENVIO_HORARIO.REENVIO;

const CORPO_LONGO =
  'Oi, Ana! Passando para lembrar: a sua oferta de 15% vale até sexta. Quer que eu separe?';
const MODELOS = [
  {
    value: 'lembrete',
    label: 'Lembrete da oferta',
    corpo: 'Oi Ana, ainda quer?',
  },
  {
    value: 'longo',
    label: 'Oferta longa',
    corpo: CORPO_LONGO,
    variaveis: [
      { key: '1', part: 'body', variable: '1', label: 'Nome' },
      { key: '2', part: 'body', variable: '2', label: 'Desconto' },
    ],
    ligacoes: { 1: { source: 'contact', value: 'first_name' } },
  },
];

const montar = (props, opcoes = {}) =>
  mount(ReenvioDaCampanha, {
    props: { canal: 'whatsapp_official', modelos: MODELOS, ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
    ...opcoes,
  });

const abrir = async wrapper => {
  await wrapper.find('[data-alterar]').trigger('click');
};

describe('ReenvioDaCampanha (#3101)', () => {
  it('starts closed and off, saying it sends only once', () => {
    const wrapper = montar({ modelValue: null });

    expect(wrapper.find('[data-resumo]').text()).toContain(R.RESUMO_DESLIGADO);
    expect(wrapper.find('[data-resumo]').text()).toContain(R.DETALHE_DESLIGADO);
  });

  it('turns on with "did not reply, 3 days later" and turns off to null', async () => {
    const wrapper = montar({ modelValue: null });
    await abrir(wrapper);

    await wrapper.find('input[role="switch"]').setValue(true);
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual(reenvioNovo());

    await wrapper.setProps({ modelValue: reenvioNovo() });
    await wrapper.find('input[role="switch"]').setValue(false);
    expect(wrapper.emitted('update:modelValue')[1][0]).toBeNull();
  });

  it('offers "did not read" on WhatsApp Oficial but not on SMS', async () => {
    const oficial = montar({ modelValue: reenvioNovo() });
    await abrir(oficial);
    expect(oficial.find('[data-quem="nao_leu"]').exists()).toBe(true);

    const sms = montar({ modelValue: reenvioNovo(), canal: 'sms' });
    await abrir(sms);
    expect(sms.find('[data-quem="nao_leu"]').exists()).toBe(false);
    expect(sms.find('[data-reenvio-texto]').exists()).toBe(true);
  });

  it('changes the days keeping the rest', async () => {
    const wrapper = montar({ modelValue: reenvioNovo() });
    await abrir(wrapper);

    await wrapper.find('[data-dias="7"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      ...reenvioNovo(),
      dias: 7,
    });
  });

  it('shows what is missing in the closed summary, then the chosen template', async () => {
    const wrapper = montar({ modelValue: reenvioNovo() });
    expect(wrapper.find('[data-reenvio-detalhe]').text()).toBe(
      R.FALTA.SEM_MODELO
    );

    await wrapper.setProps({
      modelValue: { ...reenvioNovo(), modeloId: 'lembrete' },
    });
    expect(wrapper.find('[data-reenvio-detalhe]').text()).toContain(
      'Oi Ana, ainda quer?'
    );
    await abrir(wrapper);
    expect(wrapper.find('[data-reenvio-exemplo]').text()).toContain(
      'Oi Ana, ainda quer?'
    );
  });

  it('shows the start of a long template, never its technical name', async () => {
    const wrapper = montar({
      modelValue: {
        ...reenvioNovo(),
        modeloId: 'longo',
        ligacoes: {
          1: { source: 'contact', value: 'first_name' },
          2: { source: 'fixed', value: '15%' },
        },
      },
    });

    const detalhe = wrapper.find('[data-reenvio-detalhe]').text();
    expect(detalhe).toContain('Oi, Ana! Passando para lembrar');
    expect(detalhe).toContain('…');
    expect(detalhe).not.toContain(CORPO_LONGO);
  });

  it('brings the ready bindings with the template and asks for the rest', async () => {
    const wrapper = montar({ modelValue: reenvioNovo() });
    await abrir(wrapper);

    wrapper
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', 'longo');
    const escolhido = wrapper.emitted('update:modelValue')[0][0];
    expect(escolhido.ligacoes).toEqual(MODELOS[1].ligacoes);

    await wrapper.setProps({ modelValue: escolhido });
    expect(wrapper.find('[data-reenvio-ligacoes]').exists()).toBe(true);
    expect(wrapper.find('[data-reenvio-detalhe]').exists()).toBe(false);
  });

  it('cannot be turned on when the inbox has no other template, and says why', async () => {
    const wrapper = montar({
      modelValue: null,
      modelos: [{ value: 'x', label: 'Em análise', disabled: true }],
    });
    await abrir(wrapper);

    expect(wrapper.find('input[role="switch"]').element.disabled).toBe(true);
    expect(wrapper.find('[data-reenvio-ligar-ajuda]').text()).toBe(
      R.SEM_MODELOS
    );
  });

  it('can still be turned off if it was on without templates', async () => {
    const wrapper = montar({ modelValue: reenvioNovo(), modelos: [] });
    await abrir(wrapper);

    expect(wrapper.find('input[role="switch"]').element.disabled).toBe(false);
  });

  it('starts with the example text on SMS and the example subject on e-mail', async () => {
    const sms = montar({ modelValue: null, canal: 'sms' });
    await abrir(sms);
    await sms.find('input[role="switch"]').setValue(true);
    expect(sms.emitted('update:modelValue')[0][0].texto).toBe(R.TEXTO_EXEMPLO);

    const email = montar({ modelValue: null, canal: 'email' });
    await abrir(email);
    await email.find('input[role="switch"]').setValue(true);
    expect(email.emitted('update:modelValue')[0][0].assunto).toBe(
      R.ASSUNTO_EXEMPLO
    );
  });

  it('closes again with "Done"', async () => {
    const wrapper = montar({ modelValue: null });
    await abrir(wrapper);

    expect(wrapper.find('[data-reenvio-pronto]').text()).toBe(R.PRONTO);
    await wrapper.find('[data-reenvio-pronto]').trigger('click');
    expect(wrapper.find('[data-resumo]').exists()).toBe(true);
  });

  it('only says "Close" when there is nothing to save', async () => {
    const wrapper = montar({ modelValue: null, modelos: [] });
    await abrir(wrapper);

    expect(wrapper.find('[data-reenvio-pronto]').text()).toBe(R.FECHAR);
  });

  it('moves the focus to the first field on open and back to "Change" on close', async () => {
    const wrapper = montar({ modelValue: null }, { attachTo: document.body });
    await abrir(wrapper);
    await nextTick();
    expect(document.activeElement).toBe(
      wrapper.find('input[role="switch"]').element
    );

    await wrapper.find('[data-reenvio-pronto]').trigger('click');
    await nextTick();
    expect(document.activeElement).toBe(wrapper.find('[data-alterar]').element);
    wrapper.unmount();
  });

  it('shows the SMS parts of the second message instead of the plain count', async () => {
    const wrapper = montar({
      modelValue: { ...reenvioNovo(), texto: 'a'.repeat(161) },
      canal: 'sms',
    });
    await abrir(wrapper);

    expect(wrapper.find('[data-reenvio-contador]').text()).toContain('2 SMS');
    expect(wrapper.find('[data-reenvio-texto]').text()).not.toContain('/');
  });

  it('marks the empty text in red only after the person leaves the box', async () => {
    const wrapper = montar({ modelValue: null, canal: 'sms' });
    await abrir(wrapper);
    await wrapper.setProps({ modelValue: reenvioNovo({ texto: '' }) });

    const caixa = wrapper.find('[data-reenvio-texto] textarea');
    expect(caixa.attributes('placeholder')).toBe(R.TEXTO_PLACEHOLDER);
    expect(wrapper.find('[data-reenvio-texto]').text()).not.toContain(
      R.FALTA.SEM_TEXTO
    );

    await caixa.trigger('blur');
    expect(wrapper.find('[data-reenvio-texto]').text()).toContain(
      R.FALTA.SEM_TEXTO
    );
  });

  it('marks the empty subject right away when coming back to a block already on', async () => {
    const wrapper = montar({
      modelValue: reenvioNovo({ assunto: '' }),
      canal: 'email',
    });
    await abrir(wrapper);

    expect(
      wrapper.find('[data-reenvio-assunto] input').attributes('placeholder')
    ).toBe(R.ASSUNTO_PLACEHOLDER);
    expect(wrapper.find('[data-reenvio-assunto]').text()).toContain(
      R.FALTA.SEM_ASSUNTO
    );
  });

  it('marks in red the part of the template that still has no source', async () => {
    const wrapper = montar({
      modelValue: {
        ...reenvioNovo(),
        modeloId: 'longo',
        ligacoes: { 1: { source: 'contact', value: 'first_name' } },
      },
    });
    await abrir(wrapper);

    const escolhas = wrapper
      .find('[data-reenvio-ligacoes]')
      .findAllComponents({ name: 'ChoiceSelect' });
    expect(escolhas.map(escolha => escolha.props('invalid'))).toEqual([
      false,
      true,
    ]);
    expect(wrapper.find('[data-reenvio-erro-ligacao]').text()).toBe(
      R.LIGACAO_EM_VERMELHO
    );
  });

  it('asks only for a new subject on e-mail', async () => {
    const wrapper = montar({ modelValue: reenvioNovo(), canal: 'email' });
    await abrir(wrapper);

    expect(wrapper.find('[data-reenvio-assunto]').exists()).toBe(true);
    expect(wrapper.find('[data-reenvio-modelo]').exists()).toBe(false);
  });
});
