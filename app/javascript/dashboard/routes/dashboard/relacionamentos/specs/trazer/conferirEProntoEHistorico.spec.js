import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  leituraDeExemplo,
  aplicarConserto,
  aplicarDeixarDeFora,
} from '../../demo/trazer';
import { resumoAoVivo, totalDaLeitura } from '../../trazer/contagem';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import FichaDeExemplo from '../../components/trazer/FichaDeExemplo.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
import TelaPronto from '../../components/trazer/TelaPronto.vue';
import HistoricoDeListas from '../../components/trazer/HistoricoDeListas.vue';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';

// Conferir, Pronto, histórico e o diálogo de Desfazer (#2894), com o texto real em pt_BR.
withFullI18n('pt_BR');

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

const DIA = 24 * 60 * 60 * 1000;
const AGORA = Date.UTC(2026, 10, 11, 15);
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);
const problemaDe = (leitura, linha) =>
  leitura.problemas.find(p => p.linha === linha);

const conferir = (leitura, extra = {}) =>
  mount(TelaConferir, {
    props: {
      leitura,
      resumo: resumoAoVivo(leitura),
      total: totalDaLeitura(leitura),
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
    [14, 'Linha 14: falta um número no telefone'],
    [37, 'Linha 37: o e-mail está sem “@”'],
    [62, 'Linha 62: falta o nome'],
    [143, 'Linhas 88 e 143: é a mesma pessoa. Qual fica?'],
    [171, 'Linha 171: não tem telefone nem e-mail'],
  ])('a linha %s diz o problema em palavras simples', (linha, frase) => {
    expect(montar(linha).text()).toContain(frase);
  });

  it('e-mail: Salvar só vale com um e-mail de verdade e emite a linha e o valor', async () => {
    const w = montar(37);
    const guardar = botao(w, 'Salvar');
    expect(guardar.attributes('disabled')).toBeDefined();
    await w.get('input').setValue('rita@exemplo');
    expect(botao(w, 'Salvar').attributes('disabled')).toBeDefined();
    await w.get('input').setValue(' rita.carvalhedo@exemplo.com.br ');
    expect(botao(w, 'Salvar').attributes('disabled')).toBeUndefined();
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')).toEqual([
      [37, 'rita.carvalhedo@exemplo.com.br'],
    ]);
  });

  it('nome: Salvar só com algum texto', async () => {
    const w = montar(62);
    expect(botao(w, 'Salvar').attributes('disabled')).toBeDefined();
    await w.get('input').setValue('Ana Brandolim');
    await botao(w, 'Salvar').trigger('click');
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')[0]).toEqual([62, 'Ana Brandolim']);
  });

  it('telefone: usa o campo de telefone e Salvar espera o número ficar completo', () => {
    const w = montar(14);
    expect(w.text()).toContain('Telefone certo');
    expect(w.findComponent(CampoDeTelefone).exists()).toBe(true);
    expect(botao(w, 'Salvar').attributes('disabled')).toBeDefined();
  });

  it('duplicada: escolhe qual linha fica, sem campo de texto', async () => {
    const w = montar(143);
    expect(w.find('input').exists()).toBe(false);
    expect(botao(w, 'Salvar')).toBeUndefined();
    await botao(w, 'Ficar com a linha 88').trigger('click');
    await botao(w, 'Ficar com a linha 143').trigger('click');
    expect(w.emitted('guardar')).toEqual([
      [143, 88],
      [143, 143],
    ]);
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
    expect(w.get('[data-coluna="Cel"]').text()).toContain('Cel');
    expect(w.get('[data-coluna="Cel"]').text()).toContain('Telefone');
    expect(w.get('[data-coluna="Aniversário"]').text()).toContain(
      'Vira uma informação da pessoa chamada “Aniversário”'
    );
  });

  it('coluna desconhecida tem Não guardar, que emite a troca', async () => {
    const w = montar();
    const linha = w.get('[data-coluna="Aniversário"]');
    const naoGuardar = linha
      .findAll('button')
      .find(b => b.text() === 'Não guardar');
    await naoGuardar.trigger('click');
    expect(w.emitted('trocar')).toEqual([['Aniversário', 'nao_guardar']]);
  });

  it('Trocar abre a escolha de destino em palavras simples (sem select nativo)', async () => {
    const w = montar();
    const linha = w.get('[data-coluna="Cel"]');
    await linha
      .findAll('button')
      .find(b => b.text() === 'Trocar')
      .trigger('click');
    expect(linha.find('select').exists()).toBe(false);
    const escolha = linha.get(
      'button[aria-label="Para onde vai a coluna “Cel”"]'
    );
    expect(escolha.text()).toContain('Telefone');
  });

  it('coluna que não vai ser guardada diz isso', () => {
    const w = mount(OQueVouGuardar, {
      props: { colunas: [{ nome: 'Aniversário', destino: 'nao_guardar' }] },
    });
    expect(w.text()).toContain('Não vou guardar “Aniversário”');
  });
});

describe('TelaConferir', () => {
  it('a frase forte tem os números certos, no plural', () => {
    const w = conferir(leituraDeExemplo('l1'));
    expect(w.get('h1').text()).toBe(
      'Achei 200 pessoas. 180 são novas, 15 já estavam aqui e vão ser completadas, 5 precisam de você.'
    );
  });

  it('a frase usa o singular quando é 1', () => {
    const base = leituraDeExemplo('l1');
    const leitura = {
      ...base,
      resumo: { total: 1, novas: 1, completadas: 0, comProblema: 0 },
      problemas: [],
    };
    expect(conferir(leitura).get('h1').text()).toBe(
      'Achei 1 pessoa. 1 é nova.'
    );
    const um = {
      ...base,
      resumo: { total: 3, novas: 1, completadas: 1, comProblema: 1 },
    };
    expect(conferir(um).get('h1').text()).toBe(
      'Achei 3 pessoas. 1 é nova, 1 já estava aqui e vai ser completada, 5 precisam de você.'
    );
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

  it('o botão único diz quantas pessoas vão chegar', () => {
    const w = conferir(leituraDeExemplo('l1'));
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
    expect(w.text()).toContain('Você pode desfazer por 7 dias.');
    expect(w.text()).toContain('Precisam de você (5)');
  });

  it('consertou: a frase, o título e o botão mudam na hora e a linha vira Pronto', () => {
    const leitura = aplicarConserto(
      leituraDeExemplo('l1'),
      62,
      'Ana Brandolim'
    );
    const w = conferir(leitura);
    expect(w.get('h1').text()).toBe(
      'Achei 200 pessoas. 181 são novas, 15 já estavam aqui e vão ser completadas, 4 precisam de você.'
    );
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 196 pessoas');
    expect(w.text()).toContain('Precisam de você (4)');
    expect(w.get('[data-linha="62"]').text()).toContain('Pronto');
  });

  it('deixou de fora: a frase ganha "ficou de fora" e o botão não muda', () => {
    const leitura = aplicarDeixarDeFora(leituraDeExemplo('l1'), 62);
    const w = conferir(leitura);
    expect(w.get('h1').text()).toContain('1 ficou de fora');
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 195 pessoas');
  });

  it('tudo resolvido troca o título da lista de problemas', () => {
    const base = leituraDeExemplo('l1');
    const leitura = [14, 37, 62, 143, 171].reduce(
      (atual, linha) => aplicarConserto(atual, linha, 'x'),
      base
    );
    const w = conferir(leitura);
    expect(w.text()).toContain('Tudo resolvido');
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

  it('com 0 pessoas o botão fica desabilitado', () => {
    const base = leituraDeExemplo('l1');
    const leitura = {
      ...base,
      resumo: { total: 0, novas: 0, completadas: 0, comProblema: 0 },
      problemas: [],
    };
    expect(
      marca(conferir(leitura), 'trazer-confirmar').attributes('disabled')
    ).toBeDefined();
  });

  it('erro ao trazer: frase e botão que emite "tentar"', async () => {
    const w = conferir(leituraDeExemplo('l1'), { comErro: true });
    const erro = marca(w, 'erro');
    expect(erro.text()).toContain(
      'Não consegui trazer a lista. Tente de novo.'
    );
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

describe('TelaPronto', () => {
  it('andamento: barra com role progressbar, a frase e o aviso de que pode fechar', () => {
    const w = mount(TelaPronto, {
      props: { trazendo: true, porcentagem: 40, total: 195 },
    });
    const andamento = marca(w, 'andamento');
    expect(w.get('h1').text()).toBe('Trazendo… 40%.');
    expect(andamento.text()).toContain(
      'Pode fechar esta tela; eu aviso quando terminar.'
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
    expect(erro.text()).toContain(
      'Não consegui ver como está indo. Tente de novo.'
    );
    await erro.get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it('pronto: "195 pessoas chegaram." com a ação principal e a discreta', async () => {
    const w = mount(TelaPronto, { props: { trazendo: false, total: 195 } });
    expect(marca(w, 'pronto').text()).toContain('195 pessoas chegaram.');
    expect(w.get('[role="heading"]').attributes('aria-level')).toBe('1');
    const ver = marca(w, 'ver-as-pessoas');
    expect(ver.text()).toBe('Ver as pessoas');
    await ver.trigger('click');
    expect(w.emitted('ver')).toHaveLength(1);
    await botao(w, 'Trazer outra lista').trigger('click');
    expect(w.emitted('outra')).toHaveLength(1);
    expect(marca(w, 'andamento').exists()).toBe(false);
  });

  it('singular: "1 pessoa chegou."', () => {
    const w = mount(TelaPronto, { props: { total: 1 } });
    expect(w.text()).toContain('1 pessoa chegou.');
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
  const prazoDe = item => {
    if (item.situacao !== 'pronto') return 'nao_se_aplica';
    return item.quando + 7 * DIA >= AGORA ? 'aberto' : 'acabou';
  };
  const montar = props =>
    mount(HistoricoDeListas, {
      props: { listas: [], prazoDe, ...props },
    });

  it('cheio: arquivo, quando, quem, pessoas, situação e Desfazer com o prazo', () => {
    const w = montar({ listas: [lista('Clientes 2025', 'pronto')] });
    const linha = w.get('[data-lista="Clientes 2025"]');
    expect(linha.text()).toContain('Clientes 2025.xlsx');
    expect(linha.text()).toContain('em 08/11');
    expect(linha.text()).toContain('por Marina Dornelaz');
    expect(linha.text()).toContain('195 pessoas');
    expect(linha.get('[data-situacao]').text()).toBe('Pronto');
    expect(linha.text()).toContain('até 15/11');
    expect(marca(w, 'desfazer').text()).toBe('Desfazer');
    expect(marca(w, 'desfazer').attributes('aria-label')).toBe(
      'Desfazer a lista Clientes 2025.xlsx'
    );
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

  it('passado o prazo o botão some e fica a frase', () => {
    const w = montar({
      listas: [lista('a', 'pronto', { quando: AGORA - 9 * DIA })],
    });
    expect(marca(w, 'desfazer').exists()).toBe(false);
    expect(w.text()).toContain('Prazo para desfazer acabou');
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
    expect(erro.text()).toContain(
      'Não consegui mostrar o que você já trouxe. Tente de novo.'
    );
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

  it('mostra ANTES o que sai e o que volta ao que era', () => {
    const w = montar({
      previa: { tira: 180, devolve: 15, receberamCampanha: 0 },
    });
    const texto = marca(w, 'dialogo-desfazer').text();
    expect(texto).toContain(
      'Isto tira 180 pessoas que vieram nesta lista e devolve 15 ao que eram antes.'
    );
    expect(texto).toContain('As conversas que já aconteceram ficam.');
    expect(texto).not.toContain('campanha');
  });

  it('avisa quem já recebeu campanha', () => {
    const w = montar({
      previa: { tira: 180, devolve: 15, receberamCampanha: 3 },
    });
    expect(marca(w, 'dialogo-desfazer').text()).toContain(
      '3 pessoas já receberam uma campanha. A mensagem enviada não volta.'
    );
  });

  it('singular e casos sem pessoas que saem ou que voltam', () => {
    const um = montar({
      previa: { tira: 1, devolve: 0, receberamCampanha: 1 },
    });
    expect(marca(um, 'dialogo-desfazer').text()).toContain(
      'Isto tira 1 pessoa que veio nesta lista.'
    );
    expect(marca(um, 'dialogo-desfazer').text()).toContain(
      '1 pessoa já recebeu uma campanha.'
    );
    const so = montar({
      previa: { tira: 0, devolve: 15, receberamCampanha: 0 },
    });
    expect(marca(so, 'dialogo-desfazer').text()).toContain(
      'Isto devolve 15 ao que eram antes.'
    );
  });

  it('enquanto não sabe o que sai: esqueleto e Desfazer desabilitado', () => {
    const w = montar({ previa: null });
    expect(w.findAll('.animate-pulse').length).toBeGreaterThan(0);
    expect(marca(w, 'desfazer-confirmar').attributes('disabled')).toBeDefined();
  });

  it('erro na prévia: frase e botão que emite "tentar"', async () => {
    const w = montar({ previa: null, comErroNaPrevia: true });
    expect(w.text()).toContain('Não consegui ver o que sai. Tente de novo.');
    await marca(w, 'dialogo-desfazer').get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it('Desfazer (destrutivo) confirma e Cancelar fecha', async () => {
    const w = montar({ previa: { tira: 1, devolve: 0, receberamCampanha: 0 } });
    const confirmar = marca(w, 'desfazer-confirmar');
    expect(confirmar.text()).toBe('Desfazer');
    expect(confirmar.classes().join(' ')).toContain('ruby');
    await botao(w, 'Cancelar').trigger('click');
    expect(w.emitted('fechar')).toHaveLength(1);
  });

  it('o botão mostra o carregando enquanto desfaz e fica desabilitado', () => {
    const w = montar({
      previa: { tira: 1, devolve: 0, receberamCampanha: 0 },
      desfazendo: true,
    });
    expect(marca(w, 'desfazer-confirmar').attributes('disabled')).toBeDefined();
  });
});
