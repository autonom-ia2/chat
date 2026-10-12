import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createMemoryHistory, createRouter } from 'vue-router';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import pt from 'dashboard/i18n/locale/pt_BR/modelosWhatsapp.json';
import { modeloDaMeta } from '../api/daMeta';
import { lembrarArquivoIgual } from '../helpers/conteudo';
import { corpoParaAlterar } from '../helpers/paraMeta';
import ModeloCriarPage from '../pages/ModeloCriarPage.vue';
import ModeloConferencia from '../components/ModeloConferencia.vue';
import EtapaExtras from '../components/criar/EtapaExtras.vue';

// #1394: a Meta não deixa trocar o tipo de um modelo que já existe. Corrigir e
// alterar mostram o tipo travado, com a saída "crie um modelo novo com este
// texto", que abre o criar já preenchido, com outro nome e o tipo para escolher.
const api = vi.hoisted(() => ({
  listarNumeros: vi.fn(),
  obterCatalogo: vi.fn(),
  listarFormularios: vi.fn(),
  listarModelos: vi.fn(),
  obterModelo: vi.fn(),
  ondeEstaEmUso: vi.fn(),
  custoPorEnvio: vi.fn(),
  alterarModelo: vi.fn(),
  criarModelo: vi.fn(),
}));
vi.mock('../api/modelosWhatsapp', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const GRUPO = { id: 7, conta: { id: 7, nome: 'Hub2you' }, numeros: [7] };
const NUMEROS = [
  {
    id: 7,
    nome: 'Atendimento',
    telefone: '+55 11 4000-0000',
    conta: { id: 7, nome: 'Hub2you' },
    situacao: 'conectada',
  },
];

// O caso real da conta 16: recusado, e a Meta gravou MARKETING.
const RECUSADO = modeloDaMeta(
  {
    id: '1001',
    name: 'cobranca_ou_boleto',
    friendly_name: 'Cobrança ou boleto',
    language: 'pt_BR',
    status: 'REJECTED',
    rejected_reason: 'INVALID_FORMAT',
    category: 'MARKETING',
    components: [
      { type: 'HEADER', format: 'DOCUMENT' },
      {
        type: 'BODY',
        text: 'Olá, {{1}}! O seu boleto vence amanhã. Qualquer dúvida, é só responder.',
        example: { body_text: [['Ana']] },
      },
      {
        type: 'BUTTONS',
        buttons: [{ type: 'QUICK_REPLY', text: 'Já paguei' }],
      },
    ],
    fields: { 1: 'cliente.primeiro_nome' },
    header_media: { handle: '4::velho', file_name: 'boleto.pdf' },
  },
  GRUPO
);

const loja = () =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({
        id: 1,
        accounts: [{ id: 1, role: 'administrator' }],
      }),
      getCurrentAccount: () => ({ id: 1, name: 'Hub2you' }),
      'accounts/getAccount': () => () => ({ id: 1, name: 'Hub2you' }),
    },
  });

const vazio = { template: '<div />' };
const roteador = () =>
  createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/modelos', name: 'modelos_whatsapp_lista', component: vazio },
      {
        path: '/modelos/novo',
        name: 'modelos_whatsapp_novo',
        component: ModeloCriarPage,
      },
      {
        path: '/modelos/enviado',
        name: 'modelos_whatsapp_enviado',
        component: vazio,
      },
      {
        path: '/modelos/:id',
        name: 'modelos_whatsapp_modelo',
        component: vazio,
      },
      {
        path: '/modelos/:id/alterar',
        name: 'modelos_whatsapp_alterar',
        component: ModeloCriarPage,
      },
      { path: '/campanha', name: 'campaigns_journey_new', component: vazio },
    ],
  });

const abrir = async caminho => {
  const router = roteador();
  router.push(caminho);
  await router.isReady();
  const wrapper = mount(
    { template: '<router-view />' },
    {
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
          loja(),
          router,
        ],
        stubs: { AgenteGaveta: true, ModeloCelular: true },
      },
    }
  );
  await flushPromises();
  return { wrapper, router };
};

beforeEach(() => {
  Object.values(api).forEach(fn => fn.mockReset());
  api.listarNumeros.mockResolvedValue(NUMEROS);
  api.obterCatalogo.mockResolvedValue(null);
  api.listarFormularios.mockResolvedValue([]);
  api.listarModelos.mockResolvedValue([RECUSADO]);
  api.obterModelo.mockResolvedValue(RECUSADO);
  api.ondeEstaEmUso.mockResolvedValue([]);
  api.custoPorEnvio.mockImplementation(async tipo => ({
    valor: tipo === 'divulgacao' ? 0.4 : 0.05,
    moeda: 'BRL',
  }));
});

describe('Corrigir e alterar: o tipo vem travado (#1394)', () => {
  it('mostra o tipo da Meta com o custo, sem os cartões de escolha', async () => {
    const { wrapper } = await abrir('/modelos/1001/alterar?etapa=texto');

    const travado = wrapper.find('[data-tipo-travado]');
    expect(travado.exists()).toBe(true);
    expect(travado.text()).toContain(
      en.MODELOS_WHATSAPP.TIPOS.divulgacao.ROTULO
    );
    expect(travado.text()).toContain('0.40');
    expect(travado.text()).toContain(
      en.MODELOS_WHATSAPP.TEXTO.TIPO_TRAVADO.NAO_MUDA
    );
    expect(wrapper.find('[data-tipo-do-zero]').exists()).toBe(false);
    expect(wrapper.find('[data-criar-novo-com-texto]').text()).toBe(
      en.MODELOS_WHATSAPP.TEXTO.TIPO_TRAVADO.CRIAR_NOVO
    );
  });

  it('reenviar não manda outro tipo: o rascunho segue com o tipo da Meta', async () => {
    const { wrapper } = await abrir('/modelos/1001/alterar?etapa=confira');
    api.alterarModelo.mockResolvedValue({ ...RECUSADO, id: '1001' });

    await wrapper.find('[data-enviar]').trigger('click');
    await flushPromises();

    expect(api.alterarModelo).toHaveBeenCalledTimes(1);
    const [, rascunho] = api.alterarModelo.mock.calls[0];
    expect(rascunho.tipo).toBe('divulgacao');
    // O corpo que o adaptador manda à Meta com esse rascunho não leva categoria.
    expect(corpoParaAlterar(rascunho, RECUSADO)).not.toHaveProperty('category');
  });

  it('alterar um modelo aprovado também mostra o tipo travado', async () => {
    const aprovado = { ...RECUSADO, situacao: 'pronto', recusa: null };
    api.obterModelo.mockResolvedValue(aprovado);
    api.listarModelos.mockResolvedValue([aprovado]);

    const { wrapper } = await abrir('/modelos/1001/alterar?etapa=texto');

    expect(wrapper.find('[data-aviso-alteracao]').exists()).toBe(true);
    expect(wrapper.find('[data-tipo-travado]').exists()).toBe(true);
    expect(wrapper.find('[data-tipo-do-zero]').exists()).toBe(false);
  });

  it('"crie um modelo novo" abre o criar com o texto, os campos, os exemplos e os botões, outro nome e o tipo para escolher', async () => {
    const { wrapper, router } = await abrir(
      '/modelos/1001/alterar?etapa=texto'
    );

    await router.push(
      wrapper.findComponent('[data-criar-novo-com-texto]').props('to')
    );
    await flushPromises();

    expect(router.currentRoute.value.name).toBe('modelos_whatsapp_novo');
    expect(router.currentRoute.value.query).toMatchObject({
      de: '1001',
      novoTipo: '1',
    });
    // Nome do original já existe na conta: a regra de nome repetido sugere outro.
    expect(wrapper.find('[data-nome] input').element.value).toBe(
      'Cobrança ou boleto 2'
    );
    // O tipo é escolhido de novo, sem nenhum marcado.
    const tipos = wrapper.findAll('[data-tipo-do-zero] [role="radio"]');
    expect(tipos.map(tipo => tipo.attributes('data-tipo'))).toEqual([
      'aviso',
      'divulgacao',
    ]);
    expect(
      tipos.every(tipo => tipo.attributes('aria-checked') === 'false')
    ).toBe(true);
    expect(wrapper.find('[data-tipo-travado]').exists()).toBe(false);
    expect(wrapper.find('[data-exemplo="nome_cliente"]').exists()).toBe(true);
    // Arquivo do topo: a regra de sempre (pede de novo).
    expect(wrapper.find('[data-aviso-copia]').text()).toContain(
      en.MODELOS_WHATSAPP.CRIAR.AVISO_COPIA_ARQUIVOS
    );
    expect(
      wrapper.find('[data-continuar]').attributes('disabled')
    ).toBeDefined();

    await tipos[0].trigger('click');
    expect(
      wrapper.find('[data-continuar]').attributes('disabled')
    ).toBeUndefined();
  });

  it('o criar novo leva os botões do original e pede o arquivo do topo de novo', async () => {
    const { wrapper, router } = await abrir(
      '/modelos/novo?de=1001&novoTipo=1&etapa=texto'
    );
    await wrapper
      .findAll('[data-tipo-do-zero] [role="radio"]')[0]
      .trigger('click');
    await router.push({
      query: { ...router.currentRoute.value.query, etapa: 'extras' },
    });
    await flushPromises();
    const textos = wrapper.findAll('input').map(campo => campo.element.value);
    expect(textos).toContain('Já paguei');
    // O arquivo do original não vem junto: nem o nome dele aparece.
    expect(wrapper.text()).not.toContain('boleto.pdf');

    await router.push({
      query: { ...router.currentRoute.value.query, etapa: 'confira' },
    });
    await flushPromises();

    expect(
      wrapper.find('[data-item="TOPO_ARQUIVO"]').attributes('data-ok')
    ).toBe('false');
    expect(wrapper.find('[data-enviar]').attributes('disabled')).toBeDefined();
  });
});

describe('Topo: o arquivo vai igual para todos (#1394)', () => {
  it('explica para que serve o topo embaixo de "No topo da mensagem"', () => {
    const wrapper = mount(EtapaExtras, {
      props: {
        rascunho: {
          nome: 'Lembrete',
          tipo: 'aviso',
          conteudo: {
            formato: 'padrao',
            topo: { tipo: 'nenhum', arquivo: '' },
            texto: [{ t: 'texto', v: 'Oi.' }],
            exemplos: {},
            rodape: '',
            botoes: [],
          },
        },
      },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: pt },
          }),
        ],
      },
    });

    expect(wrapper.find('[data-topo-ajuda]').text()).toBe(
      'Opcional. O mesmo arquivo vai para todas as pessoas que receberem. Use para algo igual para todos (cardápio, catálogo, regulamento). Boleto, comprovante ou documento de cada cliente não vão aqui.'
    );
  });

  const conteudo = topo => ({
    formato: 'padrao',
    topo,
    texto: [
      { t: 'texto', v: 'Seu horário é amanhã. Qualquer dúvida, responda.' },
    ],
    exemplos: {},
    rodape: '',
    botoes: [],
  });

  it('lembra só num aviso com arquivo escolhido', () => {
    const pdf = { tipo: 'documento', arquivo: 'apresentacao.pdf', local: 'x' };
    expect(lembrarArquivoIgual(conteudo(pdf), { tipo: 'aviso' })).toBe(true);
    expect(lembrarArquivoIgual(conteudo(pdf), { tipo: 'divulgacao' })).toBe(
      false
    );
    expect(
      // Só o nome que sobrou de uma cópia não é arquivo escolhido.
      lembrarArquivoIgual(
        conteudo({ tipo: 'documento', arquivo: 'boleto.pdf' }),
        {
          tipo: 'aviso',
        }
      )
    ).toBe(false);
    expect(
      lembrarArquivoIgual(conteudo({ tipo: 'texto', texto: 'Oi' }), {
        tipo: 'aviso',
      })
    ).toBe(false);
  });

  it('na conferência é um lembrete leve: não conta como problema', () => {
    const wrapper = mount(ModeloConferencia, {
      props: {
        conteudo: conteudo({
          tipo: 'documento',
          arquivo: 'apresentacao.pdf',
          local: 'x',
        }),
        contexto: { tipo: 'aviso' },
      },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: pt },
          }),
        ],
      },
    });

    expect(wrapper.find('[data-lembrete-arquivo-igual]').text()).toBe(
      'Esse arquivo vai igual para todos.'
    );
    expect(wrapper.find('[role="status"]').text()).toBe(
      pt.MODELOS_WHATSAPP.CONFERENCIA.TUDO_CERTO
    );
  });
});
