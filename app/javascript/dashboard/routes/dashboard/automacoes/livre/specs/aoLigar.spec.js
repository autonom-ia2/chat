import { mount } from '@vue/test-utils';
import { custoPorExecucao, oQueLigarFaz } from '../aoLigar';
import LivreConfirmarLigar from '../components/LivreConfirmarLigar.vue';

// #2574 (F5.4) — ligar a automação que manda mensagem, avisa a equipe ou usa
// IA pede confirmação, dizendo isso e o custo. O valor da IA vem da média dos
// últimos 30 dias ou, antes da primeira vez, da estimativa pelo modelo do passo,
// nunca de uma ida à IA, e só para quem vê os custos.
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
      ia: [{ id: 'p4', tipo: 'decidir' }],
      modeloDaMeta: false,
      pede: true,
    });
  });

  it('o escrever só manda mensagem com destino mensagem; ele sempre usa IA', () => {
    expect(
      oQueLigarFaz(
        receita([{ id: 'p1', tipo: 'escrever', destino: 'sugestao' }])
      )
    ).toMatchObject({
      manda: false,
      ia: [{ id: 'p1', tipo: 'escrever' }],
      pede: true,
    });
    expect(
      oQueLigarFaz(
        receita([{ id: 'p1', tipo: 'escrever', destino: 'mensagem' }])
      ).manda
    ).toBe(true);
  });

  // Revisão do #2574: a agente de IA fala com o cliente; liga com confirmação,
  // mas fica fora da soma do custo dos passos de IA.
  it('passar para a agente de IA pede confirmação e conta como mensagem', () => {
    expect(
      oQueLigarFaz(receita([{ id: 'p1', tipo: 'ia_assumir', agente_id: 3 }]))
    ).toMatchObject({ manda: true, agente: true, ia: [], pede: true });
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
  const p1 = { id: 'p1', tipo: 'decidir' };
  const p2 = { id: 'p2', tipo: 'resumir' };
  const p3 = { id: 'p3', tipo: 'extrair' };
  const custos = {
    p1: { media: 0.002, vezes: 4, tokens: 1500 },
    p2: { media: 0.001, tokens: 900 },
  };
  const estimativa = {
    extrair: { modelo: 'gpt-6-luna', tokens: 3000, custo_usd: 0.0005 },
  };

  it('soma a média e os tokens de cada passo que já rodou', () => {
    const custo = custoPorExecucao([p1, p2], { custos });

    expect(custo.valor).toBeCloseTo(0.003);
    expect(custo).toMatchObject({ tokens: 2400, estimado: false });
  });

  it('o passo que ainda não rodou entra pela estimativa do tipo dele', () => {
    const custo = custoPorExecucao([p1, p3], { custos, estimativa });

    expect(custo.valor).toBeCloseTo(0.0025);
    expect(custo).toMatchObject({ tokens: 4500, estimado: true });
  });

  it('sem média nem estimativa, ou sem passo de IA, é null', () => {
    expect(custoPorExecucao([p1, p3], { custos })).toBeNull();
    expect(custoPorExecucao([], { custos, estimativa })).toBeNull();
  });

  it('sem tokens num passo, o valor vale e os tokens ficam null', () => {
    const custo = custoPorExecucao([p1], { custos: { p1: { media: 0.002 } } });

    expect(custo).toMatchObject({ valor: 0.002, tokens: null });
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
      `${C}.IA_CUSTO(`
    );
  });

  it('no primeiro ligar, mostra o valor e os tokens estimados', () => {
    const wrapper = montar({
      receita: COM_IA,
      custos: {
        com_valores: true,
        custos: {},
        estimativa: { resumir: { tokens: 3300, custo_usd: 0.0007 } },
      },
    });

    expect(linhas(wrapper)).toEqual(['clientes', 'ia', 'custo', 'tokens']);
    expect(wrapper.find('[data-confirmar="custo"]').text()).toContain(
      `${C}.IA_CUSTO_ESTIMADO`
    );
    expect(wrapper.find('[data-confirmar="tokens"]').text()).toBe(
      `${C}.TOKENS(3.300)`
    );
  });

  it('sem média nem estimativa, diz que o custo aparece depois', () => {
    const wrapper = montar({
      receita: COM_IA,
      custos: { com_valores: true, custos: {} },
    });

    expect(wrapper.find('[data-confirmar="custo"]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.CUSTO.PRIMEIRA'
    );
  });

  it('a agente de IA tem frase própria, sem valor', () => {
    const wrapper = montar({
      receita: receita([{ id: 'p1', tipo: 'ia_assumir', agente_id: 3 }]),
      custos: { com_valores: true, custos: {}, estimativa: {} },
    });

    expect(linhas(wrapper)).toEqual(['clientes', 'agente']);
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
