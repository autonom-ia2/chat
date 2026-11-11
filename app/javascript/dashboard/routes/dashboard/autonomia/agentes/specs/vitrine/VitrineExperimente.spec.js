import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import VitrineExperimente from '../../vitrine/components/VitrineExperimente.vue';
import { ferramentaPorId } from '../../vitrine/catalogo';

// #2858 F2 — o Experimente pede o que a pessoa tem na mão ("Onix 2020", "Ribeirão Preto"), nunca um código técnico,
// e diz em palavras simples quando a conta não tem IA, quando não entendeu e quando mostrou a opção mais provável.
// Cópia real em pt_BR.
withFullI18n('pt_BR');

const experimentar = vi.hoisted(() => vi.fn());
vi.mock('../../vitrine/useVitrine', () => ({
  useVitrine: () => ({ experimentar }),
}));

const montadas = [];
const montar = id => {
  const wrapper = mount(VitrineExperimente, {
    props: { ferramenta: ferramentaPorId(id) },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return wrapper;
};

const campo = wrapper => wrapper.find('[data-experimente-valor]');
const rotulo = wrapper => wrapper.find('label').text();
const rodar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

beforeEach(() => experimentar.mockReset());
afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('VitrineExperimente', () => {
  it('car value asks for "car and year", as people say it, not the table code', () => {
    const wrapper = montar('fipe');
    expect(rotulo(wrapper)).toBe('Carro e ano');
    expect(campo(wrapper).element.value).toBe('Onix 2020');
  });

  it('cities ask for a city and holidays for a date or deadline in plain words', () => {
    expect(rotulo(montar('cidades'))).toBe('Cidade');
    expect(campo(montar('cidades')).element.value).toBe('Ribeirão Preto');
    const feriados = montar('feriados');
    expect(rotulo(feriados)).toBe('Data ou prazo');
    expect(campo(feriados).element.value.startsWith('dias úteis até ')).toBe(
      true
    );
  });

  it('sends what the person wrote and shows the result with the "most likely" notice', async () => {
    experimentar.mockResolvedValue({
      situacao: 'encontrado',
      mais_provavel: true,
      dados: { valor: 'R$ 60.822,00', modelo: 'ONIX HATCH LT 1.0' },
    });
    const wrapper = montar('fipe');
    await rodar(wrapper);
    expect(experimentar).toHaveBeenCalledWith('fipe', 'Onix 2020');
    expect(wrapper.find('[data-experimente-resultado]').text()).toContain(
      'R$ 60.822,00'
    );
    expect(wrapper.find('[data-experimente-mais-provavel]').text()).toBe(
      'Havia mais de uma opção, e mostrei a mais provável. Na conversa, o agente pergunta ao cliente quando tiver dúvida.'
    );
  });

  // #2858 F4 — "Deu certo" com nada embaixo (a resposta sem nenhum campo com rótulo): uma frase neutra, e o aviso no
  // console de desenvolvimento. O spec de cobertura (resultadoDasFontes.spec.js) garante que as nossas fontes têm linhas.
  it('a found answer without any labeled line says so instead of an empty box', async () => {
    const aviso = vi.spyOn(console, 'warn').mockImplementation(() => {});
    experimentar.mockResolvedValue({
      situacao: 'encontrado',
      dados: { campo_sem_rotulo: 'x', lista_sem_rotulo: [{ a: 1 }] },
    });
    const wrapper = montar('produtos_seguradoras');
    await rodar(wrapper);
    const resultado = wrapper.find('[data-experimente-resultado]');
    expect(resultado.find('[data-experimente-sem-linhas]').text()).toBe(
      'A consulta respondeu, mas não consigo mostrar aqui.'
    );
    expect(resultado.find('dl').exists()).toBe(false);
    expect(aviso).toHaveBeenCalledWith(
      'Experimente: resposta sem campo com rótulo',
      'produtos_seguradoras',
      ['campo_sem_rotulo', 'lista_sem_rotulo']
    );
    aviso.mockRestore();
  });

  it('the F4 health and insurance boxes ask for city with state and for insurer with the kind of insurance', () => {
    const hospitais = montar('hospitais');
    expect(rotulo(hospitais)).toBe('Cidade e estado');
    expect(campo(hospitais).element.value).toBe('Campinas SP');
    const produtos = montar('produtos_seguradoras');
    expect(rotulo(produtos)).toBe('Seguradora e tipo de seguro');
    expect(campo(produtos).element.value).toBe('seguro cyber da Allianz');
  });

  it('no notice when there was a single option', async () => {
    experimentar.mockResolvedValue({
      situacao: 'encontrado',
      dados: { valor: 'R$ 60.822,00' },
    });
    const wrapper = montar('fipe');
    await rodar(wrapper);
    expect(wrapper.find('[data-experimente-mais-provavel]').exists()).toBe(
      false
    );
  });

  it('the untouched example follows the language when its messages arrive late', async () => {
    const wrapper = montar('feriados');
    const { locale } = wrapper.vm.$i18n;
    wrapper.vm.$i18n.locale = 'en';
    await flushPromises();
    expect(
      campo(wrapper).element.value.startsWith('business days until ')
    ).toBe(true);
    await campo(wrapper).setValue('20/11');
    wrapper.vm.$i18n.locale = locale;
    await flushPromises();
    expect(campo(wrapper).element.value).toBe('20/11');
  });

  it.each([
    [
      'sem_ia',
      'Para experimentar esta ferramenta, a conta precisa ter a IA ligada. Peça a quem administra a conta.',
    ],
    [
      'nao_entendi',
      'Não deu para entender o que consultar. Escreva como no exemplo e tente de novo.',
    ],
  ])('%s says it in plain words', async (situacao, frase) => {
    experimentar.mockResolvedValue({ situacao });
    const wrapper = montar('fipe');
    await rodar(wrapper);
    expect(wrapper.find('[data-experimente-aviso]').text()).toBe(frase);
  });
});
