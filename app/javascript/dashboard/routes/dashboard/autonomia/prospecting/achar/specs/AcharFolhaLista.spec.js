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

  it('ao abrir a folha, as listas chegam pela fonte', async () => {
    const fonte = { listas: vi.fn().mockResolvedValue(LISTAS) };
    const { folha } = montarComposable(fonte);

    folha.value = folhaNova('lista');
    await flushPromises();

    expect(fonte.listas).toHaveBeenCalledTimes(1);
    expect(folha.value.listas).toEqual(LISTAS);
    expect(folha.value.listaId).toBe(LISTA_NOVA);
  });

  it('guardar numa lista que já existe usa acrescentarNaLista e o pronto leva o nome dela', async () => {
    const fonte = {
      listas: vi.fn().mockResolvedValue(LISTAS),
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
      listas: vi.fn().mockResolvedValue(LISTAS),
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
});
