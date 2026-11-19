import { RouterLinkStub, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRouter } from 'vue-router';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { useAlert } from 'dashboard/composables';
import GavetaDoSeguro from '../../components/carteira/GavetaDoSeguro.vue';
import { DO_RODAPE } from '../../carteira/rodapeDoSeguro';
import {
  aoMeioDia,
  assentar,
  daCarteira,
  erroHttp,
  recusa,
  textoDe,
} from './apoio';

// #3057 — o acabamento da gaveta do seguro, com o texto de verdade em pt_BR:
// o seguro que vence logo sem renovação aberta tem o azul "Conversar com
// {nome}", com o PDF ao lado; e "Enviar proposta" pergunta antes, dizendo para
// quem vai, por qual WhatsApp e onde está o PDF. A fonte é de mentira, com o
// seguro no formato do servidor; as conversas e os ajustes vêm dos clientes de
// API, também de mentira. Todos os dados são inventados.
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { maximumFileUploadSize: 40 } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: { renovacoes: vi.fn() },
}));
vi.mock('dashboard/api/relacionamentos', () => ({
  default: { conversasDaPessoa: vi.fn() },
}));
// A "Nova conversa" (components/carteira/ConversaNova.vue, com teste próprio)
// é de mentira: cada teste diz se ela abriu.
const conversaNova = vi.hoisted(() => ({ abrir: null }));
vi.mock('../../components/carteira/ConversaNova.vue', async () => {
  const { defineComponent } = await import('vue');
  return {
    default: defineComponent({
      name: 'ConversaNova',
      setup(_, { expose }) {
        expose({ abrir: (...args) => conversaNova.abrir(...args) });
        return () => null;
      },
    }),
  };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {} });
  const roteador = { push: vi.fn() };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const roteador = useRouter();

// 12/11/2026, às 10h de quem roda o teste.
const AGORA = new Date(2026, 10, 12, 10).getTime();
const ATIVO = {
  id: 7,
  pessoaId: 23,
  pessoa: { id: 23, name: 'Ana Albuquerino', phone_number: null },
  segurado: { tipo: 'pessoa', id: 23, nome: 'Ana Albuquerino' },
  tipo: 'auto',
  ramoOriginal: 'Automóvel',
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
  valor: 2760,
  bem: '',
  comeca: aoMeioDia(2025, 11, 29),
  termina: aoMeioDia(2026, 11, 29),
  origem: { tipo: 'planilha', arquivo: null, em: 1790000000 },
  temPdf: true,
  canceladoEm: null,
  corrigidoAMao: [],
};
const VENCE_LOGO = { ...ATIVO, selo: 'ativo', dias: 17 };
const VENCE_LONGE = { ...ATIVO, selo: 'ativo', dias: 200 };
const RENOVACAO = {
  cardId: 88,
  funil: 'Renovação',
  etapa: 'Cotando',
  desfecho: null,
  cuida: 'Bruna Teixeirão',
};
const COM_PROPOSTA = {
  ...ATIVO,
  selo: 'em_renovacao',
  dias: 17,
  renovacao: RENOVACAO,
  cotacao: {
    etapa: 'proposta_pronta',
    premioCentavos: 250000,
    seguradora: 'Seguradora Atlântica',
    podeEnviar: true,
  },
};
const ENVIADA = {
  ...COM_PROPOSTA,
  cotacao: {
    ...COM_PROPOSTA.cotacao,
    etapa: 'proposta_enviada',
    enviadaEm: 1790000000,
    podeEnviar: false,
  },
};

const fonteDe = (seguro, resto = {}) => ({
  usaDemo: false,
  seguro: vi.fn().mockResolvedValue(seguro),
  historia: vi.fn().mockResolvedValue([]),
  ...resto,
});

let aberta;
const abrir = async (seguro, { fonte = fonteDe(seguro), ...props } = {}) => {
  aberta = mount(GavetaDoSeguro, {
    attachTo: document.body,
    props: {
      apoliceId: seguro.id,
      fonte,
      podeEditar: true,
      agora: AGORA,
      ...props,
    },
    global: { stubs: { transition: true, RouterLink: RouterLinkStub } },
  });
  await assentar();
  return aberta;
};
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
};
const azul = w => w.get(daCarteira('gaveta-acao'));
const doMenu = w =>
  w
    .findAll(`${daCarteira('mais-do-seguro')} [role="menuitem"]`)
    .map(item => item.attributes('data-acao'));
const abrirMenu = w =>
  clicar(w, `${daCarteira('mais-do-seguro')} [aria-haspopup="menu"]`);
const pergunta = w => w.find(daCarteira('confirmar-proposta'));

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  roteador.push.mockClear();
  RelacionamentosAPI.conversasDaPessoa.mockReset();
  SegurosAPI.renovacoes.mockReset();
  useAlert.mockClear();
  conversaNova.abrir = vi.fn().mockResolvedValue(true);
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
});

describe('o seguro que vence logo, sem renovação aberta', () => {
  it('o selo diz "Vence logo", em âmbar', async () => {
    const w = await abrir(VENCE_LOGO, { podeConversar: true });

    expect(textoDe(w, daCarteira('selo'))).toBe('Vence logo');
    expect(w.get(daCarteira('selo')).attributes('data-selo')).toBe('ambar');
  });

  it('o azul é "Conversar com {nome}", com "Ver PDF" ao lado e "Corrigir" no "⋯"', async () => {
    const w = await abrir(VENCE_LOGO, { podeConversar: true });

    expect(azul(w).text()).toBe('Conversar com Ana');
    expect(azul(w).attributes('data-acao')).toBe(DO_RODAPE.CONVERSAR);
    expect(textoDe(w, daCarteira('ver-pdf'))).toBe('Ver PDF');
    await abrirMenu(w);
    expect(doMenu(w)).toEqual([
      DO_RODAPE.CORRIGIR,
      DO_RODAPE.GUARDAR_OUTRO_PDF,
      DO_RODAPE.APAGAR_PDF,
      DO_RODAPE.MARCAR_CANCELADO,
    ]);
  });

  it('"Conversar" abre a conversa mais recente da pessoa', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockResolvedValue({
      data: [{ id: 412 }, { id: 300 }],
    });
    const w = await abrir(VENCE_LOGO, { podeConversar: true });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(RelacionamentosAPI.conversasDaPessoa).toHaveBeenCalledWith(23);
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 412 },
      query: undefined,
    });
  });

  // #3057 (2ª rodada) — a ficha esconde o "Conversar" de quem não tem
  // conversa: a gaveta abre a "Nova conversa" já com a pessoa.
  it('quem nunca conversou: abre a "Nova conversa" já com a pessoa', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockResolvedValue({ data: [] });
    const w = await abrir(VENCE_LOGO, { podeConversar: true });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(conversaNova.abrir).toHaveBeenCalledWith(23);
    expect(roteador.push).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('se as conversas não vêm, também abre a "Nova conversa"', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockRejectedValue(erroHttp(500));
    const w = await abrir(VENCE_LOGO, { podeConversar: true });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(conversaNova.abrir).toHaveBeenCalledWith(23);
  });

  it('se a "Nova conversa" não abre, diz que ainda não conversaram e onde está o telefone', async () => {
    RelacionamentosAPI.conversasDaPessoa.mockResolvedValue({ data: [] });
    conversaNova.abrir.mockResolvedValue(false);
    const w = await abrir(VENCE_LOGO, { podeConversar: true });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(useAlert).toHaveBeenCalledWith(
      'Vocês ainda não conversaram por aqui. O telefone está na ficha.'
    );
    expect(roteador.push).not.toHaveBeenCalled();
  });

  it('na demonstração o clique só avisa', async () => {
    const w = await abrir(VENCE_LOGO, {
      podeConversar: true,
      fonte: { ...fonteDe(VENCE_LOGO), usaDemo: true },
    });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(useAlert).toHaveBeenCalledWith(
      'Abrindo a conversa com Ana Albuquerino'
    );
    expect(roteador.push).not.toHaveBeenCalled();
  });

  it('sem PDF, "Guardar o PDF" fica ao lado', async () => {
    const w = await abrir(
      { ...VENCE_LOGO, temPdf: false },
      { podeConversar: true }
    );

    expect(azul(w).text()).toBe('Conversar com Ana');
    expect(textoDe(w, daCarteira('guardar-pdf'))).toBe('Guardar o PDF');
  });

  it('quem só pode ver a pessoa também conversa, com o PDF ao lado e sem "⋯"', async () => {
    const w = await abrir(VENCE_LOGO, {
      podeConversar: true,
      podeEditar: false,
    });

    expect(azul(w).text()).toBe('Conversar com Ana');
    expect(textoDe(w, daCarteira('ver-pdf'))).toBe('Ver PDF');
    expect(w.find(daCarteira('mais-do-seguro')).exists()).toBe(false);
  });

  it('onde a gaveta não conversa (o painel da conversa), o rodapé é o de sempre', async () => {
    const w = await abrir(VENCE_LOGO);

    expect(azul(w).text()).toBe('Ver PDF');
    expect(w.find(daCarteira('corrigir')).exists()).toBe(true);
  });

  it('o seguro que vence longe segue com "Ver PDF" no azul', async () => {
    const w = await abrir(VENCE_LONGE, { podeConversar: true });

    expect(textoDe(w, daCarteira('selo'))).toBe('Ativo');
    expect(azul(w).text()).toBe('Ver PDF');
  });

  it('com a renovação aberta e sem proposta para enviar, o azul é "Renovou"', async () => {
    const w = await abrir(
      { ...VENCE_LOGO, selo: 'em_renovacao', renovacao: RENOVACAO },
      { podeConversar: true }
    );

    expect(azul(w).attributes('data-acao')).toBe(DO_RODAPE.RENOVOU);
  });
});

// R$ 2.500,00 do jeito que o painel escreve (com o espaço do Intl).
const REAIS_2500 = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
}).format(2500);

describe('"Enviar proposta" pergunta antes', () => {
  const comAjustes = caixaId =>
    SegurosAPI.renovacoes.mockResolvedValue({
      data: {
        ajustes: {
          funilId: 1,
          etapaId: 11,
          dias: 60,
          quemCota: 'robo',
          quemEnvia: 'pessoa',
          quemResponde: 'equipe',
          caixaId,
        },
        funis: [],
        caixas: [
          { id: 5, nome: 'Vendas', liaLigada: true },
          { id: 6, nome: 'Renovações', liaLigada: false },
        ],
        cotacaoLiberada: true,
      },
    });

  it('o clique não envia: abre a pergunta com quem recebe, o WhatsApp e o PDF', async () => {
    comAjustes(6);
    const fonte = fonteDe(COM_PROPOSTA, { enviarProposta: vi.fn() });
    const w = await abrir(COM_PROPOSTA, { fonte });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(fonte.enviarProposta).not.toHaveBeenCalled();
    expect(pergunta(w).text()).toContain('Enviar a proposta?');
    expect(pergunta(w).text()).toContain(
      `Vai para Ana Albuquerino pelo WhatsApp Renovações: a proposta de ${REAIS_2500}, da Seguradora Atlântica, com o PDF.`
    );
    const pdf = w.getComponent(RouterLinkStub);
    expect(pdf.text()).toBe('Ver a proposta no CRM (abre em outra aba)');
    expect(pdf.props('to')).toEqual({
      name: 'crm_kanban_index',
      query: { card_id: '88' },
    });
    expect(pdf.attributes('target')).toBe('_blank');
    expect(textoDe(w, '[data-confirmar]')).toBe('Enviar agora');
    expect(textoDe(w, '[data-cancelar]')).toBe('Voltar');
    // Enviar não destrói nada: o botão de confirmar é o azul.
    expect(w.get('[data-dialogo-falso]').attributes('data-tipo')).toBe('edit');
  });

  it('"Enviar agora" manda pelo mesmo pedido, fecha a pergunta e diz que saiu', async () => {
    comAjustes(6);
    const fonte = fonteDe(COM_PROPOSTA, {
      enviarProposta: vi.fn().mockResolvedValue(ENVIADA),
    });
    const w = await abrir(COM_PROPOSTA, { fonte });
    await clicar(w, daCarteira('gaveta-acao'));

    await clicar(w, '[data-confirmar]');

    expect(fonte.enviarProposta).toHaveBeenCalledTimes(1);
    expect(fonte.enviarProposta).toHaveBeenCalledWith(7, undefined);
    expect(pergunta(w).exists()).toBe(false);
    expect(textoDe(w, daCarteira('aviso-vivo'))).toBe(
      'Proposta enviada ao cliente.'
    );
  });

  it('"Voltar" fecha sem enviar', async () => {
    comAjustes(6);
    const fonte = fonteDe(COM_PROPOSTA, { enviarProposta: vi.fn() });
    const w = await abrir(COM_PROPOSTA, { fonte });
    await clicar(w, daCarteira('gaveta-acao'));

    await clicar(w, '[data-cancelar]');

    expect(pergunta(w).exists()).toBe(false);
    expect(fonte.enviarProposta).not.toHaveBeenCalled();
  });

  it('a recusa fecha a pergunta e diz o que fazer no rodapé', async () => {
    comAjustes(6);
    const fonte = fonteDe(COM_PROPOSTA, {
      enviarProposta: vi.fn().mockRejectedValue(recusa('sem_modelo')),
    });
    const w = await abrir(COM_PROPOSTA, { fonte });
    await clicar(w, daCarteira('gaveta-acao'));

    await clicar(w, '[data-confirmar]');

    expect(pergunta(w).exists()).toBe(false);
    expect(w.find(daCarteira('alerta-da-gaveta')).exists()).toBe(true);
  });

  it('sem o WhatsApp escolhido (ou sem conseguir ler), diz o das renovações', async () => {
    SegurosAPI.renovacoes.mockRejectedValue(erroHttp(500));
    const w = await abrir(COM_PROPOSTA, {
      fonte: fonteDe(COM_PROPOSTA, { enviarProposta: vi.fn() }),
    });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(pergunta(w).text()).toContain(
      `Vai para Ana Albuquerino pelo WhatsApp das renovações: a proposta de ${REAIS_2500}, da Seguradora Atlântica, com o PDF.`
    );
  });

  it('o WhatsApp que saiu da conta também não aparece', async () => {
    comAjustes(99);
    const w = await abrir(COM_PROPOSTA, {
      fonte: fonteDe(COM_PROPOSTA, { enviarProposta: vi.fn() }),
    });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(pergunta(w).text()).toContain('pelo WhatsApp das renovações:');
  });
});

// #3057 (2ª rodada) — com a renovação aberta e a proposta pronta, mandar a
// proposta é o próximo passo: ela é o azul do rodapé, "Renovou" fica ao lado e
// "Não renovou" desce para o "⋯". O botão claro saiu de dentro da Cotação.
describe('o rodapé com a proposta pronta', () => {
  it('o azul é "Enviar proposta", "Renovou" ao lado, "Não renovou" no "⋯"', async () => {
    const w = await abrir(COM_PROPOSTA);

    expect(azul(w).text()).toBe('Enviar proposta');
    expect(azul(w).attributes('data-acao')).toBe(DO_RODAPE.ENVIAR_PROPOSTA);
    expect(textoDe(w, daCarteira('renovou'))).toBe('Renovou');
    expect(
      w.find(daCarteira('cotacao-do-seguro')).findAll('button')
    ).toHaveLength(0);
    await abrirMenu(w);
    expect(doMenu(w)[0]).toBe(DO_RODAPE.NAO_RENOVOU);
    expect(doMenu(w)).toContain(DO_RODAPE.CORRIGIR);
  });

  it('a proposta que talvez não chegou é enviada "de novo"', async () => {
    const w = await abrir({
      ...COM_PROPOSTA,
      cotacao: {
        ...COM_PROPOSTA.cotacao,
        etapa: 'proposta_enviada',
        incerta: true,
      },
    });

    expect(azul(w).text()).toBe('Enviar de novo');
  });

  it('depois de enviada, o azul volta a ser "Renovou"', async () => {
    const w = await abrir(ENVIADA);

    expect(azul(w).attributes('data-acao')).toBe(DO_RODAPE.RENOVOU);
  });

  it('a pergunta só abre depois de ler o nome do WhatsApp; até lá, o azul gira', async () => {
    let responder;
    SegurosAPI.renovacoes.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const w = await abrir(COM_PROPOSTA, {
      fonte: fonteDe(COM_PROPOSTA, { enviarProposta: vi.fn() }),
    });

    await clicar(w, daCarteira('gaveta-acao'));

    expect(pergunta(w).exists()).toBe(false);
    expect(azul(w).find('.animate-spin').exists()).toBe(true);

    responder({
      data: {
        ajustes: {
          funilId: 1,
          etapaId: 11,
          dias: 60,
          quemCota: 'robo',
          quemEnvia: 'pessoa',
          quemResponde: 'equipe',
          caixaId: 6,
        },
        funis: [],
        caixas: [{ id: 6, nome: 'Renovações', liaLigada: false }],
        cotacaoLiberada: true,
      },
    });
    await assentar();

    expect(pergunta(w).text()).toContain('pelo WhatsApp Renovações:');
  });
});
