import { mount } from '@vue/test-utils';
import { custoPorExecucao, oQueLigarFaz } from '../aoLigar';
import LivreConfirmarLigar from '../components/LivreConfirmarLigar.vue';

// #2574 (F5.4) — ligar a automação que manda mensagem, avisa a equipe ou usa
// IA pede confirmação, dizendo isso e o custo. O valor da IA vem da média dos
// últimos 30 dias, nunca de uma ida à IA, e só para quem vê os custos.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: { value: 'pt_BR' },
    t: (chave, valores) =>
      valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
  }),
}));

const receita = passos => ({ gatilho: { tipo: 'conversa.criada' }, passos });
const C = 'AUTOMACAO_LIVRE.LIGAR.CONFIRMAR';

describe('oQueLigarFaz', () => {
  it('a que só espera liga sem confirmação', () => {
    expect(oQueLigarFaz(receita([{ id: 'p1', tipo: 'esperar' }])).pede).toBe(
      false
    );
  });

  it('acha mensagem aos clientes, aviso à equipe e IA, também nos galhos', () => {
    const faz = oQueLigarFaz(
      receita([
        {
          id: 'p1',
          tipo: 'se',
          entao: [{ id: 'p2', tipo: 'mensagem', texto: ['Oi'] }],
          senao: [{ id: 'p3', tipo: 'avisar', texto: ['Olha'] }],
        },
        { id: 'p4', tipo: 'decidir', caminhos: [] },
      ])
    );

    expect(faz).toMatchObject({
      manda: true,
      avisa: true,
      ia: ['p4'],
      modeloDaMeta: false,
      pede: true,
    });
  });

  it('o escrever só manda mensagem com destino mensagem; ele sempre usa IA', () => {
    expect(
      oQueLigarFaz(
        receita([{ id: 'p1', tipo: 'escrever', destino: 'sugestao' }])
      )
    ).toMatchObject({ manda: false, ia: ['p1'], pede: true });
    expect(
      oQueLigarFaz(
        receita([{ id: 'p1', tipo: 'escrever', destino: 'mensagem' }])
      ).manda
    ).toBe(true);
  });

  it('o modelo da Meta: a mensagem com modelo e a campanha que dispara', () => {
    expect(
      oQueLigarFaz(
        receita([{ id: 'p1', tipo: 'mensagem', modelo: { nome: 'oi' } }])
      ).modeloDaMeta
    ).toBe(true);
    expect(
      oQueLigarFaz(receita([{ id: 'p1', tipo: 'campanha', faz: 'disparar' }]))
    ).toMatchObject({ manda: true, modeloDaMeta: true });
    expect(
      oQueLigarFaz(
        receita([{ id: 'p1', tipo: 'campanha', faz: 'nao_receber' }])
      ).pede
    ).toBe(false);
  });
});

describe('custoPorExecucao', () => {
  it('soma a média de cada passo de IA; passo que nunca rodou deixa null', () => {
    const custos = { p1: { media: 0.002, vezes: 4 }, p2: { media: 0.001 } };

    expect(custoPorExecucao(['p1', 'p2'], custos)).toBeCloseTo(0.003);
    expect(custoPorExecucao(['p1', 'p3'], custos)).toBeNull();
    expect(custoPorExecucao([], custos)).toBeNull();
  });
});

describe('LivreConfirmarLigar', () => {
  const DialogoFalso = {
    name: 'DialogoDaCasa',
    props: ['titulo', 'acao'],
    emits: ['acao'],
    template: '<div data-dialogo><slot /></div>',
  };
  const montar = props =>
    mount(LivreConfirmarLigar, {
      props,
      global: {
        mocks: { $t: chave => chave },
        stubs: { DialogoDaCasa: DialogoFalso },
      },
    });
  const linhas = wrapper =>
    wrapper
      .findAll('[data-confirmar]')
      .map(item => item.attributes('data-confirmar'));
  const COM_IA = receita([
    { id: 'p1', tipo: 'mensagem', texto: ['Oi'] },
    { id: 'p2', tipo: 'resumir' },
  ]);

  it('diz o que ela faz e o custo da IA a quem vê os custos', () => {
    const wrapper = montar({
      receita: COM_IA,
      custos: { com_valores: true, custos: { p2: { media: 0.0021 } } },
    });

    expect(linhas(wrapper)).toEqual(['clientes', 'ia', 'custo']);
    expect(wrapper.find('[data-confirmar="custo"]').text()).toContain(
      `${C}.IA_CUSTO`
    );
  });

  it('sem custo ainda, diz que ele aparece depois da primeira vez', () => {
    const wrapper = montar({
      receita: COM_IA,
      custos: { com_valores: true, custos: {} },
    });

    expect(wrapper.find('[data-confirmar="custo"]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.CUSTO.PRIMEIRA'
    );
  });

  it('quem não vê os custos não vê o valor', () => {
    const wrapper = montar({
      receita: COM_IA,
      custos: { com_valores: false, custos: { p2: { media: 0.0021 } } },
    });

    expect(linhas(wrapper)).toEqual(['clientes', 'ia']);
  });

  it('"Ligar" do diálogo emite ligar', async () => {
    const wrapper = montar({ receita: COM_IA });

    await wrapper.findComponent(DialogoFalso).vm.$emit('acao');

    expect(wrapper.emitted('ligar')).toHaveLength(1);
  });
});
