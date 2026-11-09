import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import LivreIaTestar from '../components/LivreIaTestar.vue';

// #2500 C2 — "Testar este passo": uma conversa por pedido; o 1º traz as
// candidatas e os seguintes pedem cada uma pelo id, sem repetir conversa; o
// botão trava enquanto roda; o texto da IA sai só como texto; o custo só
// aparece com financial_view (mostraCusto).
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { testarPasso: vi.fn() },
}));
const podeMudar = ref(true);
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => podeMudar,
}));

const DECIDIR = {
  id: 'p1',
  tipo: 'decidir',
  caminhos: [
    { nome: 'Sinistro', chave: 'sinistro' },
    { nome: 'Cotação', chave: 'cotacao' },
  ],
};
const RECEITA = { gatilho: { tipo: 'conversa.criada' }, passos: [DECIDIR] };

const montar = (props = {}) =>
  mount(LivreIaTestar, {
    props: { passo: DECIDIR, receita: RECEITA, pronto: true, ...props },
    global: { mocks: { $t: t } },
  });

const BRUNO = {
  conversa_id: 7,
  nome: 'Bruno',
  resultado: { caminho: 'sinistro', motivo: 'bateu o carro' },
  custo_usd: 0.0021,
};
const CARLA = {
  conversa_id: 8,
  nome: 'Carla',
  resultado: { caminho: 'nenhum', motivo: 'não diz' },
  custo_usd: 0.001,
};
const primeira = (conversa, candidatas) => ({
  data: { conversa, candidatas, aviso: null },
});
const seguinte = conversa => ({ data: { conversa } });

describe('LivreIaTestar', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    podeMudar.value = true;
  });

  // #2780: na automação já salva, o servidor confere também quem a ligou.
  it('manda o id da automação já salva', async () => {
    AutomacoesAPI.testarPasso.mockResolvedValueOnce(primeira(BRUNO, [7]));
    const wrapper = montar({ automacaoId: 42 });

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.testarPasso.mock.calls[0][0].automacaoId).toBe(42);
  });

  it('o 1º pedido traz as candidatas; os seguintes pedem cada uma pelo id', async () => {
    AutomacoesAPI.testarPasso
      .mockResolvedValueOnce(primeira(BRUNO, [7, 8]))
      .mockResolvedValueOnce(seguinte(CARLA));
    const wrapper = montar({ mostraCusto: true });

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.testarPasso.mock.calls.map(([a]) => a)).toEqual([
      {
        receita: RECEITA,
        passoId: 'p1',
        conversaId: undefined,
        automacaoId: null,
      },
      { receita: RECEITA, passoId: 'p1', conversaId: 8, automacaoId: null },
    ]);
    const linhas = wrapper.findAll('[data-teste-resultado]');
    expect(linhas.map(linha => linha.text())).toEqual([
      'AUTOMACAO_LIVRE.IA.TESTAR.ESCOLHEU(Sinistro)',
      'AUTOMACAO_LIVRE.IA.TESTAR.NENHUM',
    ]);
    expect(wrapper.find('[data-teste-custo]').text()).toContain('0,0031');
  });

  it('a mesma conversa nunca aparece duas vezes', async () => {
    AutomacoesAPI.testarPasso
      .mockResolvedValueOnce(primeira(BRUNO, [7, 8, 9]))
      .mockResolvedValueOnce(seguinte(BRUNO))
      .mockResolvedValueOnce(seguinte(CARLA));
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(wrapper.findAll('[data-teste-conversa]')).toHaveLength(2);
  });

  it('trocar de passo no meio do teste para o teste antigo', async () => {
    let soltar;
    AutomacoesAPI.testarPasso.mockReturnValueOnce(
      new Promise(resolve => {
        soltar = resolve;
      })
    );
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await wrapper.setProps({ passo: { ...DECIDIR, id: 'p2' } });
    soltar(primeira(BRUNO, [7, 8]));
    await flushPromises();

    expect(AutomacoesAPI.testarPasso).toHaveBeenCalledTimes(1);
    expect(wrapper.findAll('[data-teste-conversa]')).toHaveLength(0);
    expect(
      wrapper.find('[data-testar]').attributes('disabled')
    ).toBeUndefined();
  });

  it('trava o botão enquanto o teste roda', async () => {
    let soltar;
    AutomacoesAPI.testarPasso.mockReturnValue(
      new Promise(resolve => {
        soltar = resolve;
      })
    );
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    expect(wrapper.find('[data-testar]').attributes('disabled')).toBeDefined();

    soltar(primeira(BRUNO, [7]));
    await flushPromises();
    expect(
      wrapper.find('[data-testar]').attributes('disabled')
    ).toBeUndefined();
  });

  it('o texto da IA sai como texto, nunca como HTML', async () => {
    AutomacoesAPI.testarPasso.mockResolvedValue({
      data: {
        candidatas: [7],
        aviso: null,
        conversa: {
          conversa_id: 7,
          nome: 'Bruno',
          resultado: { texto: '<img src=x onerror="alert(1)">' },
        },
      },
    });
    const wrapper = montar({ passo: { id: 'p1', tipo: 'escrever' } });

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('[data-teste-resultado]').text()).toBe(
      '<img src=x onerror="alert(1)">'
    );
  });

  it('sem financial_view, não mostra custo nenhum', async () => {
    AutomacoesAPI.testarPasso.mockResolvedValue({
      data: {
        candidatas: [7],
        aviso: 'nenhuma_entraria',
        conversa: { conversa_id: 7, resultado: { caminho: 'sinistro' } },
      },
    });
    const wrapper = montar({ custo: { media: 0.002, vezes: 3 } });

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-ia-custo]').exists()).toBe(false);
    expect(wrapper.find('[data-teste-custo]').exists()).toBe(false);
    expect(wrapper.find('[data-teste-aviso]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.TESTAR.AVISO.NENHUMA_ENTRARIA'
    );
  });

  it('com financial_view, mostra a média do passo ou que ainda não rodou', () => {
    expect(
      montar({ mostraCusto: true, custo: { media: 0.002, vezes: 3 } })
        .find('[data-ia-custo]')
        .text()
    ).toContain('0,002');
    expect(montar({ mostraCusto: true }).find('[data-ia-custo]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.CUSTO.PRIMEIRA'
    );
  });

  it('#2414 G20: o anexo que não pôde ir à IA usa a frase do ensaio', async () => {
    AutomacoesAPI.testarPasso.mockResolvedValueOnce({
      data: {
        candidatas: [7],
        aviso: null,
        conversa: { conversa_id: 7, motivo: 'anexo_fora_do_formato' },
      },
    });
    const wrapper = montar();
    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-teste-resultado]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.ANEXOS.ANEXO_FORA_DO_FORMATO'
    );
  });

  it('a falha de uma conversa vira frase; a recusa da API mostra o erro', async () => {
    AutomacoesAPI.testarPasso.mockResolvedValueOnce({
      data: {
        candidatas: [7],
        aviso: null,
        conversa: { conversa_id: 7, motivo: 'ia_indisponivel' },
      },
    });
    const wrapper = montar();
    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-teste-resultado]').text()).toBe(
      'AUTOMACAO_LIVRE.IA.TESTAR.MOTIVOS.IA_INDISPONIVEL'
    );

    AutomacoesAPI.testarPasso.mockRejectedValueOnce({
      response: {
        status: 422,
        data: { error: 'Corrija antes.', problemas: ['Falta o caminho.'] },
      },
    });
    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-teste-erro]').text()).toBe(
      'Corrija antes. Falta o caminho.'
    );
  });

  it('extrair, passo incompleto ou quem não monta: sem o botão de testar', () => {
    expect(
      montar({ passo: { id: 'p1', tipo: 'extrair' } })
        .find('[data-testar]')
        .exists()
    ).toBe(false);
    expect(
      montar({ pronto: false }).find('[data-testar]').attributes('disabled')
    ).toBeDefined();
    podeMudar.value = false;
    expect(montar().find('[data-testar]').exists()).toBe(false);
  });
});
