import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
import { resumoDaTela } from '../../trazer/contagem';
import { ERROS } from '../../trazer/useTrazerLista';
import { ETAPAS } from '../../trazer/etapas';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import {
  emVoo,
  erroDeNome,
  lida,
  noConferir,
  problema as problemaDaTela,
} from './apoioDaTela';
import {
  LENDO,
  PLANILHA,
  erroHttp,
  montarFonteReal,
  pagina,
  problema,
  responder,
} from './apoioDoServidor';

// #2896, Fatia 2 — as linhas que precisam da pessoa vêm em páginas. A leitura
// traz só a primeira e diz quantas há ao todo; as outras vêm a pedido ("Mostrar
// mais"), uma por vez. Nada de buscar todas em série nem de desenhar tudo.
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('./apiDeMentira')).apiDeMentira(),
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const responde = responder(TrazerAPI);
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const linhasDe = leitura => leitura.problemas.map(item => item.linha);

const lerAPrimeira = async () => {
  const montada = montarFonteReal();
  responde('enviar', LENDO);
  responde('leitura', pagina(1, [14, 37], 5));
  const leitura = await montada.fonte.ler(PLANILHA);
  return { ...montada, leitura };
};

afterEach(() => {
  vi.resetAllMocks();
  document.body.innerHTML = '';
});

describe('fonte real: a leitura traz só a primeira página', () => {
  it('pede uma página e guarda o total de problemas', async () => {
    const { leitura } = await lerAPrimeira();
    expect(TrazerAPI.leitura.mock.calls).toEqual([[812, 1]]);
    expect(linhasDe(leitura)).toEqual([14, 37]);
    expect(leitura.problemasTotal).toBe(5);
  });
});

describe('fonte real: maisProblemas', () => {
  it('busca a página seguinte e soma os problemas dela', async () => {
    const { fonte } = await lerAPrimeira();
    responde('leitura', pagina(2, [62, 143], 5));
    const segunda = await fonte.maisProblemas(812);
    expect(TrazerAPI.leitura).toHaveBeenLastCalledWith(812, 2);
    expect(linhasDe(segunda)).toEqual([14, 37, 62, 143]);
    expect(segunda.problemasTotal).toBe(5);
    responde('leitura', pagina(3, [171], 5));
    const terceira = await fonte.maisProblemas(812);
    expect(TrazerAPI.leitura).toHaveBeenLastCalledWith(812, 3);
    expect(linhasDe(terceira)).toEqual([14, 37, 62, 143, 171]);
  });

  it('não perde o que a pessoa já fez nas linhas que estavam na tela', async () => {
    const { fonte } = await lerAPrimeira();
    responde('deixarDeFora', {
      problema: problema(14, { estado: 'deixado' }),
      entram: 195,
    });
    await fonte.deixarDeFora(812, 14);
    responde('leitura', pagina(2, [62, 143], 5));
    const nova = await fonte.maisProblemas(812);
    expect(nova.problemas[0]).toEqual(problema(14, { estado: 'deixado' }));
    expect(linhasDe(nova)).toEqual([14, 37, 62, 143]);
  });

  it('a linha que já está na tela não entra duas vezes', async () => {
    const { fonte } = await lerAPrimeira();
    responde('leitura', pagina(2, [37, 62], 5));
    expect(linhasDe(await fonte.maisProblemas(812))).toEqual([14, 37, 62]);
  });

  it('a página que falha não conta: o pedido seguinte busca a mesma', async () => {
    const { fonte } = await lerAPrimeira();
    const caiu = erroHttp(500);
    TrazerAPI.leitura.mockRejectedValueOnce(caiu);
    await expect(fonte.maisProblemas(812)).rejects.toBe(caiu);
    responde('leitura', pagina(2, [62, 143], 5));
    await fonte.maisProblemas(812);
    expect(TrazerAPI.leitura).toHaveBeenLastCalledWith(812, 2);
  });

  it('404: a leitura já foi trazida (LEITURA_NAO_ENCONTRADA)', async () => {
    const { fonte } = await lerAPrimeira();
    TrazerAPI.leitura.mockRejectedValueOnce(erroHttp(404));
    await expect(fonte.maisProblemas(812)).rejects.toMatchObject({
      name: 'LEITURA_NAO_ENCONTRADA',
    });
  });

  it('a planilha está sendo lida de novo: TELA_DESATUALIZADA', async () => {
    const { fonte } = await lerAPrimeira();
    responde('leitura', LENDO);
    await expect(fonte.maisProblemas(812)).rejects.toMatchObject({
      name: 'TELA_DESATUALIZADA',
    });
  });

  it('depois de a leitura voltar inteira de uma escrita, recomeça da segunda página', async () => {
    const { fonte } = await lerAPrimeira();
    responde('leitura', pagina(2, [62, 143], 5));
    await fonte.maisProblemas(812);
    responde('trocarColuna', pagina(1, [14, 37], 5));
    const trocada = await fonte.trocarDestino(812, 6, 'nao_guardar');
    expect(linhasDe(trocada)).toEqual([14, 37]);
    responde('leitura', pagina(2, [62, 143], 5));
    await fonte.maisProblemas(812);
    expect(TrazerAPI.leitura).toHaveBeenLastCalledWith(812, 2);
  });
});

describe('a demonstração tem os mesmos métodos', () => {
  const montar = () =>
    trazerFonte({
      demo: 'cheio',
      carregarDemo: () => import('../../demo/trazer.js'),
      atraso: 0,
      atrasoDaLeitura: 0,
    });

  beforeEach(() => esquecerMemoriaDaDemo());

  it('a leitura de exemplo já vem com todos os problemas e diz o total', async () => {
    const leitura = await montar().ler({ name: 'a.xlsx' });
    expect(leitura.problemasTotal).toBe(leitura.problemas.length);
  });

  it('maisProblemas devolve a mesma leitura (não há mais o que buscar)', async () => {
    const fonte = montar();
    const leitura = await fonte.ler({ name: 'a.xlsx' });
    expect(await fonte.maisProblemas(leitura.id)).toEqual(leitura);
  });

  it('retomar devolve a leitura guardada; a que não existe é LEITURA_NAO_ENCONTRADA', async () => {
    const fonte = montar();
    const leitura = await fonte.ler({ name: 'a.xlsx' });
    await fonte.deixarDeFora(leitura.id, 14);
    const retomada = await fonte.retomar(leitura.id);
    expect(retomada.problemas[0].estado).toBe('deixado');
    expect(retomada).not.toHaveProperty('situacao');
    await expect(fonte.retomar('leitura-999')).rejects.toMatchObject({
      name: 'LEITURA_NAO_ENCONTRADA',
    });
  });

  // Como o servidor: a troca que muda quem é o telefone, o e-mail, o nome ou
  // a empresa faz ler a planilha de novo, e a resposta é o marcador; a que só
  // mexe numa informação devolve a leitura (specs/trazer/demonstracaoColunas).
  it('trocar a coluna devolve o marcador `lendo` só quando o servidor leria de novo', async () => {
    const fonte = montar();
    const { id } = await fonte.ler({ name: 'a.xlsx' });
    const informacao = await fonte.trocarDestino(id, 6, 'nao_guardar');
    expect(informacao).not.toHaveProperty('situacao');
    expect(await fonte.trocarDestino(id, 1, 'nao_guardar')).toEqual({
      situacao: 'lendo',
      id,
    });
  });
});

// ---- a tela ------------------------------------------------------------------

const DUAS_DE_CINCO = lida({
  problemas: [problemaDaTela(14), problemaDaTela(37)],
  problemasTotal: 5,
});
const QUATRO_DE_CINCO = lida({
  problemas: [14, 37, 62, 143].map(linha => problemaDaTela(linha)),
  problemasTotal: 5,
});

describe('o estado busca mais problemas a pedido', () => {
  it('diz quantos faltam e usa a leitura que a fonte devolve', async () => {
    const { tela, fonte } = await noConferir(DUAS_DE_CINCO, {
      maisProblemas: vi.fn().mockResolvedValue(QUATRO_DE_CINCO),
    });
    expect(tela.faltamCarregar.value).toBe(3);
    expect(fonte.maisProblemas).not.toHaveBeenCalled();
    await tela.mostrarMais();
    expect(fonte.maisProblemas).toHaveBeenCalledWith('l1');
    expect(tela.leitura.value).toEqual(QUATRO_DE_CINCO);
    expect(tela.faltamCarregar.value).toBe(1);
  });

  it('as linhas que ainda não vieram contam como abertas no topo', async () => {
    const { tela } = await noConferir(
      lida({
        problemas: [
          problemaDaTela(14, { estado: 'deixado' }),
          problemaDaTela(37),
        ],
        problemasTotal: 5,
      })
    );
    expect(tela.resumo.value.precisamDeVoce).toBe(4);
    expect(tela.resumo.value.deixadas).toBe(1);
  });

  it('fica "carregando mais" enquanto busca, e o segundo pedido não vai', async () => {
    const pedido = emVoo();
    const { tela, fonte } = await noConferir(DUAS_DE_CINCO, {
      maisProblemas: vi.fn(() => pedido.promessa),
    });
    const primeiro = tela.mostrarMais();
    expect(tela.carregandoMais.value).toBe(true);
    const segundo = tela.mostrarMais();
    pedido.resolver(QUATRO_DE_CINCO);
    await Promise.all([primeiro, segundo]);
    expect(fonte.maisProblemas).toHaveBeenCalledTimes(1);
    expect(tela.carregandoMais.value).toBe(false);
  });

  it('a busca que falha fica marcada; a seguinte que dá certo desmarca', async () => {
    const { tela, avisar } = await noConferir(DUAS_DE_CINCO, {
      maisProblemas: vi
        .fn()
        .mockRejectedValueOnce(new Error('caiu'))
        .mockResolvedValueOnce(QUATRO_DE_CINCO),
    });
    await tela.mostrarMais();
    expect(tela.erroDoMais.value).toBe(true);
    expect(tela.leitura.value).toEqual(DUAS_DE_CINCO);
    expect(avisar).not.toHaveBeenCalled();
    await tela.mostrarMais();
    expect(tela.erroDoMais.value).toBe(false);
  });

  it('a leitura que já foi trazida volta ao Enviar', async () => {
    const { tela } = await noConferir(DUAS_DE_CINCO, {
      maisProblemas: vi
        .fn()
        .mockRejectedValue(erroDeNome('LEITURA_NAO_ENCONTRADA')),
    });
    await tela.mostrarMais();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.erro.value).toBe(ERROS.JA_TRAZIDA);
  });

  it('a leitura que mudou no servidor é lida de novo', async () => {
    const { tela, fonte } = await noConferir(DUAS_DE_CINCO, {
      maisProblemas: vi
        .fn()
        .mockRejectedValue(erroDeNome('TELA_DESATUALIZADA')),
      retomar: vi.fn().mockResolvedValue(lida()),
    });
    await tela.mostrarMais();
    expect(fonte.retomar).toHaveBeenCalledWith('l1');
    expect(tela.mudou.value).toBe(true);
  });
});

describe('"Precisam de você": Mostrar mais', () => {
  const montar = (props = {}) =>
    mount(PrecisamDeVoce, {
      attachTo: document.body,
      props: { problemas: DUAS_DE_CINCO.problemas, ...props },
    });

  it('sem nada por carregar, não há botão', () => {
    expect(marca(montar(), 'mostrar-mais').exists()).toBe(false);
  });

  it('com linhas por carregar: o botão, com 44 px, e o título conta todas', async () => {
    const w = montar({ faltamCarregar: 3 });
    const mais = marca(w, 'mostrar-mais');
    expect(mais.text()).toBe('Mostrar mais');
    expect(mais.classes()).toContain('min-h-11');
    expect(marca(w, 'precisam-titulo').text()).toBe('Precisam de você (5)');
    await mais.trigger('click');
    expect(w.emitted('mostrarMais')).toHaveLength(1);
  });

  it('só desenha as linhas que já vieram', () => {
    expect(montar({ faltamCarregar: 3 }).findAll('[data-linha]')).toHaveLength(
      2
    );
  });

  it('buscando: o botão fica carregando', () => {
    const w = montar({ faltamCarregar: 3, carregandoMais: true });
    expect(
      w
        .findComponent('[data-relacionamentos="mostrar-mais"]')
        .props('isLoading')
    ).toBe(true);
  });

  it('a busca que falhou é dita como alerta, junto do botão', () => {
    const w = montar({ faltamCarregar: 3, erroDoMais: true });
    const alerta = marca(w, 'erro-do-mais');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe('Não consegui mostrar mais. Tente de novo.');
  });

  const temOFoco = (w, linha) =>
    w.get(`[data-linha="${linha}"]`).element.contains(document.activeElement);

  it('chegaram as linhas que a pessoa pediu: o foco vai para a primeira nova', async () => {
    const w = montar({ faltamCarregar: 3 });
    await marca(w, 'mostrar-mais').trigger('click');
    await w.setProps({
      problemas: QUATRO_DE_CINCO.problemas,
      faltamCarregar: 1,
    });
    await flushPromises();
    expect(temOFoco(w, 62)).toBe(true);
  });

  it('linhas novas que a pessoa não pediu (a lista foi lida de novo) não roubam o foco', async () => {
    const w = montar({ faltamCarregar: 3 });
    await w.setProps({
      problemas: QUATRO_DE_CINCO.problemas,
      faltamCarregar: 1,
    });
    await flushPromises();
    expect(temOFoco(w, 62)).toBe(false);
  });

  it('com tudo resolvido entre as que vieram e outras por carregar, não diz "Tudo resolvido"', () => {
    const w = montar({
      problemas: [problemaDaTela(14, { estado: 'deixado' })],
      faltamCarregar: 2,
    });
    expect(marca(w, 'precisam-titulo').text()).toBe('Precisam de você (2)');
  });
});

describe('Conferir: os números vêm do servidor', () => {
  const conferir = (leitura, props = {}) =>
    mount(TelaConferir, {
      attachTo: document.body,
      props: {
        leitura,
        resumo: resumoDaTela(leitura),
        total: resumoDaTela(leitura).entram,
        ...props,
      },
    });

  it('o botão de trazer diz o `entram` da leitura', () => {
    const w = conferir(DUAS_DE_CINCO);
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
  });

  it('repassa o pedido de "Mostrar mais"', async () => {
    const w = conferir(DUAS_DE_CINCO, { faltamCarregar: 3 });
    await marca(w, 'mostrar-mais').trigger('click');
    expect(w.emitted('mostrarMais')).toHaveLength(1);
  });

  it('o contador "precisam de você" conta as que ainda não vieram', () => {
    const w = conferir(DUAS_DE_CINCO, { faltamCarregar: 3 });
    expect(w.get('[data-contador="PRECISAM"]').text()).toContain('5');
  });
});
