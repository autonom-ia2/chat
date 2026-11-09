import { nextTick, ref } from 'vue';
import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AcharFolhaEnvio from '../components/AcharFolhaEnvio.vue';
import {
  LISTA_NOVA,
  folhaNova,
  useFolhaDaLista,
} from '../composables/useFolhaDaLista';
import { TEXTO_DO_ERRO } from '../composables/useDonoDaLista';
import { foraDoPublico } from '../utils/acharConfiraEstados';
import { MAX_PAGINAS_DE_LISTAS } from '../utils/listasDaFolha';

const pagina = n =>
  Array.from({ length: 25 }, (_, i) => ({ id: n * 100 + i, nome: `L${i}` }));

// #2775 — F6, "Para qual lista?" no Guardar lista: "Lista nova" ou uma que já
// existe, com os números; a já enviada fica desligada. Numa lista que já
// existe as empresas entram nela (acrescentarNaLista), e o pronto diz o nome
// dela.
config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];
Element.prototype.scrollIntoView = () => {};

const LISTAS = [
  {
    id: 4,
    nome: 'Padarias',
    empresas: 12,
    whatsapp: 9,
    email: 5,
    enviada: false,
  },
  { id: 5, nome: 'Antiga', empresas: 8, whatsapp: 6, email: 2, enviada: true },
];

const montarFolha = props =>
  mount(AcharFolhaEnvio, {
    attachTo: document.body,
    props: {
      n: 3,
      podeLista: true,
      pessoa: 'Você',
      entramLista: 3,
      nomeLista: 'padarias · Centro · 09/11',
      listas: LISTAS,
      ...props,
    },
  });

const montarComposable = fonte => {
  const folha = ref(null);
  const pronto = ref(null);
  const acoes = useFolhaDaLista({
    demo: ref(null),
    estado: ref(''),
    fonte: ref(fonte),
    mudarEstado: vi.fn(),
    contaId: ref(1),
    usuarioId: ref(7),
    escolhidas: ref([
      { id: 1, temContato: true },
      { id: 2, temContato: true },
    ]),
    destino: ref(null),
    pessoaId: ref('voce'),
    pessoaNome: ref('Você'),
    donoId: ref(null),
    nomeLista: ref('Nome sugerido'),
    folha,
    pronto,
    subpainel: ref(null),
    trocar: vi.fn(),
  });
  return { folha, pronto, acoes };
};

describe('Guardar lista: lista nova ou uma que já existe', () => {
  it('a escolha mostra "Lista nova" e as listas com os números; a enviada fica desligada', async () => {
    const wrapper = montarFolha({});
    await wrapper.find('[data-escolha-da-lista] button').trigger('click');
    await nextTick();

    const opcoes = wrapper.findAll('[role="option"]');
    expect(opcoes.map(opcao => opcao.text())).toEqual([
      'Lista nova',
      expect.stringContaining('Padarias'),
      expect.stringContaining('Antiga'),
    ]);
    expect(opcoes[1].text()).toContain(
      '12 empresas · 9 com WhatsApp · 5 com e-mail'
    );
    expect(opcoes[2].attributes('aria-disabled')).toBe('true');
    expect(opcoes[2].text()).toContain('Já enviada');
    expect(wrapper.find('select').exists()).toBe(false);
    wrapper.unmount();
  });

  it('com uma lista que já existe, o nome some e o botão diz "Pôr"', () => {
    const wrapper = montarFolha({ listaId: 4 });

    expect(wrapper.find('[data-lista-escolhida]').text()).toContain(
      'Quem já está na lista não entra de novo'
    );
    expect(wrapper.find('[data-principal-folha]').text()).toBe(
      'Pôr 3 empresas na lista'
    );
    wrapper.unmount();
  });

  it('ao abrir a folha, as listas chegam pela fonte, com quantas das escolhidas entram', async () => {
    const fonte = {
      listas: vi.fn().mockResolvedValue({
        listas: [{ ...LISTAS[0], jaNaLista: [2] }, LISTAS[1]],
        temMais: false,
      }),
    };
    const { folha } = montarComposable(fonte);

    folha.value = folhaNova('lista');
    await flushPromises();

    expect(fonte.listas).toHaveBeenCalledTimes(1);
    expect(fonte.listas).toHaveBeenCalledWith({
      depois: null,
      empresaIds: [1, 2],
    });
    expect(folha.value.listas.map(lista => [lista.id, lista.entram])).toEqual([
      [4, 1],
      [5, 2],
    ]);
    expect(folha.value.listaId).toBe(LISTA_NOVA);
  });

  // Revisão do #2775, item 1: quem tem mais de 25 listas acha todas.
  it('lê todas as páginas de listas, pelo cursor, até o servidor dizer que acabou', async () => {
    const cursor = { em: '2026-11-09T10:00:00.000001Z', id: 124 };
    const fonte = {
      listas: vi
        .fn()
        .mockResolvedValueOnce({
          listas: pagina(1),
          temMais: true,
          depois: cursor,
        })
        .mockResolvedValueOnce({
          listas: [{ id: 999, nome: 'A 26ª' }],
          temMais: false,
          depois: null,
        }),
    };
    const { folha } = montarComposable(fonte);

    folha.value = folhaNova('lista');
    await flushPromises();

    expect(fonte.listas).toHaveBeenCalledTimes(2);
    expect(fonte.listas).toHaveBeenLastCalledWith({
      depois: cursor,
      empresaIds: [1, 2],
    });
    expect(folha.value.listas).toHaveLength(26);
    expect(folha.value.listas.at(-1)).toMatchObject({ id: 999, entram: 2 });
    expect(folha.value.listasIncompletas).toBe(false);
  });

  // Revisão do #2775, rodada 2, item 2: página que falha no meio.
  it('uma página que falha no meio guarda as que vieram e avisa que nem todas apareceram', async () => {
    const fonte = {
      listas: vi
        .fn()
        .mockResolvedValueOnce({
          listas: pagina(1),
          temMais: true,
          depois: { em: 'x', id: 1 },
        })
        .mockRejectedValueOnce(new Error('rede')),
    };
    const { folha } = montarComposable(fonte);

    folha.value = folhaNova('lista');
    await flushPromises();

    expect(folha.value.listas).toHaveLength(25);
    expect(folha.value.listasIncompletas).toBe(true);

    const wrapper = montarFolha({ listasIncompletas: true });
    expect(wrapper.find('[data-listas-incompletas]').text()).toBe(
      'Nem todas as suas listas apareceram. Feche e abra de novo para ver as outras.'
    );
    wrapper.unmount();
  });

  it('passar do teto de páginas guarda as que vieram e avisa', async () => {
    const fonte = {
      listas: vi.fn(async ({ depois }) => ({
        listas: [{ id: (depois?.id || 0) + 1, nome: 'L' }],
        temMais: true,
        depois: { em: 'x', id: (depois?.id || 0) + 1 },
      })),
    };
    const { folha } = montarComposable(fonte);

    folha.value = folhaNova('lista');
    await flushPromises();

    expect(fonte.listas).toHaveBeenCalledTimes(MAX_PAGINAS_DE_LISTAS);
    expect(folha.value.listas).toHaveLength(MAX_PAGINAS_DE_LISTAS);
    expect(folha.value.listasIncompletas).toBe(true);
  });

  // Revisão do #2775, item 8: singular e plural, e o n só de quem entra.
  it('o botão conta só quem entra, no singular e no plural', () => {
    const uma = montarFolha({
      listaId: 4,
      listas: [{ ...LISTAS[0], empresas: 1, entram: 1 }, LISTAS[1]],
    });
    expect(uma.find('[data-principal-folha]').text()).toBe(
      'Pôr 1 empresa na lista'
    );
    expect(uma.find('[data-lista-escolhida]').text()).toContain(
      '1 empresa · 9 com WhatsApp'
    );
    uma.unmount();

    const duas = montarFolha({
      listaId: 4,
      listas: [{ ...LISTAS[0], entram: 2 }, LISTAS[1]],
    });
    expect(duas.find('[data-principal-folha]').text()).toBe(
      'Pôr 2 empresas na lista'
    );
    duas.unmount();

    const nenhuma = montarFolha({
      listaId: 4,
      listas: [{ ...LISTAS[0], entram: 0 }, LISTAS[1]],
    });
    const botao = nenhuma.find('[data-principal-folha]');
    expect(botao.text()).toBe('Essas empresas já estão nesta lista');
    expect(botao.attributes('disabled')).toBeDefined();
    nenhuma.unmount();
  });

  it('todas já estavam na lista (servidor): a frase própria', async () => {
    const fonte = {
      listas: vi.fn().mockResolvedValue({ listas: LISTAS, temMais: false }),
      acrescentarNaLista: vi.fn().mockRejectedValue(
        Object.assign(new Error('x'), {
          codigo: 'prospecting.audience.all_already_in_list',
          fora: [{ id: 1, motivo: 'already_in_list' }],
        })
      ),
    };
    const { folha, acoes } = montarComposable(fonte);
    folha.value = { ...folhaNova('lista'), listaId: 4 };
    await flushPromises();

    await acoes.guardarDaFolha();

    expect(folha.value.erro).toBe('lista_ja_estavam');
    expect(TEXTO_DO_ERRO.lista_ja_estavam).toBe(
      'PROSPECTING_ACHAR.FOLHA.ERRO_LISTA_JA_ESTAVAM'
    );
  });

  it('guardar numa lista que já existe usa acrescentarNaLista e o pronto leva o nome dela', async () => {
    const fonte = {
      listas: vi.fn().mockResolvedValue({ listas: LISTAS, temMais: false }),
      guardarLista: vi.fn(),
      acrescentarNaLista: vi.fn().mockResolvedValue({
        publicoId: 4,
        nome: 'Padarias',
        n: 1,
        lista: LISTAS[0],
        fora: [{ id: 2, motivo: 'already_in_list' }],
      }),
    };
    const { folha, pronto, acoes } = montarComposable(fonte);
    folha.value = { ...folhaNova('lista'), listaId: 4 };
    await flushPromises();

    await acoes.guardarDaFolha();

    expect(fonte.guardarLista).not.toHaveBeenCalled();
    expect(fonte.acrescentarNaLista).toHaveBeenCalledWith({
      listaId: 4,
      ids: [1, 2],
    });
    expect(pronto.value).toMatchObject({
      tipo: 'lista',
      n: 1,
      publicoId: 4,
      nome: 'Padarias',
    });
  });

  it('lista que passou a ser enviada no meio do caminho: a frase própria', async () => {
    const fonte = {
      listas: vi.fn().mockResolvedValue({ listas: LISTAS, temMais: false }),
      acrescentarNaLista: vi.fn().mockRejectedValue(
        Object.assign(new Error('x'), {
          codigo: 'prospecting.audience.audience_locked',
          fora: [],
        })
      ),
    };
    const { folha, acoes } = montarComposable(fonte);
    folha.value = { ...folhaNova('lista'), listaId: 4 };
    await flushPromises();

    await acoes.guardarDaFolha();

    expect(folha.value.erro).toBe('lista_enviada');
  });

  // #2775, item 16: bloqueado (#2733) e motivo novo da régua têm frase própria.
  it('quem ficou de fora por bloqueio ou por não poder receber ganha a frase certa', () => {
    const t = (chave, _named, n) => `${chave}:${n}`;

    expect(
      foraDoPublico(t, [
        { id: 1, motivo: 'blocked' },
        { id: 2, motivo: 'unreachable' },
        { id: 3, motivo: 'unreachable' },
      ])
    ).toEqual([
      'PROSPECTING_ACHAR.PRONTO.LISTA.FORA.BLOQUEADO:1',
      'PROSPECTING_ACHAR.PRONTO.LISTA.FORA.NAO_RECEBE:2',
    ]);
    expect(ptBR.PROSPECTING_ACHAR.PRONTO.LISTA.FORA.NAO_RECEBE).toContain(
      'não pode receber mensagem'
    );
  });
});
