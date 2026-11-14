import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PerguntasEmBlocos from '../../components/criar/PerguntasEmBlocos.vue';

// #3020 — a gaveta das perguntas de um agente pronto por ramo, em blocos: o dono liga e desliga cada pergunta, o
// contador diz quantas o cliente responde, e as perguntas que ele escreve ficam no fim. Cópia real.
withFullI18n('pt_BR');

const ITENS = [
  { id: 'p1', texto: 'Qual o CEP?', tirada: false, bloco: 'Endereço' },
  {
    id: 'p2',
    texto: 'Qual o endereço?',
    tirada: false,
    bloco: 'Endereço',
    se: 'não souber o CEP',
    segue: true,
  },
  { id: 'p3', texto: 'Quantos elevadores?', tirada: true, bloco: 'O prédio' },
  {
    id: 'p4',
    texto: 'Qual a marca deles?',
    tirada: true,
    bloco: 'O prédio',
    se: 'houver elevadores',
    segue: true,
  },
  { id: 'p5', texto: 'Tem portaria 24 horas?', tirada: false },
];

const montar = (props = {}) =>
  mount(PerguntasEmBlocos, {
    props: {
      itens: ITENS,
      nome: 'Bia',
      rotuloIncluir: 'Incluir pergunta',
      podeMudar: true,
      ...props,
    },
  });
const bloco = (wrapper, nome) => wrapper.get(`[data-bloco="${nome}"]`);
const pergunta = (wrapper, id) => wrapper.get(`[data-pergunta="${id}"]`);
const ligadas = lista => lista.filter(item => !item.tirada).map(i => i.id);

describe('PerguntasEmBlocos', () => {
  it('says at the top how many questions are on and how many every customer answers', () => {
    const wrapper = montar();

    expect(wrapper.get('[data-ligadas]').text()).toBe('3');
    expect(wrapper.get('[data-contador]').text()).toContain(
      'Todo cliente responde: 2. Só conforme a resposta: 1.'
    );
  });

  it('shows one card per block with how many are on, and only the first one open', () => {
    const wrapper = montar();

    expect(
      wrapper
        .findAll('[data-bloco]')
        .map(card => card.get('[data-ligadas-do-bloco]').text())
    ).toEqual(['Ligadas: 2 de 2', 'Ligadas: 0 de 2']);
    expect(
      wrapper
        .findAll('[data-abrir-bloco]')
        .map(botao => botao.attributes('aria-expanded'))
    ).toEqual(['true', 'false']);
    expect(wrapper.find('[data-pergunta="p3"]').exists()).toBe(false);
  });

  it('each question is a switch, and the condition shows as a plain sentence', () => {
    const wrapper = montar();

    expect(pergunta(wrapper, 'p1').attributes('role')).toBe('switch');
    expect(pergunta(wrapper, 'p1').attributes('aria-checked')).toBe('true');
    expect(pergunta(wrapper, 'p2').get('[data-condicao]').text()).toBe(
      'Só pergunta se não souber o CEP.'
    );
    expect(pergunta(wrapper, 'p1').find('[data-condicao]').exists()).toBe(
      false
    );
  });

  it('marks the question that depends on the one above it', () => {
    const wrapper = montar();

    expect(pergunta(wrapper, 'p2').find('[data-segue]').exists()).toBe(true);
    expect(pergunta(wrapper, 'p1').find('[data-segue]').exists()).toBe(false);
  });

  it('says it is saving while the change goes, and saved only when the server kept it', async () => {
    const wrapper = montar();
    expect(wrapper.find('[data-estado]').exists()).toBe(false);

    await pergunta(wrapper, 'p1').trigger('click');
    await wrapper.setProps({ gravando: true });
    expect(wrapper.get('[data-estado]').text()).toBe('Salvando…');

    const [lista, aoGravar] = wrapper.emitted('mudar')[0];
    aoGravar();
    await wrapper.setProps({ itens: lista, gravando: false });
    expect(wrapper.get('[data-estado]').text()).toBe('Salvo');
  });

  it('does not say saved when the server refuses the change', async () => {
    const wrapper = montar();

    await pergunta(wrapper, 'p1').trigger('click');
    await wrapper.setProps({ gravando: true });
    await wrapper.setProps({ gravando: false });

    expect(wrapper.find('[data-estado]').exists()).toBe(false);
  });

  it('a tap changes the screen at once and sends the whole new list', async () => {
    const wrapper = montar();

    await pergunta(wrapper, 'p1').trigger('click');

    expect(wrapper.get('[data-ligadas]').text()).toBe('1');
    expect(pergunta(wrapper, 'p2').attributes('aria-checked')).toBe('false');
    expect(wrapper.emitted('mudar')).toHaveLength(1);
    expect(ligadas(wrapper.emitted('mudar')[0][0])).toEqual(['p5']);
  });

  it('a tap while a change is still going waits and leaves with everything the owner tapped', async () => {
    const wrapper = montar();
    await bloco(wrapper, 'O prédio').get('[data-abrir-bloco]').trigger('click');

    await pergunta(wrapper, 'p3').trigger('click');
    await wrapper.setProps({ gravando: true });
    await pergunta(wrapper, 'p4').trigger('click');
    expect(wrapper.emitted('mudar')).toHaveLength(1);
    expect(wrapper.vm.pendente).toBe(true);

    const [primeira, aoGravar] = wrapper.emitted('mudar')[0];
    aoGravar();
    await wrapper.setProps({ itens: primeira, gravando: false });

    expect(wrapper.vm.pendente).toBe(false);
    expect(wrapper.emitted('mudar')).toHaveLength(2);
    expect(ligadas(wrapper.emitted('mudar')[1][0])).toEqual([
      'p1',
      'p2',
      'p3',
      'p4',
      'p5',
    ]);
  });

  it('a tap while a new question of the owner is being saved does not lose that question', async () => {
    const wrapper = montar();
    const suas = wrapper.get('[data-suas-perguntas]');
    await suas.get('[data-incluir-item]').trigger('click');
    await suas.get('[data-incluindo] textarea').setValue('Tem piscina?');
    await suas.get('[data-confirmar-inclusao]').trigger('click');
    await wrapper.setProps({ gravando: true });

    await pergunta(wrapper, 'p1').trigger('click');

    const [enviada, aoGravar] = wrapper.emitted('mudar')[0];
    const doServidor = enviada.map(item =>
      item.id ? item : { ...item, id: 'p6' }
    );
    aoGravar();
    await wrapper.setProps({ itens: doServidor, gravando: false });

    const [segunda] = wrapper.emitted('mudar')[1];
    expect(segunda.find(item => item.id === 'p6')).toEqual({
      id: 'p6',
      texto: 'Tem piscina?',
      tirada: false,
    });
    expect(segunda.find(item => item.id === 'p1').tirada).toBe(true);
  });

  it('when the server refuses, the taps kept while it went are dropped too', async () => {
    const wrapper = montar();

    await pergunta(wrapper, 'p1').trigger('click');
    await wrapper.setProps({ gravando: true });
    await pergunta(wrapper, 'p2').trigger('click');
    await wrapper.setProps({ gravando: false });

    expect(wrapper.emitted('mudar')).toHaveLength(1);
    expect(wrapper.get('[data-ligadas]').text()).toBe('3');
    expect(wrapper.vm.pendente).toBe(false);
  });

  it('when the server refuses, the screen goes back to the list it has', async () => {
    const wrapper = montar();

    await pergunta(wrapper, 'p1').trigger('click');
    await wrapper.setProps({ gravando: true });
    await wrapper.setProps({ gravando: false });

    expect(wrapper.get('[data-ligadas]').text()).toBe('3');
    expect(pergunta(wrapper, 'p1').attributes('aria-checked')).toBe('true');
  });

  it('"Turn all on" and "Turn all off" change the whole block', async () => {
    const wrapper = montar();
    const endereco = bloco(wrapper, 'Endereço');

    expect(endereco.get('[data-ligar-todas]').attributes('aria-disabled')).toBe(
      'true'
    );
    await endereco.get('[data-ligar-todas]').trigger('click');
    expect(wrapper.emitted('mudar')).toBeUndefined();

    await endereco.get('[data-desligar-todas]').trigger('click');

    expect(ligadas(wrapper.emitted('mudar')[0][0])).toEqual(['p5']);
    expect(endereco.get('[data-ligadas-do-bloco]').text()).toBe(
      'Ligadas: 0 de 2'
    );
    expect(
      endereco.get('[data-ligar-todas]').attributes('aria-disabled')
    ).toBeUndefined();
    expect(
      endereco.get('[data-desligar-todas]').attributes('aria-disabled')
    ).toBe('true');
  });

  it('keeps the questions the owner wrote at the end, and a new one leaves after the ones of the model', async () => {
    const wrapper = montar();
    const suas = wrapper.get('[data-suas-perguntas]');

    expect(suas.text()).toContain('Suas perguntas');
    expect(suas.get('[data-texto-do-item]').text()).toBe(
      'Tem portaria 24 horas?'
    );
    await suas.get('[data-incluir-item]').trigger('click');
    await suas.get('[data-incluindo] textarea').setValue('Tem piscina?');
    await suas.get('[data-confirmar-inclusao]').trigger('click');

    const [lista] = wrapper.emitted('mudar')[0];
    expect(lista.map(item => item.id)).toEqual([
      'p1',
      'p2',
      'p3',
      'p4',
      'p5',
      undefined,
    ]);
    expect(lista[5]).toEqual({ texto: 'Tem piscina?', tirada: false });
  });

  it('who can only look sees the switches without being able to change them', async () => {
    const wrapper = montar({ podeMudar: false });

    expect(pergunta(wrapper, 'p1').attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-desligar-todas]').exists()).toBe(false);
    await pergunta(wrapper, 'p1').trigger('click');
    expect(wrapper.emitted('mudar')).toBeUndefined();
  });
});
