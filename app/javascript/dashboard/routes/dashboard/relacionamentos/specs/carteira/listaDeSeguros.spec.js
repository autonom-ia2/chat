import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { useAlert } from 'dashboard/composables';
import ControlesDeSeguros from '../../components/carteira/ControlesDeSeguros.vue';
import GavetaDeFiltrosDeSeguros from '../../components/carteira/GavetaDeFiltrosDeSeguros.vue';
import ListaDeSeguros from '../../components/carteira/ListaDeSeguros.vue';
import { DO_RODAPE } from '../../carteira/rodapeDoSeguro';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { GRUPOS_DE_SEGUROS } from '../../fonte/gruposDeSeguros';
import { POR_PAGINA } from '../../fonte/listaFonte';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  erroHttp,
  semRolagem,
  textoDe,
} from './apoio';

// A aba Seguros de Relacionamentos (#2897) com o texto de verdade em pt_BR: o
// herói, as abas, os grupos, a busca, a ordem, os filtros, a gaveta pelo
// endereço e os estados sem seguro, carregando, erro e sem acesso. Na
// demonstração lê a carteira fictícia; sem ela, o servidor (o cliente de API é
// de mentira).
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: {
    lista: vi.fn(),
    contagens: vi.fn(),
    resumo: vi.fn(),
    opcoesDeFiltro: vi.fn(),
    seguro: vi.fn(),
    historia: vi.fn(),
  },
}));
const permissoes = vi.hoisted(() => ({ podeEditar: true }));
vi.mock('../../ficha/usePermissoesDaFicha', () => ({
  usePermissoesDaFicha: () => ({
    podeEditar: { value: permissoes.podeEditar },
  }),
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relationships_home' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();
const daLista = nome => `[data-relacionamentos="${nome}"]`;

const PESSOA_DAS_JORNADAS = 23;
const SEGURO_DAS_JORNADAS = 1;
const ESPERA_DA_BUSCA_MS = 400;

// Um seguro como o servidor manda (datas sem hora, selo e dias prontos).
const DO_SERVIDOR = {
  id: 7,
  pessoaId: 23,
  pessoa: { id: 23, name: 'Ana Albuquerino', phone_number: null },
  segurado: {
    tipo: 'pessoa',
    id: 23,
    nome: 'Ana Albuquerino',
    documento: null,
  },
  tipo: 'auto',
  ramoOriginal: null,
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
  valor: 2760,
  bem: '',
  comeca: '2025-11-29',
  termina: '2026-11-29',
  selo: 'ativo',
  dias: 17,
  origem: { tipo: 'planilha', arquivo: null, em: 1790000000 },
  temPdf: true,
  canceladoEm: null,
  corrigidoAMao: [],
};

let aberta;
const abrir = async ({ demo = 'cheio', query = {}, ...props } = {}) => {
  rota.query = query;
  aberta = mount(ListaDeSeguros, {
    attachTo: document.body,
    props: { demo, comEmpresas: true, ...props },
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};

const linhas = w => w.findAll(daCarteira('linha'));
const nomes = w => linhas(w).map(linha => linha.get('button').text());
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
};
const buscar = async (w, texto) => {
  await w.get(daLista('busca')).setValue(texto);
  await vi.advanceTimersByTimeAsync(ESPERA_DA_BUSCA_MS);
  await assentar();
};
const cancelarNaGaveta = async w => {
  await w
    .get(`${daCarteira('mais-do-seguro')} [aria-haspopup="menu"]`)
    .trigger('click');
  await clicar(
    w,
    `[role="menuitem"][data-acao="${DO_RODAPE.MARCAR_CANCELADO}"]`
  );
};

// Os números da carteira fictícia, lidos da própria fonte antes dos testes.
const carteira = { resumo: null };
beforeAll(async () => {
  await carregarDemonstracao();
  const fonte = carteiraFonte({ demo: 'cheio', atraso: 0 });
  carteira.resumo = await fonte.resumo();
}, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  semRolagem();
  permissoes.podeEditar = true;
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
});

describe('o herói e as abas', () => {
  it('diz quantos seguros vencem em até 7 dias e leva ao grupo', async () => {
    const w = await abrir();
    const { vence7 } = carteira.resumo;

    expect(w.get(daCarteira('heroi')).attributes('data-heroi')).toBe('vence_7');
    expect(textoDe(w, '[data-heroi-frase]')).toBe(
      `${vence7} seguros vencem nos próximos 7 dias.`
    );
    expect(textoDe(w, daCarteira('heroi-acao'))).toBe('Ver quais');

    await clicar(w, daCarteira('heroi-acao'));

    expect(
      w.get('[data-grupo="vence_7_dias"]').attributes('aria-pressed')
    ).toBe('true');
    expect(textoDe(w, daCarteira('explicacao-do-grupo'))).toBe(
      'Seguros que terminam nos próximos 7 dias.'
    );
    expect(linhas(w)).toHaveLength(Math.min(vence7, POR_PAGINA));
  });

  it('quem pode trazer lista vê o botão de trazer seguros, que avisa a página', async () => {
    const w = await abrir({ podeTrazer: true });

    expect(textoDe(w, daCarteira('heroi-trazer'))).toBe('Trazer seguros');

    await clicar(w, daCarteira('heroi-trazer'));

    expect(w.emitted('trazer')).toHaveLength(1);
  });

  it('sem poder trazer lista, a aba não oferece trazer seguros; e não há marcar nem mandar mensagem', async () => {
    const w = await abrir();

    expect(w.find(daCarteira('heroi-trazer')).exists()).toBe(false);
    expect(w.findAll(daCarteira('heroi-acao'))).toHaveLength(1);
    expect(w.find('input[type="checkbox"]').exists()).toBe(false);
    expect(w.find(daCarteira('barra')).exists()).toBe(false);
    expect(w.text()).not.toContain('Trazer');
    expect(w.text()).not.toContain('Mandar mensagem');
  });

  it('a aba Seguros está escolhida, e trocar de aba é com a página', async () => {
    const w = await abrir();
    const seguros = w.get(daLista('aba-seguros'));

    expect(seguros.text()).toBe('Seguros');
    expect(seguros.attributes('aria-selected')).toBe('true');
    await w.get(daLista('aba-pessoas')).trigger('click');

    expect(w.emitted('trocarAba')).toEqual([['pessoas']]);
  });

  it('conta sem Empresas fica com Pessoas e Seguros', async () => {
    const w = await abrir({ comEmpresas: false });

    expect(w.find(daLista('aba-empresas')).exists()).toBe(false);
    expect(w.find(daLista('aba-seguros')).exists()).toBe(true);
  });
});

describe('os grupos e a lista', () => {
  it('mostra os grupos por vencimento, cada um com o seu número', async () => {
    const w = await abrir();
    const pilulas = w.findAll('[data-grupo]');

    expect(pilulas.map(pilula => pilula.attributes('data-grupo'))).toEqual(
      GRUPOS_DE_SEGUROS.map(grupo => grupo.id)
    );
    expect(pilulas[0].text()).toContain('Todos');
    expect(pilulas[0].text()).toContain(String(carteira.resumo.total));
    expect(pilulas[1].text()).toContain(String(carteira.resumo.vence7));
    expect(pilulas[0].attributes('aria-pressed')).toBe('true');
  });

  it('um seguro por linha: nome, selo, tipo, seguradora e quando vence', async () => {
    const w = await abrir();
    const [primeira] = linhas(w);

    expect(linhas(w)).toHaveLength(POR_PAGINA);
    expect(primeira.find(daCarteira('selo')).text()).toBe('Ativo');
    expect(primeira.text()).toContain('vence em 3 dias');
    // Nada de caixinha nem de atalho: a linha só abre o seguro.
    expect(primeira.find('input').exists()).toBe(false);
    expect(primeira.findAll('button')).toHaveLength(1);
  });

  it('"Mostrar mais" traz a página seguinte', async () => {
    const w = await abrir();

    await clicar(w, daLista('mostrar-mais'));

    expect(linhas(w)).toHaveLength(POR_PAGINA * 2);
  });

  it('o grupo "Vencido" só mostra seguro vencido', async () => {
    const w = await abrir();

    await clicar(w, '[data-grupo="vencido"]');

    const selos = w
      .findAll(`${daCarteira('linha')} ${daCarteira('selo')}`)
      .map(selo => selo.attributes('data-selo-da-carteira'));
    expect(selos.length).toBeGreaterThan(0);
    expect(new Set(selos)).toEqual(new Set(['vencido']));
    expect(linhas(w)[0].text()).toContain('venceu');
  });
});

describe('busca, ordem e filtros', () => {
  it('busca pelo número da apólice', async () => {
    const w = await abrir();

    await buscar(w, 'AT-000451');

    expect(linhas(w)).toHaveLength(1);
    expect(linhas(w)[0].text()).toContain('Seguradora Atlântica');
    expect(w.get('[data-grupo="todos"]').text()).toContain('1');
  });

  it('busca sem resultado diz o que houve e oferece limpar', async () => {
    const w = await abrir();

    await buscar(w, 'zzzzqx');

    const frase = 'Não achei nenhum seguro com “zzzzqx”.';
    expect(textoDe(w, daCarteira('vazio'))).toContain(frase);
    expect(textoDe(w, daCarteira('aviso-da-lista'))).toBe(frase);

    await clicar(w, `${daCarteira('vazio')} button`);

    expect(linhas(w)).toHaveLength(POR_PAGINA);
    expect(w.get(daLista('busca')).element.value).toBe('');
  });

  it('ordena por nome', async () => {
    const w = await abrir();

    w.findComponent(ControlesDeSeguros).vm.$emit('update:ordem', 'nome');
    await assentar();

    const naTela = nomes(w);
    expect(naTela).toEqual(
      [...naTela].sort((a, b) => a.localeCompare(b, 'pt-BR'))
    );
  });

  it('"Mais filtros" oferece o que a carteira tem e conta o que está ligado', async () => {
    const w = await abrir();
    const filtros = () => w.findComponent(GavetaDeFiltrosDeSeguros);

    await clicar(w, daCarteira('mais-filtros'));

    expect(w.find(daCarteira('filtros')).exists()).toBe(true);
    expect(filtros().props('opcoes').seguradoras).toHaveLength(4);

    filtros().vm.$emit('aplicar', { tipo: 'vida', seguradora: '' });
    await assentar();

    expect(w.find(daCarteira('filtros')).exists()).toBe(false);
    expect(textoDe(w, daCarteira('mais-filtros'))).toBe('Mais filtros · 1');
    expect(linhas(w).every(linha => linha.text().includes('Vida'))).toBe(true);

    filtros().vm.$emit('limpar');
    await assentar();

    expect(textoDe(w, daCarteira('mais-filtros'))).toBe('Mais filtros');
    expect(linhas(w)).toHaveLength(POR_PAGINA);
  });

  it('filtro sem resultado oferece limpar os filtros', async () => {
    const w = await abrir();

    w.findComponent(GavetaDeFiltrosDeSeguros).vm.$emit('aplicar', {
      tipo: 'vida',
      seguradora: 'Seguradora que não existe',
    });
    await assentar();

    expect(textoDe(w, daCarteira('vazio'))).toContain(
      'Nenhum seguro com esses filtros.'
    );
    await clicar(w, `${daCarteira('vazio')} button`);

    expect(linhas(w)).toHaveLength(POR_PAGINA);
  });
});

describe('a gaveta do seguro', () => {
  it('clicar no nome põe o seguro no endereço e abre a gaveta', async () => {
    const w = await abrir();
    await buscar(w, 'AT-000451');

    await clicar(w, `${daCarteira('linha')} button`);

    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { apolice: String(SEGURO_DAS_JORNADAS) },
    });
    expect(textoDe(w, '[data-view-title]')).toBe('Auto · Seguradora Atlântica');
  });

  it('o endereço com `?apolice=` já abre a gaveta, e fechar tira do endereço', async () => {
    const w = await abrir({ query: { aba: 'seguros', apolice: '2' } });

    expect(textoDe(w, '[data-view-title]')).toBe(
      'Residencial · Horizonte Seguros'
    );
    await clicar(w, '[role="dialog"] header button');

    expect(roteador.push).toHaveBeenLastCalledWith({
      query: { aba: 'seguros' },
    });
    expect(w.find('[role="dialog"]').exists()).toBe(false);
  });

  it('o que muda na gaveta aparece na lista', async () => {
    const w = await abrir({ query: { apolice: '1' } });
    await buscar(w, 'AT-000451');

    await cancelarNaGaveta(w);

    expect(
      w
        .get(`${daCarteira('linha')} ${daCarteira('selo')}`)
        .attributes('data-selo-da-carteira')
    ).toBe('cancelado');
    expect(linhas(w)[0].text()).toContain('cancelado em');
  });

  it('depois de mudar um seguro, a lista relê sem voltar ao começo', async () => {
    const w = await abrir();
    await clicar(w, daLista('mostrar-mais'));
    const quantas = linhas(w).length;
    const primeiro = linhas(w)[0].attributes('data-apolice');
    await clicar(w, `${daCarteira('linha')} button`);

    await cancelarNaGaveta(w);

    // As duas páginas continuam à vista, e quem foi cancelado saiu do topo
    // (deixou de valer): a lista foi relida de verdade.
    expect(quantas).toBeGreaterThan(POR_PAGINA);
    expect(linhas(w)).toHaveLength(quantas);
    expect(linhas(w)[0].attributes('data-apolice')).not.toBe(primeiro);
    expect(w.find(daCarteira('carregando')).exists()).toBe(false);
    expect(w.find('[role="dialog"]').exists()).toBe(true);
  });

  it('o nome do segurado na gaveta leva à ficha', async () => {
    const w = await abrir({ query: { apolice: '1' } });

    await w.get(daCarteira('abrir-segurado')).trigger('click');

    expect(roteador.push).toHaveBeenLastCalledWith({
      name: 'relacionamentos_pessoa',
      params: { contactId: PESSOA_DAS_JORNADAS },
    });
  });
});

describe('sem seguro, carregando e erro', () => {
  it('conta sem seguro: a frase, o apoio e a lista de exemplo, sem botão', async () => {
    const w = await abrir({ demo: 'sem-seguros' });

    expect(w.get(daCarteira('heroi')).attributes('data-heroi')).toBe(
      'sem_seguro'
    );
    expect(textoDe(w, '[data-heroi-frase]')).toBe('Ainda não há seguros aqui.');
    expect(textoDe(w, daCarteira('heroi'))).toContain(
      'Os seguros da sua carteira aparecem aqui e na ficha de cada pessoa.'
    );
    expect(w.find(daCarteira('heroi-acao')).exists()).toBe(false);
    expect(w.findAll('button[disabled]')).toHaveLength(0);
    const exemplo = w.get(daCarteira('seguros-de-exemplo'));
    expect(exemplo.attributes('aria-hidden')).toBe('true');
    expect(exemplo.findAll('[data-linha-de-exemplo]')).toHaveLength(5);
    expect(w.find('[data-grupo]').exists()).toBe(false);
    expect(w.find(daLista('aba-seguros')).exists()).toBe(true);
  });

  it('enquanto carrega mostra o esqueleto', async () => {
    const w = await abrir({ demo: 'carregando' });

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(w.find(daCarteira('heroi')).exists()).toBe(false);
  });

  it('no erro, diz a frase e oferece tentar de novo', async () => {
    const w = await abrir({ query: { 'demo-carteira': 'erro' } });

    expect(textoDe(w, daCarteira('erro'))).toContain(
      'Não consegui mostrar os seguros. Tente de novo.'
    );
    expect(w.find(`${daCarteira('erro')} button`).exists()).toBe(true);
  });
});

describe('fora da demonstração (o servidor)', () => {
  const servidorResponde = () => {
    SegurosAPI.resumo.mockResolvedValue({ data: { total: 1, vence7: 0 } });
    SegurosAPI.contagens.mockResolvedValue({ data: { todos: 1 } });
    SegurosAPI.lista.mockResolvedValue({
      data: { itens: [DO_SERVIDOR], total: 1, temMais: false },
    });
    SegurosAPI.seguro.mockResolvedValue({ data: DO_SERVIDOR });
    SegurosAPI.historia.mockResolvedValue({ data: [] });
  };

  it('lê do servidor e escreve a linha com o selo e os dias que ele mandou', async () => {
    servidorResponde();
    const w = await abrir({ demo: null });

    expect(SegurosAPI.lista).toHaveBeenCalledWith({
      grupo: 'todos',
      ordem: 'vence_primeiro',
      pagina: 1,
    });
    expect(textoDe(w, '[data-heroi-frase]')).toBe(
      'Você tem 1 seguro. Ele não vence nos próximos 7 dias.'
    );
    expect(nomes(w)).toEqual(['Ana Albuquerino']);
    expect(linhas(w)[0].text()).toContain('vence em 17 dias (29/11');
  });

  it('sem nada vencendo na semana e com vencidos, o herói fala deles e leva ao grupo', async () => {
    servidorResponde();
    SegurosAPI.resumo.mockResolvedValue({ data: { total: 6, vence7: 0 } });
    SegurosAPI.contagens.mockResolvedValue({
      data: { todos: 6, vencido: 2 },
    });
    const w = await abrir({ demo: null });

    expect(w.get(daCarteira('heroi')).attributes('data-heroi')).toBe(
      'vencidos'
    );
    expect(textoDe(w, '[data-heroi-frase]')).toBe('2 seguros já venceram.');
    expect(textoDe(w, daCarteira('heroi-acao'))).toBe('Ver vencidos');
    // A contagem é a que a barra de grupos já carrega: um pedido só.
    expect(SegurosAPI.contagens).toHaveBeenCalledTimes(1);

    await clicar(w, daCarteira('heroi-acao'));

    expect(w.get('[data-grupo="vencido"]').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(SegurosAPI.lista).toHaveBeenLastCalledWith({
      grupo: 'vencido',
      ordem: 'vence_primeiro',
      pagina: 1,
    });
  });

  it('com os dois, vale a frase de quem vence em 7 dias', async () => {
    servidorResponde();
    SegurosAPI.resumo.mockResolvedValue({ data: { total: 6, vence7: 3 } });
    SegurosAPI.contagens.mockResolvedValue({
      data: { todos: 6, vencido: 2 },
    });
    const w = await abrir({ demo: null });

    expect(textoDe(w, '[data-heroi-frase]')).toBe(
      '3 seguros vencem nos próximos 7 dias.'
    );
    expect(textoDe(w, daCarteira('heroi-acao'))).toBe('Ver quais');
  });

  it('a busca não muda a frase do topo, que fala da carteira inteira', async () => {
    servidorResponde();
    SegurosAPI.resumo.mockResolvedValue({ data: { total: 6, vence7: 0 } });
    SegurosAPI.contagens.mockResolvedValue({
      data: { todos: 6, vencido: 2 },
    });
    const w = await abrir({ demo: null });
    SegurosAPI.contagens.mockResolvedValue({
      data: { todos: 1, vencido: 0 },
    });

    await buscar(w, 'AT-000451');

    expect(textoDe(w, '[data-heroi-frase]')).toBe('2 seguros já venceram.');
  });

  it('quem só pode ver a pessoa abre a gaveta sem as ações de escrita', async () => {
    servidorResponde();
    permissoes.podeEditar = false;
    const w = await abrir({ demo: null, query: { apolice: '7' } });

    expect(SegurosAPI.seguro).toHaveBeenCalledWith(7);
    expect(textoDe(w, daCarteira('gaveta-acao'))).toBe('Ver PDF');
    expect(w.find(daCarteira('corrigir')).exists()).toBe(false);
    expect(w.find(daCarteira('mais-do-seguro')).exists()).toBe(false);
  });

  it('quem não pode ver os contatos lê só que não tem acesso', async () => {
    ['resumo', 'contagens', 'lista'].forEach(leitura =>
      SegurosAPI[leitura].mockRejectedValue(erroHttp(401))
    );
    const w = await abrir({ demo: null });

    expect(textoDe(w, daLista('sem-acesso'))).toBe(
      'Você não tem acesso aos seguros desta conta.'
    );
    expect(w.find(daCarteira('erro')).exists()).toBe(false);
    expect(w.find(daCarteira('linha')).exists()).toBe(false);
    expect(w.find(daLista('aba-seguros')).exists()).toBe(true);
  });

  it('falha ao abrir "Mais filtros" avisa e não quebra a tela', async () => {
    servidorResponde();
    SegurosAPI.opcoesDeFiltro.mockRejectedValue(erroHttp(500));
    const w = await abrir({ demo: null });

    await clicar(w, daCarteira('mais-filtros'));

    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui carregar. Tente de novo.'
    );
    expect(w.find(daCarteira('filtros')).exists()).toBe(true);
  });
});
