import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRoute, useRouter } from 'vue-router';
import BarraDeControles from '../../components/lista/BarraDeControles.vue';
import ListaPage from '../../pages/ListaPage.vue';
import { usarDemo } from '../../fonte/modoDemo';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  doBlocoA,
  textoDe,
} from './apoio';

// A aba Seguros e a lista de pessoas em conta de seguros (#2897, telas 1 e 2),
// pela página de verdade, com a carteira fictícia e o texto em pt_BR. A
// demonstração entra pelo endereço (`?demo=`), como no navegador.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
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
// As fontes de demonstração sem o atraso de 300 ms.
const semAtraso = vi.hoisted(() => nome => async importOriginal => {
  const real = await importOriginal();
  return { ...real, [nome]: opcoes => real[nome]({ ...opcoes, atraso: 0 }) };
});
vi.mock('../../fonte/listaFonte', semAtraso('listaFonte'));
vi.mock('../../fonte/carteiraFonte', semAtraso('carteiraFonte'));
vi.mock('../../fonte/acoesDaListaFonte', semAtraso('acoesDaListaFonte'));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();

let aberta;
const abrir = async (query = {}) => {
  rota.name = 'relationships_home';
  rota.query = { demo: 'cheio', ...query };
  aberta = mount(ListaPage, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const abrirSeguros = query => abrir({ aba: 'seguros', ...query });
const linhas = w => w.findAll(daCarteira('linha'));
const pilula = (w, id) => w.get(`[data-grupo="${id}"]`);
const linhaDo = (w, id) =>
  w.get(`${daCarteira('linha')}[data-apolice="${id}"]`);
const marcar = async (w, id) => {
  await linhaDo(w, id).get('input[type="checkbox"]').trigger('change');
};
const digitar = async (w, seletor, texto) => {
  await w.get(seletor).setValue(texto);
  await vi.advanceTimersByTimeAsync(500);
  await flushPromises();
};
const buscar = (w, texto) => digitar(w, `${daCarteira('busca')} input`, texto);
const buscarPessoa = (w, texto) =>
  digitar(w, `input${doBlocoA('busca')}`, texto);

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
  usarDemo({ demo: 'desligado' });
  vi.clearAllMocks();
});

describe('aba Seguros: cheia', () => {
  it('o herói fala de quem vence em 7 dias e o botão leva a esse grupo', async () => {
    const w = await abrirSeguros();

    const heroi = textoDe(w, daCarteira('heroi'));
    expect(heroi).toContain('5 seguros vencem nos próximos 7 dias.');
    expect(heroi).toContain('Todos já estão em renovação.');
    expect(w.get(daCarteira('heroi-acao')).text()).toBe('Ver quais');
    expect(w.findAll(daCarteira('heroi-acao'))).toHaveLength(1);

    await w.get(daCarteira('heroi-acao')).trigger('click');
    await assentar();

    expect(pilula(w, 'vence_7_dias').attributes('aria-pressed')).toBe('true');
    expect(linhas(w)).toHaveLength(5);
    expect(textoDe(w, daCarteira('explicacao-do-grupo'))).toBe(
      'Seguros que terminam nesta semana.'
    );
  });

  it('cada grupo mostra quantos seguros tem', async () => {
    const w = await abrirSeguros();

    const numeros = Object.fromEntries(
      w.findAll('[data-grupo]').map(p => [p.attributes('data-grupo'), p.text()])
    );
    expect(numeros.todos).toContain('168');
    expect(numeros.vence_7_dias).toContain('5');
    expect(numeros.vence_30_dias).toContain('17');
    expect(numeros.vence_90_dias).toContain('31');
    expect(numeros.em_renovacao).toContain('22');
    expect(numeros.vencido).toContain('41');
    expect(numeros.sem_telefone).toContain('4');
    expect(numeros.parcela_atrasada).toContain('3');
  });

  it('um seguro por linha, 25 de cada vez, o que vence primeiro em cima', async () => {
    const w = await abrirSeguros();

    expect(linhas(w)).toHaveLength(25);
    expect(textoDe(w, doBlocoA('lista'))).toContain('Mostrando 25 de 168');
    const primeira = textoDe(w, daCarteira('linha'));
    expect(primeira).toContain('Em renovação');
    expect(primeira).toContain('vence em 2 dias');

    await w.get(doBlocoA('mostrar-mais')).trigger('click');
    await assentar();
    expect(linhas(w)).toHaveLength(50);
  });

  it('as três abas aparecem e a de Seguros está escolhida', async () => {
    const w = await abrirSeguros();

    expect(w.get(doBlocoA('aba-seguros')).attributes('aria-selected')).toBe(
      'true'
    );
    await w.get(doBlocoA('aba-pessoas')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({ query: { demo: 'cheio' } });
  });

  it('clicar na linha abre a gaveta do seguro pelo endereço', async () => {
    const w = await abrirSeguros();

    await linhaDo(w, 110).get('button[aria-label^="Abrir"]').trigger('click');
    await assentar();

    expect(rota.query.apolice).toBe('110');
    expect(textoDe(w, '[data-view-title]')).toBe('Vida · Serra Azul Seguros');
  });

  it('a busca acha pela placa e pelo número da apólice', async () => {
    const w = await abrirSeguros();

    await buscar(w, 'fic-0a23');
    expect(linhas(w).map(l => l.attributes('data-apolice'))).toEqual(['1']);

    await buscar(w, 'HZ-002318');
    expect(linhas(w).map(l => l.attributes('data-apolice'))).toEqual(['2']);
  });

  it('busca sem resultado: diz o que procurou e oferece limpar', async () => {
    const w = await abrirSeguros();
    await buscar(w, 'zzzz');

    const vazio = w.get(daCarteira('vazio'));
    expect(vazio.text()).toContain('Não achei nenhum seguro com “zzzz”.');
    expect(textoDe(w, daCarteira('aviso-da-lista'))).toContain('zzzz');

    await vazio.get('button').trigger('click');
    await assentar();
    expect(linhas(w)).toHaveLength(25);
  });

  it('no grupo "Sem telefone" a linha diz isso no lugar do vencimento', async () => {
    const w = await abrirSeguros();
    await pilula(w, 'sem_telefone').trigger('click');
    await assentar();

    expect(linhas(w)).toHaveLength(4);
    expect(textoDe(w, daCarteira('linha'))).toContain('Sem telefone');
  });

  it('"Trazer seguros" leva à tela de trazer', async () => {
    const w = await abrirSeguros();

    await w.get(daCarteira('heroi-trazer')).trigger('click');

    expect(roteador.push).toHaveBeenLastCalledWith({
      name: 'relacionamentos_trazer',
    });
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('Resultados e Ajustar renovações levam às telas deles; Conversar avisa o que vai abrir', async () => {
    const w = await abrirSeguros();

    await w.get(daCarteira('resultados')).trigger('click');
    expect(roteador.push).toHaveBeenLastCalledWith({
      name: 'relacionamentos_resultados',
    });
    await w.get(daCarteira('ajustar')).trigger('click');
    expect(roteador.push).toHaveBeenLastCalledWith({
      name: 'relacionamentos_renovacoes',
    });
    await linhaDo(w, 110)
      .get('button[aria-label^="Conversar"]')
      .trigger('click');

    expect(useAlert.mock.calls.map(([texto]) => texto)).toEqual([
      expect.stringMatching('Abrindo a conversa com '),
    ]);
  });

  it('`?grupo=` abre a lista já no grupo; "Não renovaram" só existe quando os resultados levam até ele', async () => {
    const semPedido = await abrirSeguros();
    expect(semPedido.find('[data-grupo="nao_renovaram_30"]').exists()).toBe(
      false
    );
    aberta.unmount();

    const w = await abrirSeguros({ grupo: 'nao_renovaram_30' });
    const temporario = w.get('[data-grupo="nao_renovaram_30"]');
    expect(temporario.attributes('aria-pressed')).toBe('true');
    expect(textoDe(w, '[data-grupo="nao_renovaram_30"]')).toBe(
      'Não renovaram (últimos 30 dias) 5'
    );
    expect(textoDe(w, daCarteira('explicacao-do-grupo'))).toBe(
      'Venceram nos últimos 30 dias e não foram renovados.'
    );
    expect(w.findAll(daCarteira('linha'))).toHaveLength(5);
    aberta.unmount();

    // Um grupo que não existe cai no de sempre.
    const inventado = await abrirSeguros({ grupo: 'nao_existe' });
    expect(
      inventado.get('[data-grupo="todos"]').attributes('aria-pressed')
    ).toBe('true');
  });
});

describe('aba Seguros: marcar e mandar mensagem', () => {
  it('a barra conta os marcados e a mensagem vai por pessoa, sem repetir', async () => {
    const w = await abrirSeguros();
    await pilula(w, 'vence_30_dias').trigger('click');
    await assentar();

    await marcar(w, 110);
    await marcar(w, 107);
    await marcar(w, 104);

    expect(textoDe(w, daCarteira('barra'))).toContain('3 marcados');
    expect(w.get(daCarteira('marcar-todos')).text()).toBe(
      'Marcar todos os 17 deste grupo'
    );

    await w.get(daCarteira('mandar-mensagem')).trigger('click');
    const dialogo = textoDe(w, doBlocoA('dialogo-mensagem'));
    expect(dialogo).toContain('vão receber');
    expect(dialogo).toContain('fica de fora: está sem telefone');
  });

  it('"Marcar todos" marca o grupo inteiro; o X desmarca', async () => {
    const w = await abrirSeguros();
    await pilula(w, 'vence_7_dias').trigger('click');
    await assentar();
    await marcar(w, 110);

    await w.get(daCarteira('marcar-todos')).trigger('click');
    await assentar();
    expect(textoDe(w, daCarteira('barra'))).toContain('5 marcados');
    expect(w.find(daCarteira('marcar-todos')).exists()).toBe(false);

    await w.get(`${daCarteira('barra')} button[aria-label]`).trigger('click');
    expect(w.find(daCarteira('barra')).exists()).toBe(false);
  });
});

describe('aba Seguros: sem seguro, carregando e erro', () => {
  it('sem seguro: o herói com um botão e, embaixo, a lista de exemplo apagada', async () => {
    const w = await abrirSeguros({ demo: 'sem-seguros' });

    const exemplo = w.get(daCarteira('seguros-de-exemplo'));
    expect(exemplo.attributes('aria-hidden')).toBe('true');
    expect(exemplo.get('p').text()).toBe(
      'Sua lista de seguros vai ficar assim:'
    );
    expect(exemplo.findAll('[data-linha-de-exemplo]')).toHaveLength(5);
    // É só desenho: nada ali se clica nem se marca.
    expect(exemplo.findAll('button, a, input')).toHaveLength(0);
    expect(linhas(w)).toHaveLength(0);

    const heroi = textoDe(w, daCarteira('heroi'));
    expect(heroi).toContain('Traga os seguros da sua carteira.');
    expect(heroi).toContain('Eles aparecem aqui e na ficha de cada pessoa.');
    expect(w.get(daCarteira('heroi-acao')).text()).toBe('Trazer meus seguros');
    expect(w.find(daCarteira('heroi-trazer')).exists()).toBe(false);
    expect(w.find(daCarteira('grupos')).exists()).toBe(false);
    expect(w.find(daCarteira('busca')).exists()).toBe(false);
  });

  it('carregando: o esqueleto', async () => {
    const w = await abrirSeguros({ demo: 'carregando' });

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(w.find(daCarteira('heroi')).exists()).toBe(false);
  });

  it('erro: a frase e "Tentar de novo"', async () => {
    const w = await abrirSeguros({ demo: 'desligado' });

    const erro = w.get(daCarteira('erro'));
    expect(erro.text()).toContain(
      'Não consegui mostrar os seguros. Tente de novo.'
    );
    expect(erro.find('button').exists()).toBe(true);
  });

  it('conta de outro segmento: o endereço da aba não mostra seguro nenhum', async () => {
    const w = await abrirSeguros({ demo: 'fora-do-segmento' });

    expect(w.find(daCarteira('heroi')).exists()).toBe(false);
    expect(w.find(doBlocoA('aba-seguros')).exists()).toBe(false);
    expect(w.findAll(doBlocoA('linha')).length).toBeGreaterThan(0);
  });
});

describe('aba Pessoas em conta de seguros', () => {
  it('a linha ganha o selo do seguro mais urgente e, em renovação, quando vence', async () => {
    const w = await abrir();
    await buscarPessoa(w, 'fic-0a23');

    const linha = w.get(doBlocoA('linha'));
    expect(linha.get(daCarteira('selo-da-pessoa')).text()).toBe('Em renovação');
    expect(textoDe(w, doBlocoA('linha'))).toContain('Auto vence em 18 dias');
  });

  it('o grupo "Só tem um seguro" vem depois de "Clientes", com 84', async () => {
    const w = await abrir();

    const grupos = w
      .findAll('[data-grupo]')
      .map(p => p.attributes('data-grupo'));
    expect(grupos.indexOf('so_um_seguro')).toBe(grupos.indexOf('clientes') + 1);
    expect(pilula(w, 'so_um_seguro').text()).toContain('84');

    await pilula(w, 'so_um_seguro').trigger('click');
    await assentar();
    expect(textoDe(w, doBlocoA('explicacao-do-grupo'))).toBe(
      'Clientes com um seguro só. Boa hora para oferecer outro.'
    );
    expect(textoDe(w, doBlocoA('lista'))).toContain('de 84');
  });

  it('a busca diz que aceita placa, e a aba Seguros aparece', async () => {
    const w = await abrir();

    expect(w.getComponent(BarraDeControles).props('placeholder')).toBe(
      'Buscar por nome, telefone, documento ou placa'
    );
    expect(w.find(doBlocoA('aba-seguros')).exists()).toBe(true);

    await w.get(doBlocoA('aba-seguros')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      query: { demo: 'cheio', aba: 'seguros' },
    });
  });

  it('conta de outro segmento: a lista é a do bloco A, sem nada de seguro', async () => {
    const w = await abrir({ demo: 'fora-do-segmento' });

    expect(w.find(doBlocoA('aba-seguros')).exists()).toBe(false);
    expect(w.find(daCarteira('selo-da-pessoa')).exists()).toBe(false);
    expect(w.find('[data-grupo="so_um_seguro"]').exists()).toBe(false);
    expect(w.getComponent(BarraDeControles).props('placeholder')).toBe(
      'Buscar por nome, telefone ou documento'
    );
  });
});
