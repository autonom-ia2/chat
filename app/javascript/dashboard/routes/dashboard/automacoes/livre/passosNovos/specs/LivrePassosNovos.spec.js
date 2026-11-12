import { flushPromises, mount } from '@vue/test-utils';
import LivrePassoNovo from '../LivrePassoNovo.vue';
import LivreRepetir from '../LivreRepetir.vue';
import LivreBloco from '../LivreBloco.vue';
import LivreConsulta from '../LivreConsulta.vue';
import LivreReuniao from '../LivreReuniao.vue';
import LivrePesquisa from '../LivrePesquisa.vue';
import LivreAprovacao from '../LivreAprovacao.vue';
import LivrePedidoAprovacao from '../LivrePedidoAprovacao.vue';
import LivreSeletorPasso from '../../components/LivreSeletorPasso.vue';
import { PASSOS_NOVOS, comPassosNovos, novoPassoNovo } from '../passosNovos';

// Protótipo #2931–#2936 — as telas dos passos novos: cada uma começa pronta,
// mostra antes de fazer (contagem, teste, prévia da mensagem) e o "Pedir
// aprovação" tem o lado de quem aprova, com Aprovar e Recusar.
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push: vi.fn() }),
}));
const leValor = vi.hoisted(() => ({ sim: true }));
vi.mock('../../usePodeLerValor', async () => {
  const { computed } = await import('vue');
  return { usePodeLerValor: () => computed(() => () => leValor.sim) };
});
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { ref } = await import('vue');
    return { useCrmPermissions: () => ({ canManagePipelines: ref(true) }) };
  }
);

const ChoiceFalso = {
  name: 'ChoiceSelect',
  props: ['modelValue', 'options', 'groups', 'ariaLabel', 'placeholder'],
  emits: ['update:modelValue'],
  template: '<div />',
};
const DialogFalso = {
  name: 'Dialog',
  methods: { open() {}, close() {} },
  template: '<div><slot /><slot name="footer" /></div>',
};
const stubs = {
  ChoiceSelect: ChoiceFalso,
  Dialog: DialogFalso,
  CrmKanbanCard: {
    name: 'CrmKanbanCard',
    props: ['card', 'comValor'],
    template: '<div data-card />',
  },
  LivreTexto: { name: 'LivreTexto', template: '<div data-texto />' },
  LivreDuracao: { name: 'LivreDuracao', template: '<div data-duracao />' },
  LivreModelo: {
    name: 'LivreModelo',
    props: ['modelValue'],
    emits: ['update:modelValue'],
    template: '<div data-modelo />',
  },
};
const OPCOES = {
  pessoa: [{ value: 7, label: 'Maria' }],
  time: [{ value: 3, label: 'Vendas' }],
  etiquetaPorNome: [{ value: 'vip', label: 'vip' }],
};
const ETAPAS = [
  { label: 'Vendas', options: [{ value: 12, label: 'Proposta' }] },
];
const CATALOGO = { unidades: [], valores: [] };

const montar = (componente, props) =>
  mount(componente, { props, global: { stubs, mocks: { $t: t } } });
const ultimo = tela => tela.emitted('update:modelValue').at(-1)[0];
const escolha = (tela, seletor) =>
  tela.find(seletor).findComponent(ChoiceFalso);
const novo = tipo => novoPassoNovo(tipo, 'p9', t);

describe('LivrePassoNovo', () => {
  it.each(Object.keys(PASSOS_NOVOS))(
    '%s: mostra o formulário, o aviso de teste e a prévia',
    tipo => {
      const tela = montar(LivrePassoNovo, {
        modelValue: novo(tipo),
        catalogo: CATALOGO,
        opcoes: OPCOES,
        atributosDo: () => [],
        etapas: ETAPAS,
      });

      expect(tela.find(`[data-passo-novo="${tipo}"]`).exists()).toBe(true);
      expect(tela.find('[data-em-teste]').exists()).toBe(true);
      expect(tela.find('[data-previa-ensaio]').text()).not.toBe('');
      expect(tela.find('[data-previa-historico]').text()).not.toBe('');
    }
  );
});

describe('Veja como fica', () => {
  it('reunião e pesquisa dizem o que sai com a janela de 24 h fechada', () => {
    ['marcar_reuniao', 'pesquisa_nota'].forEach(tipo => {
      const tela = montar(LivrePassoNovo, {
        modelValue: novo(tipo),
        catalogo: CATALOGO,
        opcoes: OPCOES,
        atributosDo: () => [],
        etapas: ETAPAS,
      });

      expect(tela.find('[data-previa-aviso]').text()).toContain(
        'SEM_MODELO_FORA_DA_JANELA'
      );
    });
  });

  it('a busca do ensaio só acontece depois do OK de quem ensaia', async () => {
    const tela = montar(LivrePassoNovo, {
      modelValue: {
        ...novo('consultar'),
        fonte: { de: 'integracao', id: 'loja' },
        guardar: [{ nome: 'Status do pedido', caminho: 'pedido.status' }],
      },
      catalogo: CATALOGO,
      opcoes: OPCOES,
      atributosDo: () => [],
      etapas: ETAPAS,
    });

    expect(tela.find('[data-busca-resultado]').exists()).toBe(false);
    await tela.find('[data-busca-pedir]').trigger('click');
    expect(tela.find('[data-busca-confirmar]').text()).toContain(
      'CONSULTAR.CONFIRMAR_BUSCA'
    );
    await tela.find('[data-busca-sim]').trigger('click');
    await flushPromises();

    const resultado = tela.find('[data-busca-resultado]').text();
    expect(resultado).toContain('Status do pedido');
    expect(resultado).toContain('EXEMPLO.STATUS_ENVIADO');
  });
});

describe('LivreSeletorPasso com os passos novos', () => {
  it('cada passo novo mostra o nome e o que faz em uma frase', () => {
    const tela = mount(LivreSeletorPasso, {
      props: {
        catalogo: comPassosNovos(
          {
            grupos: [{ chave: 'EQUIPE', frase: 'G.EQUIPE' }],
            passos: [],
          },
          true
        ),
        liberado: () => true,
      },
      global: {
        mocks: { $t: t },
        stubs: { SidePanel: { template: '<div><slot /></div>' } },
      },
    });

    const botao = tela.find('[data-tipo="pedir_aprovacao"]');
    expect(botao.text()).toContain('APROVACAO.NOME');
    expect(botao.find('[data-dica]').text()).toContain('APROVACAO.DICA');
  });
});

describe('LivreRepetir', () => {
  it('começa com a primeira etapa escolhida', () => {
    const tela = montar(LivreRepetir, {
      modelValue: novo('repetir_lista'),
      opcoes: OPCOES,
      etapas: ETAPAS,
    });

    expect(ultimo(tela).lista).toEqual({ de: 'etapa', etapa_id: 12 });
  });

  it('trocar para etiqueta já escolhe a primeira etiqueta', async () => {
    const tela = montar(LivreRepetir, {
      modelValue: {
        ...novo('repetir_lista'),
        lista: { de: 'etapa', etapa_id: 12 },
      },
      opcoes: OPCOES,
      etapas: ETAPAS,
    });

    await escolha(tela, '[data-repetir-de]').vm.$emit(
      'update:modelValue',
      'etiqueta'
    );

    expect(ultimo(tela).lista).toEqual({ de: 'etiqueta', etiqueta: 'vip' });
  });

  it('a lista pode vir de um público, que já vem escolhido', async () => {
    const tela = montar(LivreRepetir, {
      modelValue: {
        ...novo('repetir_lista'),
        lista: { de: 'etapa', etapa_id: 12 },
      },
      opcoes: OPCOES,
      etapas: ETAPAS,
    });

    expect(
      escolha(tela, '[data-repetir-de]')
        .props('options')
        .map(o => o.value)
    ).toEqual(['etapa', 'etiqueta', 'publico']);
    await escolha(tela, '[data-repetir-de]').vm.$emit(
      'update:modelValue',
      'publico'
    );

    expect(ultimo(tela).lista).toEqual({ de: 'publico', publico_id: 1 });
  });

  it('diz quantos entrariam hoje e mostra os 3 primeiros', () => {
    const tela = montar(LivreRepetir, {
      modelValue: {
        ...novo('repetir_lista'),
        lista: { de: 'etapa', etapa_id: 12 },
      },
      opcoes: OPCOES,
      etapas: ETAPAS,
    });
    const contagem = tela.find('[data-repetir-contagem]');

    expect(contagem.text()).toContain('12');
    expect(contagem.findAll('li')).toHaveLength(3);
  });

  it('teto fora de 1 a 200 avisa', () => {
    const tela = montar(LivreRepetir, {
      modelValue: {
        ...novo('repetir_lista'),
        lista: { de: 'etapa', etapa_id: 12 },
        teto: 0,
      },
      opcoes: OPCOES,
      etapas: ETAPAS,
    });

    expect(tela.text()).toContain('REPETIR.TETO_FORA');
  });
});

describe('LivreBloco', () => {
  it('começa com o primeiro bloco e troca pelo toque', async () => {
    const tela = montar(LivreBloco, { modelValue: novo('usar_bloco') });

    expect(ultimo(tela).bloco_id).toBe(1);
    await tela.find('[data-bloco="2"]').trigger('click');
    expect(ultimo(tela).bloco_id).toBe(2);
  });

  it('o bloco escolhido mostra os passos de dentro', () => {
    const tela = montar(LivreBloco, {
      modelValue: { ...novo('usar_bloco'), bloco_id: 1 },
    });

    expect(tela.find('[data-bloco="1"]').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(tela.findAll('[data-bloco-dentro] li')).toHaveLength(3);
  });
});

describe('LivreConsulta', () => {
  it('começa com a primeira integração conectada', () => {
    const tela = montar(LivreConsulta, { modelValue: novo('consultar') });

    expect(ultimo(tela).fonte).toEqual({ de: 'integracao', id: 'loja' });
  });

  it('o teste mostra os dados e o toque guarda o escolhido', async () => {
    const tela = montar(LivreConsulta, {
      modelValue: {
        ...novo('consultar'),
        fonte: { de: 'integracao', id: 'loja' },
      },
    });

    await tela.find('[data-consulta-testar]').trigger('click');
    await flushPromises();
    await tela.find('[data-consulta-dado="pedido.status"]').trigger('click');

    expect(ultimo(tela).guardar).toEqual([
      {
        nome: 'AUTOMACAO_LIVRE.PASSOS_NOVOS.EXEMPLO.DADOS.STATUS_DO_PEDIDO',
        caminho: 'pedido.status',
      },
    ]);
  });

  it('endereço sem https avisa e não deixa testar', () => {
    const tela = montar(LivreConsulta, {
      modelValue: {
        ...novo('consultar'),
        fonte: { de: 'endereco', url: 'http://x' },
      },
    });

    expect(tela.text()).toContain('CONSULTAR.ENDERECO_RUIM');
    expect(
      tela.find('[data-consulta-testar]').attributes('disabled')
    ).toBeDefined();
  });
});

describe('LivreReuniao', () => {
  it('a prévia mostra os 3 horários, e a agenda é de uma pessoa', () => {
    const tela = montar(LivreReuniao, {
      modelValue: novo('marcar_reuniao'),
      catalogo: CATALOGO,
      opcoes: OPCOES,
      atributosDo: () => [],
    });

    expect(tela.findAll('[data-reuniao-previa] li')).toHaveLength(3);
    expect(
      escolha(tela, '[data-quem-de]')
        .props('options')
        .map(o => o.value)
    ).toEqual(['responsavel', 'pessoa']);
  });

  it('escolhe o que sai com a janela de 24 h fechada', async () => {
    const tela = montar(LivreReuniao, {
      modelValue: novo('marcar_reuniao'),
      catalogo: CATALOGO,
      opcoes: OPCOES,
      atributosDo: () => [],
    });
    const modelo = { nome: 'lembrete', idioma: 'pt_BR', variaveis: [] };

    await tela
      .findComponent({ name: 'LivreModelo' })
      .vm.$emit('update:modelValue', modelo);

    expect(ultimo(tela).modelo).toEqual(modelo);
  });
});

describe('LivrePesquisa', () => {
  it('a prévia tem os botões de 0 a 10 e a escolha da janela de 24 h', () => {
    const tela = montar(LivrePesquisa, {
      modelValue: novo('pesquisa_nota'),
      catalogo: CATALOGO,
      atributosDo: () => [],
    });

    expect(tela.findAll('[data-pesquisa-previa] li')).toHaveLength(11);
    expect(tela.find('[data-pesquisa-media]').text()).toContain('7,8');
    expect(tela.find('[data-modelo]').exists()).toBe(true);
  });

  it('faixa do meio vazia avisa', () => {
    const tela = montar(LivrePesquisa, {
      modelValue: { ...novo('pesquisa_nota'), baixa_ate: 7, alta_desde: 8 },
      catalogo: CATALOGO,
      atributosDo: () => [],
    });

    expect(tela.find('[data-pesquisa-faixas-ruins]').exists()).toBe(true);
    expect(tela.find('[data-pesquisa-media]').exists()).toBe(false);
  });
});

describe('Pedir aprovação: o lado de quem aprova', () => {
  const PASSO = {
    ...novo('pedir_aprovacao'),
    pergunta: ['Posso dar o desconto de ', { $valor: 'card.valor' }, '?'],
  };
  const montarPedido = () =>
    montar(LivrePedidoAprovacao, { passo: PASSO, catalogo: CATALOGO });

  beforeEach(() => {
    leValor.sim = true;
  });

  it('a pergunta sai com o valor de exemplo, oculto para quem não vê valores', () => {
    expect(montarPedido().find('[data-pedido-pergunta]').text()).toBe(
      'Posso dar o desconto de R$ 4.800,00?'
    );
    leValor.sim = false;
    expect(montarPedido().find('[data-pedido-pergunta]').text()).toContain(
      'EXEMPLO.VALOR_OCULTO'
    );
  });

  it('aprovar mostra que a automação seguiu', async () => {
    const tela = montarPedido();

    await tela.find('[data-pedido-aprovar]').trigger('click');

    expect(tela.find('[data-pedido-feito]').text()).toContain(
      'PEDIDO.APROVADO'
    );
  });

  it('recusar pede o motivo, que é opcional', async () => {
    const tela = montarPedido();

    await tela.find('[data-pedido-recusar]').trigger('click');
    await tela
      .find('[data-pedido-motivo] textarea')
      .setValue('Passou do combinado');
    await tela.find('[data-pedido-confirmar-recusa]').trigger('click');

    const feito = tela.find('[data-pedido-feito]').text();
    expect(feito).toContain('PEDIDO.RECUSADO');
    expect(feito).toContain('Passou do combinado');
  });

  it('o botão do formulário abre o pedido', async () => {
    const abrir = vi.fn();
    const tela = mount(LivreAprovacao, {
      props: {
        modelValue: PASSO,
        catalogo: CATALOGO,
        opcoes: OPCOES,
        atributosDo: () => [],
      },
      global: {
        stubs: {
          ...stubs,
          LivrePedidoAprovacao: {
            name: 'LivrePedidoAprovacao',
            methods: { abrir },
            template: '<div />',
          },
        },
        mocks: { $t: t },
      },
    });

    await tela.find('[data-ver-pedido]').trigger('click');

    expect(abrir).toHaveBeenCalled();
  });
});
