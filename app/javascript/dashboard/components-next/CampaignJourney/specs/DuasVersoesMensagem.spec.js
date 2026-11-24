import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import duasVersoes from 'dashboard/i18n/locale/en/duasVersoes.json';
import campaignJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import DuasVersoesMensagem from '../DuasVersoesMensagem.vue';
import { duasVersoesVazias } from '../duasVersoes';
import { CAMPAIGN_CHANNELS } from '../campaignChannels';

// #3099 — o bloco "Duas versões da mensagem" do passo Mensagem: desligado numa linha, ligado com a versão 2 no jeito
// do canal e o plano em frases.
const M = duasVersoes.DUAS_VERSOES.MENSAGEM;
const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...campaignJourney, ...duasVersoes } },
  });

const montar = (props = {}) =>
  mount(DuasVersoesMensagem, {
    props: {
      canal: CAMPAIGN_CHANNELS.SMS,
      versoes: duasVersoesVazias(),
      primeira: { texto: 'Oi! Volte hoje.' },
      publico: 1350,
      ...props,
    },
    global: { plugins: [i18n()] },
  });

const ligado = patch => ({ ...duasVersoesVazias(), ligado: true, ...patch });

describe('DuasVersoesMensagem', () => {
  it('desligado mostra só o convite e devolve o objeto inteiro ao ligar', async () => {
    const wrapper = montar();
    expect(wrapper.text()).toContain(M.AJUDA_DESLIGADO);
    expect(wrapper.find('[data-segunda-versao-texto]').exists()).toBe(false);
    await wrapper.find('[data-ligar-duas-versoes] input').setValue(true);
    expect(wrapper.emitted('update')[0][0]).toEqual({
      ...duasVersoesVazias(),
      ligado: true,
    });
  });

  it('texto livre: começar com a versão 1 e o aviso de versão igual', async () => {
    const wrapper = montar({ versoes: ligado() });
    await wrapper.find('[data-comecar-da-1]').trigger('click');
    expect(wrapper.emitted('update')[0][0].texto).toBe('Oi! Volte hoje.');

    await wrapper.setProps({ versoes: ligado({ texto: 'Oi! Volte hoje.' }) });
    expect(wrapper.find('[data-aviso-da-2]').text()).toBe(M.IGUAL);
  });

  it('versão 2 vazia só reclama depois de quem chama pedir', async () => {
    const wrapper = montar({ versoes: ligado() });
    expect(wrapper.find('[data-aviso-da-2]').exists()).toBe(false);
    await wrapper.setProps({ mostrarFalta: true });
    expect(wrapper.find('[data-aviso-da-2]').text()).toBe(M.VAZIA);
  });

  it('o plano conta o teste e o resto do público', () => {
    const wrapper = montar({ versoes: ligado({ texto: 'Outra' }) });
    const frases = wrapper.findAll('[data-frase-do-plano]').map(f => f.text());
    expect(frases[0]).toBe(
      'First, 270 people get the test: 135 get version 1 and 135 get version 2.'
    );
    expect(frases[1]).toBe(
      'After 4 hours, the other 1,080 people get the one with more replies.'
    );
  });

  it('WhatsApp Oficial: o modelo da versão 1 e o de outras informações ficam apagados', () => {
    const wrapper = montar({
      canal: CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
      versoes: ligado(),
      primeira: { templateId: 'a' },
      modelos: [
        { value: 'a', label: 'promo_a', corpo: 'A', mesmasInformacoes: true },
        { value: 'b', label: 'promo_b', corpo: 'B', mesmasInformacoes: true },
        { value: 'c', label: 'boleto', corpo: 'C', mesmasInformacoes: false },
      ],
    });
    const opcoes = wrapper
      .findComponent({ name: 'ChoiceSelect' })
      .props('options');
    expect(opcoes.map(opcao => opcao.disabled)).toEqual([true, false, true]);
  });

  it('WhatsApp Oficial sem outro modelo que sirva oferece criar um', async () => {
    const wrapper = montar({
      canal: CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
      versoes: ligado(),
      primeira: { templateId: 'a' },
      modelos: [
        { value: 'a', label: 'promo_a', corpo: 'A', mesmasInformacoes: true },
      ],
    });
    await wrapper.find('[data-sem-outro-modelo] button').trigger('click');
    expect(wrapper.emitted('criarModelo')).toHaveLength(1);
  });

  it('e-mail: a ideia da IA vira o assunto da versão 2, sem repetir o da 1', async () => {
    const wrapper = montar({
      canal: CAMPAIGN_CHANNELS.EMAIL,
      versoes: ligado(),
      primeira: { assunto: 'Oferta da semana' },
      sugestoesDeAssunto: ['Oferta da semana', 'Só hoje: frete grátis'],
    });
    const ideias = wrapper.findAll('[data-ideia-de-assunto]');
    expect(ideias).toHaveLength(1);
    await ideias[0].trigger('click');
    expect(wrapper.emitted('update')[0][0].assunto).toBe(
      'Só hoje: frete grátis'
    );
  });
});
