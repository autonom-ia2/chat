import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import duasVersoes from 'dashboard/i18n/locale/en/duasVersoes.json';
import campaignJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import LivreDuasVersoes from '../components/LivreDuasVersoes.vue';

// #3099 — o passo "Mandar mensagem" com duas versões: ligar põe `versoes` na receita, desligar tira.
const passo = { id: 'p1', tipo: 'mensagem', texto: ['Oi'] };

const montar = modelValue =>
  mount(LivreDuasVersoes, {
    props: { modelValue, catalogo: { valores: [] }, atributosDo: () => [] },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...campaignJourney, ...duasVersoes } },
        }),
      ],
      stubs: { LivreTexto: true, LivreModelo: true },
    },
  });

describe('LivreDuasVersoes', () => {
  it('ligar cria as versões com a regra padrão, sem mudar o resto do passo', async () => {
    const wrapper = montar(passo);
    await wrapper.find('[data-ligar-duas-versoes] input').setValue(true);
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      ...passo,
      versoes: {
        texto: [],
        modelo: null,
        criterio: 'respostas',
        divisao: 50,
        espera: 4,
      },
    });
  });

  it('desligar tira a chave versoes', async () => {
    const comVersoes = {
      ...passo,
      versoes: {
        texto: ['Olá'],
        modelo: null,
        criterio: 'respostas',
        divisao: 50,
        espera: 4,
      },
    };
    const wrapper = montar(comVersoes);
    await wrapper.find('[data-ligar-duas-versoes] input').setValue(false);
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual(passo);
  });

  it('o modelo da versão 2 só aparece quando o passo usa modelo', async () => {
    const versoes = {
      texto: [],
      modelo: null,
      criterio: 'respostas',
      divisao: 50,
      espera: 4,
    };
    const wrapper = montar({ ...passo, versoes });
    expect(wrapper.findComponent({ name: 'LivreModelo' }).exists()).toBe(false);
    await wrapper.setProps({
      modelValue: {
        ...passo,
        modelo: { nome: 'oi', idioma: 'pt_BR' },
        versoes,
      },
    });
    expect(wrapper.findComponent({ name: 'LivreModelo' }).exists()).toBe(true);
  });

  it('a regra fala no jeito da automação', () => {
    const versoes = {
      texto: [],
      modelo: null,
      criterio: 'respostas',
      divisao: 50,
      espera: 4,
    };
    const wrapper = montar({ ...passo, versoes });
    expect(wrapper.find('[data-frase-do-plano]').text()).toBe(
      'Each person who reaches this step gets one of the two, half each.'
    );
  });

  it('avisa quando a versão 2 ficou igual à 1', async () => {
    const versoes = {
      texto: ['Oi'],
      modelo: null,
      criterio: 'respostas',
      divisao: 50,
      espera: 4,
    };
    const wrapper = montar({ ...passo, versoes });
    expect(wrapper.find('[data-versoes-iguais]').text()).toBe(
      'Version 2 is the same as version 1. Change something so they can be compared.'
    );
    await wrapper.setProps({
      modelValue: { ...passo, versoes: { ...versoes, texto: ['Olá!'] } },
    });
    expect(wrapper.find('[data-versoes-iguais]').exists()).toBe(false);
  });
});
