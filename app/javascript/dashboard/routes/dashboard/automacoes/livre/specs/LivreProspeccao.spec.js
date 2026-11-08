import { flushPromises, mount } from '@vue/test-utils';
import LivreProspeccao from '../components/LivreProspeccao.vue';
import {
  MAXIMO_DE_EMPRESAS,
  comFaz,
  fraseDaProspeccao,
  prospeccaoPronta,
} from '../prospeccao';
import { fraseDoPasso } from '../frases';
import { novoPasso } from '../catalogo';
import catalogoGerado from '../../../../../../../../lib/operator_guide/automacao-passos.json';

// #2414 G21 (#2706) — o passo "prospecção" no editor: buscar empresas numa
// busca do histórico da Prospecção (só no recorrente) ou marcar a recusa do
// lead. O "Salvar" só libera com a busca completa, e a troca entre as duas
// não leva campo que sobra.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const getSearches = vi.fn();
const getSearch = vi.fn();
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSearches: (...args) => getSearches(...args),
    getSearch: (...args) => getSearch(...args),
  },
}));

const BUSCAS = [
  {
    id: 11,
    query: 'escritório de contabilidade',
    location: 'Campinas, SP',
    status: 'completed',
    created_at: '2026-11-02T11:00:00Z',
  },
  {
    id: 12,
    query: 'padaria',
    location: 'Campinas, SP',
    status: 'failed',
    created_at: '2026-11-03T11:00:00Z',
  },
];

const PRONTA = {
  id: 'p1',
  tipo: 'prospeccao',
  faz: 'buscar',
  busca_id: 11,
  quantas: 20,
  etapa_id: 5,
  etiquetas: [7],
};

const t = (chave, valores) =>
  valores ? `${chave} ${JSON.stringify(valores)}` : chave;

describe('prospeccao.js', () => {
  it('buscar só fica pronto com busca, quantas de 1 a 60 e etapa', () => {
    expect(prospeccaoPronta(PRONTA)).toBe(true);
    expect(prospeccaoPronta({ ...PRONTA, busca_id: undefined })).toBe(false);
    expect(prospeccaoPronta({ ...PRONTA, etapa_id: null })).toBe(false);
    expect(prospeccaoPronta({ ...PRONTA, quantas: 0 })).toBe(false);
    expect(
      prospeccaoPronta({ ...PRONTA, quantas: MAXIMO_DE_EMPRESAS + 1 })
    ).toBe(false);
  });

  it('recusar está sempre pronto', () => {
    expect(prospeccaoPronta({ id: 'r1', faz: 'recusar' })).toBe(true);
  });

  it('trocar para recusar não leva os campos da busca', () => {
    expect(comFaz(PRONTA, 'recusar')).toEqual({
      id: 'p1',
      tipo: 'prospeccao',
      faz: 'recusar',
    });
  });

  it('trocar para buscar nasce com 20 empresas e sem etiqueta', () => {
    expect(
      comFaz({ id: 'p1', tipo: 'prospeccao', faz: 'recusar' }, 'buscar')
    ).toEqual({
      id: 'p1',
      tipo: 'prospeccao',
      faz: 'buscar',
      quantas: 20,
      etiquetas: [],
    });
  });

  it('a frase da linha diz quantas empresas', () => {
    expect(fraseDaProspeccao(PRONTA, t)).toBe(
      'AUTOMACAO_LIVRE.PROSPECCAO.FRASE_BUSCAR {"quantas":20}'
    );
    expect(fraseDoPasso(PRONTA, catalogoGerado, t)).toBe(
      fraseDaProspeccao(PRONTA, t)
    );
  });

  it('o passo novo nasce no recusar, que vale em qualquer gatilho', () => {
    expect(novoPasso({ tipo: 'prospeccao' }, 'p9', t)).toEqual({
      id: 'p9',
      tipo: 'prospeccao',
      faz: 'recusar',
    });
  });
});

describe('LivreProspeccao', () => {
  beforeEach(() => {
    getSearches.mockReset();
    getSearches.mockResolvedValue({ data: { payload: BUSCAS } });
    getSearch.mockReset();
    getSearch.mockRejectedValue(new Error('404'));
  });

  const montar = modelValue =>
    mount(LivreProspeccao, {
      props: {
        modelValue,
        etiquetas: [{ value: 7, label: 'prospeccao-novembro' }],
        etapas: [
          { label: 'Prospecção', options: [{ value: 5, label: 'Novos' }] },
        ],
      },
    });

  const escolha = (tela, marca) =>
    tela
      .findAllComponents({ name: 'ChoiceSelect' })
      .find(item => item.attributes(marca) !== undefined);

  it('recusar mostra só a explicação, sem os campos da busca', () => {
    const tela = montar({ id: 'r1', tipo: 'prospeccao', faz: 'recusar' });

    expect(tela.text()).toContain('AUTOMACAO_LIVRE.PROSPECCAO.RECUSAR_DICA');
    expect(tela.find('[data-prospeccao-quantas]').exists()).toBe(false);
    expect(getSearches).not.toHaveBeenCalled();
  });

  it('buscar avisa que só vale no recorrente e lista só as buscas concluídas', async () => {
    const tela = montar(PRONTA);
    await flushPromises();

    expect(tela.find('[data-prospeccao-so-recorrente]').exists()).toBe(true);
    expect(getSearches).toHaveBeenCalledWith({ per_page: 50 });
    const opcoes = escolha(tela, 'data-prospeccao-busca').props('options');
    expect(opcoes.map(opcao => opcao.value)).toEqual([11]);
  });

  it('escolher a busca guarda o id e mantém o resto', async () => {
    const tela = montar({ ...PRONTA, busca_id: undefined });
    await flushPromises();

    escolha(tela, 'data-prospeccao-busca').vm.$emit('update:modelValue', 11);

    expect(tela.emitted('update:modelValue').at(-1)).toEqual([
      { ...PRONTA, busca_id: 11 },
    ]);
  });

  it('quantas vira número; apagado fica vazio para o Salvar travar', async () => {
    const tela = montar(PRONTA);
    const quantas = tela.findComponent('[data-prospeccao-quantas]');

    quantas.vm.$emit('update:modelValue', '35');
    expect(tela.emitted('update:modelValue').at(-1)[0].quantas).toBe(35);

    quantas.vm.$emit('update:modelValue', '2.5');
    expect(tela.emitted('update:modelValue').at(-1)[0].quantas).toBe(2.5);

    quantas.vm.$emit('update:modelValue', '');
    expect(tela.emitted('update:modelValue').at(-1)[0].quantas).toBeNull();
  });

  it('busca que saiu do histórico avisa para escolher outra', async () => {
    const tela = montar({ ...PRONTA, busca_id: 99 });
    await flushPromises();

    expect(getSearch).toHaveBeenCalledWith(99);
    expect(tela.find('[data-prospeccao-busca-sumiu]').exists()).toBe(true);
  });

  it('busca salva fora das 50 recentes é lida pelo id e fica na lista', async () => {
    getSearch.mockResolvedValue({
      data: { payload: { ...BUSCAS[0], id: 3, status: 'cached' } },
    });
    const tela = montar({ ...PRONTA, busca_id: 3 });
    await flushPromises();

    const opcoes = escolha(tela, 'data-prospeccao-busca').props('options');
    expect(opcoes.map(opcao => opcao.value)).toEqual([11, 3]);
    expect(tela.find('[data-prospeccao-busca-sumiu]').exists()).toBe(false);
  });

  it('quantas fora de 1 a 60 diz o porquê', () => {
    const tela = montar({ ...PRONTA, quantas: 61 });
    const quantas = tela.findComponent('[data-prospeccao-quantas]');

    expect(quantas.props('messageType')).toBe('error');
    expect(quantas.props('message')).toContain('QUANTAS_FORA');
  });

  it('falha ao carregar as buscas diz o que fazer', async () => {
    getSearches.mockRejectedValue(new Error('rede'));
    const tela = montar(PRONTA);
    await flushPromises();

    expect(tela.find('[data-prospeccao-falhou]').exists()).toBe(true);
  });

  it('nenhum <select> nativo', async () => {
    const tela = montar(PRONTA);
    await flushPromises();

    expect(tela.find('select').exists()).toBe(false);
  });
});
