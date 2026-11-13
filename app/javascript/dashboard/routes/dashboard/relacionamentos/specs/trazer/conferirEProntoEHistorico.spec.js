import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  leituraDeExemplo,
  aplicarConserto,
  aplicarDeixarDeFora,
} from '../../demo/trazer';
import { resumoDaTela } from '../../trazer/contagem';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import FichaDeExemplo from '../../components/trazer/FichaDeExemplo.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
import TelaPronto from '../../components/trazer/TelaPronto.vue';
import HistoricoDeListas from '../../components/trazer/HistoricoDeListas.vue';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';
import { tudoResolvido } from './apoioDaDemo';

// Conferir, Pronto, histórico e o diálogo de Desfazer (#2894), com o texto real em pt_BR.
withFullI18n('pt_BR');

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

const DIA = 24 * 60 * 60 * 1000;
const AGORA = Date.UTC(2026, 10, 11, 15);
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const contador = (w, chave) =>
  w.get(`[data-contador="${chave}"] .sr-only`).text();
const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);
const problemaDe = (leitura, linha) =>
  leitura.problemas.find(p => p.linha === linha);

const conferir = (leitura, extra = {}) =>
  mount(TelaConferir, {
    props: {
      leitura,
      resumo: resumoDaTela(leitura),
      total: resumoDaTela(leitura).entram,
      ...extra,
    },
  });

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

describe('FichaDeExemplo', () => {
  const pessoa = {
    nome: 'Marina Esteveira',
    telefone: '+55 11 94271-0003',
    email: 'marina.esteveira@exemplo.com.br',
    empresa: 'Casa Aurora',
    cliente: true,
  };

  it('mostra nome, telefone, e-mail, empresa e o selo Cliente', () => {
    const w = mount(FichaDeExemplo, { props: { pessoa } });
    expect(w.text()).toContain('Marina Esteveira');
    expect(w.text()).toContain('+55 11 94271-0003');
    expect(w.text()).toContain('marina.esteveira@exemplo.com.br');
    expect(w.text()).toContain('Casa Aurora');
    expect(w.get('[data-selo="cliente"]').text()).toBe('Cliente');
  });

  it('sem empresa e sem ser cliente, não desenha a linha nem o selo', () => {
    const w = mount(FichaDeExemplo, {
      props: { pessoa: { ...pessoa, empresa: '', cliente: false } },
    });
    expect(w.find('.i-lucide-building-2').exists()).toBe(false);
    expect(w.find('[data-selo]').exists()).toBe(false);
  });
});

describe('ProblemaDaLinha', () => {
  const leitura = leituraDeExemplo('l1');
  const montar = linha =>
    mount(ProblemaDaLinha, { props: { problema: problemaDe(leitura, linha) } });

  it.each([
    [
      14,
      'Tadeu Imbirussu: este telefone não parece um celular. Confira os dígitos e o DDD: o DDD precisa estar junto do número, na mesma coluna.',
    ],
    [37, 'Rita Carvalhedo: este e-mail não parece certo.'],
    [62, '(11) 95412-0062: falta o nome'],
    [143, 'Paulo Hortêncio aparece duas vezes. Qual fica?'],
    [171, 'Helena Ourivesco: não tem telefone nem e-mail'],
  ])('a linha %s diz o problema em palavras simples', (linha, frase) => {
    expect(montar(linha).text()).toContain(frase);
  });

  // A tela só trava o campo vazio: o formato quem confere é o servidor.
  it('e-mail: Salvar só não salva o campo vazio; o que a pessoa escreveu sai com a linha, sem espaço nas pontas', async () => {
    const w = montar(37);
    expect(botao(w, 'Salvar').attributes('disabled')).toBeUndefined();
    await w.get('input').setValue('');
    await w.get('form').trigger('submit');
    expect(w.get('[role="alert"]').text()).toBe(
      'Escreva o e-mail para salvar.'
    );
    expect(w.emitted('guardar')).toBeUndefined();
    await w.get('input').setValue('rita@exemplo');
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await w.get('form').trigger('submit');
    await w.get('input').setValue(' rita.carvalhedo@exemplo.com.br ');
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')).toEqual([
      [37, 'rita@exemplo'],
      [37, 'rita.carvalhedo@exemplo.com.br'],
    ]);
  });

  it('nome: Salvar só com algum texto; vazio diz o que falta', async () => {
    const w = montar(62);
    expect(botao(w, 'Salvar').attributes('disabled')).toBeUndefined();
    await w.get('input').setValue('');
    await w.get('form').trigger('submit');
    expect(w.get('[role="alert"]').text()).toBe('Escreva o nome para salvar.');
    expect(w.get('input').attributes('aria-invalid')).toBe('true');
    expect(w.get('input').attributes('aria-describedby')).toBe(
      w.get('[role="alert"]').attributes('id')
    );
    expect(w.emitted('guardar')).toBeUndefined();
    await w.get('input').setValue('Ana Brandolim');
    await botao(w, 'Salvar').trigger('click');
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')[0]).toEqual([62, 'Ana Brandolim']);
  });

  it('telefone: usa o campo de telefone e Salvar, ligado, pede para corrigir o número em que a pessoa não mexeu', async () => {
    const w = montar(14);
    expect(w.text()).toContain('Telefone certo');
    expect(w.findComponent(CampoDeTelefone).exists()).toBe(true);
    expect(botao(w, 'Salvar').attributes('disabled')).toBeUndefined();
    await w.get('form').trigger('submit');
    expect(w.get('[role="alert"]').text()).toBe(
      'Corrija o telefone para salvar.'
    );
    expect(w.emitted('guardar')).toBeUndefined();
  });

  it('duplicada: escolhe qual linha fica, sem campo de texto', async () => {
    const w = montar(143);
    expect(w.find('input').exists()).toBe(false);
    expect(botao(w, 'Salvar')).toBeUndefined();
    // O nome acessível é o conteúdo do cartão, que diz o que distingue a linha.
    expect(w.get('[data-opcao="88"]').attributes('aria-label')).toBeUndefined();
    expect(w.get('[data-opcao="88"]').text()).toContain('Linha 88 da planilha');
    await w.get('[data-opcao="88"]').trigger('click');
    await w.get('[data-opcao="143"]').trigger('click');
    expect(w.emitted('guardar')).toEqual([
      [143, 88],
      [143, 143],
    ]);
  });

  // #2896 — o servidor pode não saber qual é a outra linha (planilha já
  // apagada, ou caso raro): a linha diz o problema, sem a comparação.
  it('duplicada sem a outra linha: diz o problema, sem escolha, e dá para deixar de fora', async () => {
    const w = mount(ProblemaDaLinha, {
      props: {
        problema: {
          linha: 7,
          tipo: 'duplicada',
          nome: 'Ana Repetida',
          valor: '11987650001',
          estado: 'aberto',
          outraLinha: null,
          duplicadas: [],
        },
      },
    });
    expect(w.text()).toContain('Ana Repetida aparece duas vezes.');
    expect(w.text()).not.toContain('Qual fica?');
    expect(w.text()).toContain('Linha 7 da planilha');
    expect(w.text()).not.toContain('null');
    expect(w.find('[data-opcao]').exists()).toBe(false);
    expect(w.find('input').exists()).toBe(false);
    expect(botao(w, 'Salvar')).toBeUndefined();
    await marca(w, 'deixar-de-fora').trigger('click');
    expect(w.emitted('deixarDeFora')).toEqual([[7]]);
  });

  it('Deixar de fora emite a linha, em todo tipo de problema', async () => {
    const w = montar(171);
    const deixar = marca(w, 'deixar-de-fora');
    expect(deixar.text()).toBe('Deixar de fora');
    await deixar.trigger('click');
    expect(w.emitted('deixarDeFora')).toEqual([[171]]);
  });

  it('consertada vira "Pronto" e deixada de fora vira "Deixada de fora", só com Voltar atrás', () => {
    const guardada = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(aplicarConserto(leitura, 62, 'Ana'), 62) },
    });
    expect(guardada.text()).toContain('Pronto');
    expect(guardada.findAll('button').map(b => b.text())).toEqual([
      'Voltar atrás',
    ]);
    const deixada = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(aplicarDeixarDeFora(leitura, 62), 62) },
    });
    expect(deixada.text()).toContain('Deixada de fora');
    expect(deixada.findAll('button').map(b => b.text())).toEqual([
      'Voltar atrás',
    ]);
  });
});

describe('OQueVouGuardar', () => {
  const colunas = leituraDeExemplo('l1').colunas;
  const montar = () => mount(OQueVouGuardar, { props: { colunas } });

  it('vem recolhido e abre com um clique', async () => {
    const w = montar();
    const abrir = w.get('h2 button');
    expect(abrir.text()).toBe('O que vou guardar');
    expect(abrir.attributes('aria-expanded')).toBe('false');
    expect(w.get('ul').attributes('style')).toContain('display: none');
    await abrir.trigger('click');
    expect(abrir.attributes('aria-expanded')).toBe('true');
    expect(w.get('ul').attributes('style') || '').not.toContain(
      'display: none'
    );
  });

  it('mostra para onde cada coluna vai e o que é desconhecido vira informação', () => {
    const w = montar();
    expect(w.get('[data-coluna="Cel"]').text()).toContain(
      '“Cel” fica como Telefone.'
    );
    expect(w.get('[data-coluna="Aniversário"]').text()).toContain(
      '“Aniversário” fica como informação nova.'
    );
  });

  // #2896 — no servidor quem identifica a coluna é o índice: o nome pode
  // repetir ou vir vazio.
  it('coluna com índice emite o índice, e nome repetido não some da lista', async () => {
    const w = mount(OQueVouGuardar, {
      props: {
        colunas: [
          { indice: 0, nome: 'Telefone', destino: 'telefone' },
          { indice: 3, nome: 'Telefone', destino: 'informacao' },
        ],
      },
    });
    const linhas = w.findAll('[data-coluna]');
    expect(linhas).toHaveLength(2);
    const naoGuardar = linhas[1]
      .findAll('button')
      .find(b => b.text() === 'Não guardar');
    await naoGuardar.trigger('click');
    expect(w.emitted('trocar')).toEqual([[3, 'nao_guardar']]);
  });

  it('coluna sem nome aparece pela posição dela na planilha', () => {
    const w = mount(OQueVouGuardar, {
      props: { colunas: [{ indice: 4, nome: '', destino: 'informacao' }] },
    });
    expect(w.get('[data-coluna]').text()).toContain(
      '“Coluna 5” fica como informação nova.'
    );
  });

  it('coluna desconhecida tem Não guardar, que emite a troca', async () => {
    const w = montar();
    const linha = w.get('[data-coluna="Aniversário"]');
    const naoGuardar = linha
      .findAll('button')
      .find(b => b.text() === 'Não guardar');
    await naoGuardar.trigger('click');
    // Quem identifica a coluna é o índice dela na planilha.
    expect(w.emitted('trocar')).toEqual([[6, 'nao_guardar']]);
  });

  it('Trocar abre a escolha de destino em palavras simples (sem select nativo)', async () => {
    const w = montar();
    const linha = w.get('[data-coluna="Cel"]');
    await linha
      .findAll('button')
      .find(b => b.text() === 'Mudar')
      .trigger('click');
    expect(linha.find('select').exists()).toBe(false);
    const escolha = linha.get(
      'button[aria-label="Para onde vai a coluna “Cel”"]'
    );
    expect(escolha.text()).toContain('Telefone');
  });

  it('coluna que não vai ser guardada diz isso', () => {
    const w = mount(OQueVouGuardar, {
      props: {
        colunas: [{ indice: 5, nome: 'Aniversário', destino: 'nao_guardar' }],
      },
    });
    expect(w.text()).toContain('Não vou guardar “Aniversário”');
  });
});

describe('TelaConferir', () => {
  it('a frase forte tem os números certos, no plural', () => {
    const w = conferir(leituraDeExemplo('l1'));
    expect(w.get('h1').text()).toBe('Achei 203 pessoas.');
    expect(contador(w, 'NOVAS')).toBe('180 novas');
    expect(contador(w, 'COMPLETADAS')).toBe('15 já estavam aqui');
    expect(contador(w, 'PRECISAM')).toBe('8 precisam de você');
  });

  it('a frase usa o singular quando é 1', () => {
    const base = leituraDeExemplo('l1');
    const leitura = {
      ...base,
      resumo: { total: 1, novas: 1, completadas: 0, comProblema: 0 },
      problemas: [],
    };
    const um1 = conferir(leitura);
    expect(um1.get('h1').text()).toBe('Achei 1 pessoa.');
    expect(contador(um1, 'NOVAS')).toBe('1 nova');
    expect(um1.find('[data-contador="COMPLETADAS"]').exists()).toBe(false);
    const um = {
      ...base,
      resumo: { total: 3, novas: 1, completadas: 1, comProblema: 1 },
    };
    const tres = conferir(um);
    expect(tres.get('h1').text()).toBe('Achei 3 pessoas.');
    expect(contador(tres, 'COMPLETADAS')).toBe('1 já estava aqui');
    expect(contador(tres, 'PRECISAM')).toBe('8 precisam de você');
  });

  it('a ordem é: frase, três fichas, precisam de você, o que vou guardar, botão', () => {
    const w = conferir(leituraDeExemplo('l1'));
    expect(w.findAll('[data-ficha-de-exemplo]')).toHaveLength(3);
    const ordem = [
      'h1',
      '[data-ficha-de-exemplo]',
      '[data-relacionamentos="precisam-de-voce"]',
      '[data-relacionamentos="o-que-vou-guardar"]',
      '[data-relacionamentos="trazer-confirmar"]',
    ].map(seletor => w.get(seletor).element);
    // Posição de cada bloco na página: tem de crescer na ordem pedida.
    const todos = [...w.element.querySelectorAll('*')];
    const posicoes = ordem.map(elemento => todos.indexOf(elemento));
    expect(posicoes).toEqual([...posicoes].sort((a, b) => a - b));
  });

  it('sem o Desfazer na conta, o Conferir não promete desfazer', () => {
    const w = conferir(leituraDeExemplo('l1'));
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
    expect(w.text()).not.toContain('desfazer');
  });

  it('o botão único diz quantas pessoas vão chegar', () => {
    const w = conferir(leituraDeExemplo('l1'), { temDesfazer: true });
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
    expect(w.text()).toContain('Você pode desfazer quando quiser.');
    expect(w.text()).toContain('Precisam de você (8)');
  });

  // "Novas" é do servidor: a tela não chama de nova a linha consertada (não
  // sabe se a pessoa já existe). O que muda é quem precisa da pessoa e o botão.
  it('consertou: os que precisam de você, o título e o botão mudam na hora e a linha vira Pronto', () => {
    const leitura = aplicarConserto(
      leituraDeExemplo('l1'),
      62,
      'Ana Brandolim'
    );
    const w = conferir(leitura);
    expect(contador(w, 'NOVAS')).toBe('180 novas');
    expect(contador(w, 'PRECISAM')).toBe('7 precisam de você');
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 196 pessoas');
    expect(w.text()).toContain('Precisam de você (7)');
    expect(w.get('[data-linha="62"]').text()).toContain('Pronto');
  });

  it('deixou de fora: a frase ganha "ficou de fora" e o botão não muda', () => {
    const leitura = aplicarDeixarDeFora(leituraDeExemplo('l1'), 62);
    const w = conferir(leitura);
    expect(contador(w, 'DEIXADAS')).toBe('1 ficou de fora');
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
  });

  it('tudo resolvido troca o título da lista de problemas', () => {
    const w = conferir(tudoResolvido(leituraDeExemplo('l1')));
    expect(w.text()).toContain('Tudo resolvido');
    // A linha repetida (143) é troca: ela fica e a outra, que já estava
    // contada, sai. Das 8 linhas, 5 somam uma pessoa; a outra repetida e a da
    // fórmula ficam de fora.
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 200 pessoas');
  });

  it('sem problemas não mostra a lista "Precisam de você"', () => {
    const leitura = { ...leituraDeExemplo('l1'), problemas: [] };
    expect(marca(conferir(leitura), 'precisam-de-voce').exists()).toBe(false);
  });

  it('Trazer emite "trazer" e Voltar emite "voltar"', async () => {
    const w = conferir(leituraDeExemplo('l1'));
    await marca(w, 'trazer-confirmar').trigger('click');
    await botao(w, 'Voltar').trigger('click');
    expect(w.emitted('trazer')).toHaveLength(1);
    expect(w.emitted('voltar')).toHaveLength(1);
  });

  it('com 0 pessoas o botão principal vira "Escolher outra planilha" e a frase diz que não sobrou ninguém', async () => {
    const base = leituraDeExemplo('l1');
    const leitura = {
      ...base,
      resumo: { total: 0, novas: 0, completadas: 0, comProblema: 0 },
      problemas: [],
    };
    const w = conferir(leitura);
    expect(marca(w, 'trazer-confirmar').exists()).toBe(false);
    expect(marca(w, 'ninguem-para-trazer').text()).toBe(
      'Não sobrou ninguém para trazer.'
    );
    const outra = marca(w, 'escolher-outra');
    expect(outra.text()).toBe('Escolher outra planilha');
    expect(outra.attributes('disabled')).toBeUndefined();
    await outra.trigger('click');
    expect(w.emitted('escolherOutra')).toHaveLength(1);
  });

  it('erro ao trazer: frase e botão que emite "tentar"', async () => {
    const w = conferir(leituraDeExemplo('l1'), { comErro: true });
    const erro = marca(w, 'erro');
    expect(erro.text()).toContain('Não consegui trazer a lista.');
    await erro.get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it('escrita em andamento desabilita o que escreve', () => {
    const w = conferir(leituraDeExemplo('l1'), { ocupado: true });
    expect(marca(w, 'trazer-confirmar').attributes('disabled')).toBeDefined();
    expect(marca(w, 'deixar-de-fora').attributes('disabled')).toBeDefined();
  });

  it('repassa o conserto, o deixar de fora e a troca de destino', async () => {
    const w = conferir(leituraDeExemplo('l1'));
    await w
      .getComponent(ProblemaDaLinha)
      .vm.$emit('guardar', 14, '+5511973800014');
    await w.getComponent(ProblemaDaLinha).vm.$emit('deixarDeFora', 14);
    await w.getComponent(OQueVouGuardar).vm.$emit('trocar', 'Cel', 'telefone');
    expect(w.emitted('guardar')).toEqual([[14, '+5511973800014']]);
    expect(w.emitted('deixarDeFora')).toEqual([[14]]);
    expect(w.emitted('trocar')).toEqual([['Cel', 'telefone']]);
  });
});

// #2896 — a planilha original fica guardada por poucos dias. Depois disso o
// servidor manda os valores mascarados: dá para ver o problema e deixar a linha
// de fora, mas não para consertar.
describe('Conferir com a planilha já apagada (valores mascarados)', () => {
  const FRASE =
    'A planilha já foi apagada daqui. Para corrigir uma linha, envie a planilha de novo.';
  const apagada = () => ({ ...leituraDeExemplo('l1'), valores: 'mascarados' });

  it('diz uma vez, no topo dos problemas, que a planilha já foi apagada', () => {
    const w = conferir(apagada());
    const aviso = w.findAll('[data-relacionamentos="planilha-apagada"]');
    expect(aviso).toHaveLength(1);
    expect(aviso[0].text()).toBe(FRASE);
    // Antes da lista dos problemas: na ordem do documento o aviso vem primeiro.
    const naOrdem = marca(w, 'precisam-de-voce')
      .findAll('[data-relacionamentos="planilha-apagada"], ul')
      .map(peca => peca.element.tagName);
    expect(naOrdem).toEqual(['P', 'UL']);
  });

  it('nenhuma linha tem campo, Salvar nem "Ficar com esta": a ação não existe ali', () => {
    const w = conferir(apagada());
    const problemas = marca(w, 'precisam-de-voce');
    expect(problemas.findAll('[data-linha]')).toHaveLength(8);
    expect(problemas.find('input').exists()).toBe(false);
    expect(problemas.findComponent(CampoDeTelefone).exists()).toBe(false);
    expect(problemas.find('[data-opcao]').exists()).toBe(false);
    expect(
      problemas.findAll('button').filter(b => b.text() === 'Salvar')
    ).toHaveLength(0);
    expect(problemas.find('button[disabled]').exists()).toBe(false);
  });

  it('"Deixar de fora" continua em todas as linhas e emite a linha', async () => {
    const w = conferir(apagada());
    const deixar = w.findAll('[data-relacionamentos="deixar-de-fora"]');
    expect(deixar).toHaveLength(8);
    await deixar[0].trigger('click');
    expect(w.emitted('deixarDeFora')).toEqual([[14]]);
  });

  it('a linha continua dizendo o problema em palavras simples', () => {
    const w = conferir(apagada());
    expect(w.get('[data-linha="14"]').text()).toContain(
      'Tadeu Imbirussu: este telefone não parece um celular. Confira os dígitos e o DDD: o DDD precisa estar junto do número, na mesma coluna.'
    );
  });

  it('com a planilha guardada (valores inteiros) não há a frase e o conserto existe', () => {
    const w = conferir({ ...leituraDeExemplo('l1'), valores: 'inteiros' });
    expect(marca(w, 'planilha-apagada').exists()).toBe(false);
    expect(w.get('[data-linha="37"]').find('input').exists()).toBe(true);
    expect(botao(w.get('[data-linha="37"]'), 'Salvar')).toBeTruthy();
  });
});

describe('TelaPronto', () => {
  it('andamento: barra com role progressbar, a frase e onde a lista vai aparecer', () => {
    const w = mount(TelaPronto, {
      props: { trazendo: true, porcentagem: 40 },
    });
    const andamento = marca(w, 'andamento');
    expect(w.get('h1').text()).toBe('Trazendo… 40%.');
    expect(andamento.text()).toContain(
      'Pode sair desta tela. A lista aparece aqui embaixo quando terminar.'
    );
    const barra = w.get('[role="progressbar"]');
    expect(barra.attributes('aria-valuenow')).toBe('40');
    expect(barra.attributes('aria-valuemin')).toBe('0');
    expect(barra.attributes('aria-valuemax')).toBe('100');
    expect(barra.get('div').classes()).toContain('w-[40%]');
    expect(marca(w, 'pronto').exists()).toBe(false);
  });

  it('andamento com erro mostra a frase e o botão que emite "tentar"', async () => {
    const w = mount(TelaPronto, { props: { trazendo: true, comErro: true } });
    const erro = marca(w, 'erro');
    expect(erro.text()).toContain('Não consegui ver como está indo.');
    await erro.get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it('pronto: "180 pessoas chegaram e 15 foram completadas." com a ação principal e a discreta', async () => {
    const w = mount(TelaPronto, {
      props: { trazendo: false, novas: 180, completadas: 15 },
    });
    expect(w.get('[role="heading"]').text()).toBe(
      '180 pessoas chegaram e 15 foram completadas.'
    );
    expect(w.get('[role="heading"]').attributes('aria-level')).toBe('1');
    const ver = marca(w, 'ver-as-pessoas');
    expect(ver.text()).toBe('Ver as pessoas');
    await ver.trigger('click');
    expect(w.emitted('ver')).toHaveLength(1);
    await botao(w, 'Trazer outra lista').trigger('click');
    expect(w.emitted('outra')).toHaveLength(1);
    expect(marca(w, 'andamento').exists()).toBe(false);
  });

  const fraseDoPronto = props =>
    mount(TelaPronto, { props }).get('[role="heading"]').text();

  it('diz a verdade: só novas, só completadas, singular e plural', () => {
    expect(fraseDoPronto({ novas: 180, completadas: 0 })).toBe(
      '180 pessoas chegaram.'
    );
    expect(fraseDoPronto({ novas: 0, completadas: 15 })).toBe(
      '15 pessoas foram completadas.'
    );
    expect(fraseDoPronto({ novas: 1, completadas: 0 })).toBe(
      '1 pessoa chegou.'
    );
    expect(fraseDoPronto({ novas: 0, completadas: 1 })).toBe(
      '1 pessoa foi completada.'
    );
    expect(fraseDoPronto({ novas: 1, completadas: 1 })).toBe(
      '1 pessoa chegou e 1 foi completada.'
    );
  });
});

describe('HistoricoDeListas', () => {
  const lista = (id, situacao, extra = {}) => ({
    id,
    arquivo: `${id}.xlsx`,
    quando: AGORA - 3 * DIA,
    quem: 'Marina Dornelaz',
    total: 195,
    situacao,
    porcentagem: 100,
    ...extra,
  });
  const montar = props =>
    mount(HistoricoDeListas, {
      props: { listas: [], temDesfazer: true, ...props },
    });

  it('cheio: arquivo, quando, quem, pessoas, situação e Desfazer, sem data limite', () => {
    const w = montar({ listas: [lista('Clientes 2025', 'pronto')] });
    const linha = w.get('[data-lista="Clientes 2025"]');
    expect(linha.text()).toContain('Clientes 2025.xlsx');
    expect(linha.text()).toContain('em 08/11');
    expect(linha.text()).toContain('por Marina Dornelaz');
    expect(linha.text()).toContain('195 pessoas');
    expect(linha.get('[data-situacao]').text()).toBe('Pronto');
    expect(linha.text()).not.toContain('até');
    expect(marca(w, 'desfazer').text()).toBe('Desfazer');
    expect(marca(w, 'desfazer').attributes('aria-label')).toBe(
      'Desfazer a lista Clientes 2025.xlsx'
    );
  });

  it('sem o nome de quem trouxe, a linha não diz "por"', () => {
    const w = montar({ listas: [lista('a', 'pronto', { quem: '' })] });
    const texto = w.get('[data-lista="a"]').text();
    expect(texto).toContain('em 08/11');
    expect(texto).toContain('195 pessoas');
    expect(texto).not.toContain('por');
  });

  it('Desfazer emite a lista', async () => {
    const pronta = lista('a', 'pronto');
    const w = montar({ listas: [pronta] });
    await marca(w, 'desfazer').trigger('click');
    expect(w.emitted('desfazer')).toEqual([[pronta]]);
  });

  it('desfeita mostra "Desfeito" e não tem botão', () => {
    const w = montar({ listas: [lista('a', 'desfeito')] });
    expect(w.get('[data-situacao]').text()).toBe('Desfeito');
    expect(marca(w, 'desfazer').exists()).toBe(false);
  });

  it('trazendo mostra a porcentagem e não tem botão', () => {
    const w = montar({ listas: [lista('a', 'trazendo', { porcentagem: 40 })] });
    expect(w.get('[data-situacao]').text()).toBe('Trazendo 40%');
    expect(marca(w, 'desfazer').exists()).toBe(false);
  });

  it('lista pronta antiga tem Desfazer sempre, sem prazo nem data', () => {
    const w = montar({
      listas: [lista('a', 'pronto', { quando: AGORA - 400 * DIA })],
    });
    expect(marca(w, 'desfazer').exists()).toBe(true);
    expect(w.text()).not.toContain('Prazo');
    expect(w.text()).not.toContain('até');
  });

  // #2896 — a lista que parou no meio.
  it('falhou e dá para continuar: a frase e o botão "Tentar de novo", que emite a lista', async () => {
    const parada = lista('a', 'falhou', { podeTentar: true, porcentagem: 40 });
    const w = montar({ listas: [parada] });
    expect(w.get('[data-situacao="falhou"]').text()).toBe(
      'Não consegui trazer esta lista.'
    );
    const tentar = marca(w, 'tentar-de-novo');
    expect(tentar.text()).toBe('Tentar de novo');
    expect(tentar.attributes('aria-label')).toBe(
      'Tentar trazer de novo a lista a.xlsx'
    );
    expect(tentar.attributes('disabled')).toBeUndefined();
    expect(marca(w, 'desfazer').exists()).toBe(false);
    await tentar.trigger('click');
    expect(w.emitted('tentarDeNovo')).toEqual([[parada]]);
  });

  it('falhou e não dá para continuar: só a frase, sem botão', () => {
    const w = montar({ listas: [lista('a', 'falhou', { podeTentar: false })] });
    expect(w.get('[data-situacao="falhou"]').text()).toBe(
      'Não consegui trazer esta lista.'
    );
    expect(w.find('button').exists()).toBe(false);
  });

  it('enquanto tenta de novo, só o botão daquela lista fica ocupado', () => {
    const w = montar({
      listas: [
        lista('a', 'falhou', { podeTentar: true }),
        lista('b', 'falhou', { podeTentar: true }),
      ],
      tentando: 'a',
    });
    const botoes = w.findAll('[data-relacionamentos="tentar-de-novo"]');
    expect(botoes[0].attributes('disabled')).toBeDefined();
    expect(botoes[1].attributes('disabled')).toBeUndefined();
  });

  it('vazio: uma frase curta, sem botão', () => {
    const w = montar();
    expect(marca(w, 'vazio').text()).toBe(
      'Você ainda não trouxe nenhuma lista.'
    );
    expect(w.find('button').exists()).toBe(false);
  });

  it('carregando: esqueleto', () => {
    const w = montar({ carregando: true });
    expect(
      marca(w, 'carregando').findAll('.animate-pulse').length
    ).toBeGreaterThan(0);
    expect(marca(w, 'vazio').exists()).toBe(false);
  });

  it('erro: frase e botão que emite "tentar"', async () => {
    const w = montar({ comErro: true });
    const erro = marca(w, 'erro');
    expect(erro.text()).toContain('Não consegui mostrar o que você já trouxe.');
    await erro.get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });
});

describe('DialogoDesfazer', () => {
  // O Dialog da casa abre um <dialog> nativo, que o jsdom não tem: troco por um
  // que só mostra o conteúdo e o rodapé.
  const DialogFalso = {
    props: ['title'],
    emits: ['close', 'confirm'],
    methods: {
      open() {},
      close() {
        this.$emit('close');
      },
    },
    template:
      '<div data-dialog><h3>{{ title }}</h3><slot /><slot name="footer" /></div>',
  };
  const montar = props =>
    mount(DialogoDesfazer, {
      props,
      global: { stubs: { Dialog: DialogFalso } },
    });

  it('mostra ANTES o que sai, quem fica aqui e o que volta ao que era, nesta ordem', () => {
    const w = montar({
      previa: { tira: 162, ficam: 18, devolve: 15 },
    });
    const texto = marca(w, 'dialogo-desfazer').text();
    expect(texto).toContain(
      'Isto tira as 162 pessoas que vieram nesta lista e ainda não conversaram com você. 18 ficam aqui, porque já conversaram com você ou já receberam campanha. As 15 que já estavam aqui voltam a ser como eram.'
    );
    expect(texto).toContain(
      'Quem pediu para não receber mensagens continua assim.'
    );
  });

  it('nenhuma frase promete conversa ou campanha que fica para quem sai', () => {
    const w = montar({ previa: { tira: 162, ficam: 18, devolve: 15 } });
    const texto = marca(w, 'dialogo-desfazer').text();
    expect(texto).not.toContain('As conversas que já aconteceram ficam');
    expect(texto).not.toContain('A mensagem enviada não volta');
  });

  it('singular e casos sem pessoas em cada grupo', () => {
    const um = montar({ previa: { tira: 1, ficam: 1, devolve: 0 } });
    const textoUm = marca(um, 'dialogo-desfazer').text();
    expect(textoUm).toContain(
      'Isto tira a pessoa que veio nesta lista e ainda não conversou com você.'
    );
    expect(textoUm).toContain(
      '1 fica aqui, porque já conversou com você ou já recebeu campanha.'
    );
    const so = montar({ previa: { tira: 0, ficam: 0, devolve: 15 } });
    const textoSo = marca(so, 'dialogo-desfazer').text();
    expect(textoSo).toContain(
      'As 15 que já estavam aqui voltam a ser como eram.'
    );
    expect(textoSo).not.toContain('Isto tira');
    expect(textoSo).not.toContain('aqui, porque');
  });

  it('enquanto não sabe o que sai: esqueleto e Desfazer desabilitado', () => {
    const w = montar({ previa: null });
    expect(w.findAll('.animate-pulse').length).toBeGreaterThan(0);
    expect(marca(w, 'desfazer-confirmar').attributes('disabled')).toBeDefined();
  });

  it('erro na prévia: frase e botão que emite "tentar"', async () => {
    const w = montar({ previa: null, comErroNaPrevia: true });
    expect(w.text()).toContain('Não consegui ver o que sai.');
    await marca(w, 'dialogo-desfazer').get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it('Desfazer (destrutivo) confirma e Cancelar fecha', async () => {
    const w = montar({ previa: { tira: 1, ficam: 0, devolve: 0 } });
    const confirmar = marca(w, 'desfazer-confirmar');
    expect(confirmar.text()).toBe('Desfazer');
    expect(confirmar.classes().join(' ')).toContain('ruby');
    await botao(w, 'Cancelar').trigger('click');
    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it('o botão mostra o carregando enquanto desfaz e fica desabilitado', () => {
    const w = montar({
      previa: { tira: 1, ficam: 0, devolve: 0 },
      desfazendo: true,
    });
    expect(marca(w, 'desfazer-confirmar').attributes('disabled')).toBeDefined();
  });
});
