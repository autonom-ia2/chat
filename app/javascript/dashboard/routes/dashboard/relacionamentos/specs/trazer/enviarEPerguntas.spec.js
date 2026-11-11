import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import EtapasDoTopo from '../../components/trazer/EtapasDoTopo.vue';
import SoltarArquivo from '../../components/trazer/SoltarArquivo.vue';
import TelaEnviar from '../../components/trazer/TelaEnviar.vue';
import CartoesDeEscolha from '../../components/trazer/CartoesDeEscolha.vue';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';

// Etapas, Enviar e as perguntas de "Trazer minha lista" (#2894), com o texto real em pt_BR.
withFullI18n('pt_BR');

const arquivo = nome => new File(['x'], nome);
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

describe('EtapasDoTopo', () => {
  it('marca a etapa de agora e põe ✓ nas feitas', () => {
    const w = mount(EtapasDoTopo, { props: { atual: 'conferir' } });
    expect(w.element.tagName).toBe('OL');
    const itens = w.findAll('li');
    expect(itens[0].text()).toContain('Enviar');
    expect(itens[0].get('.sr-only').text()).toBe('feita');
    expect(itens[1].text()).toContain('Conferir');
    expect(itens[2].text()).toContain('Pronto');
    expect(itens[1].find('.sr-only').exists()).toBe(false);
    expect(itens.map(li => li.attributes('aria-current'))).toEqual([
      undefined,
      'step',
      undefined,
    ]);
    expect(itens[0].find('.i-lucide-check').exists()).toBe(true);
  });

  it('não é navegação clicável', () => {
    const w = mount(EtapasDoTopo, { props: { atual: 'enviar' } });
    expect(w.find('a, button').exists()).toBe(false);
  });
});

describe('SoltarArquivo', () => {
  it('é um botão de verdade que abre o seletor e aceita Excel e CSV', async () => {
    const w = mount(SoltarArquivo);
    const botao = marca(w, 'soltar-arquivo');
    expect(botao.element.tagName).toBe('BUTTON');
    expect(botao.text()).toContain(
      'Arraste a planilha aqui ou clique para escolher'
    );
    expect(botao.text()).toContain(
      'Excel ou CSV. Precisa ter nome e telefone ou e-mail.'
    );
    const entrada = w.get('input[type="file"]');
    expect(entrada.attributes('accept')).toBe('.xlsx,.xls,.csv');
    const clique = vi.spyOn(entrada.element, 'click');
    await botao.trigger('click');
    expect(clique).toHaveBeenCalledTimes(1);
  });

  it('emite o arquivo escolhido', async () => {
    const w = mount(SoltarArquivo);
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [arquivo('lista.xlsx')],
      configurable: true,
    });
    await entrada.trigger('change');
    expect(w.emitted('arquivo')[0][0].name).toBe('lista.xlsx');
  });

  it('realça ao arrastar por cima e emite o arquivo solto', async () => {
    const w = mount(SoltarArquivo);
    const botao = marca(w, 'soltar-arquivo');
    await botao.trigger('dragenter');
    expect(botao.classes()).toContain('bg-n-blue-2');
    await botao.trigger('drop', {
      dataTransfer: { files: [arquivo('contatos.csv')] },
    });
    expect(botao.classes()).not.toContain('bg-n-blue-3');
    expect(w.emitted('arquivo')[0][0].name).toBe('contatos.csv');
  });

  it('mostra o erro como alerta', () => {
    const w = mount(SoltarArquivo, { props: { erro: 'Não é planilha.' } });
    expect(w.get('[role="alert"]').text()).toBe('Não é planilha.');
  });
});

describe('TelaEnviar', () => {
  it('mostra o título e a área de soltar, sem link de exemplo fora da demonstração', () => {
    const w = mount(TelaEnviar);
    expect(w.get('h1').text()).toBe('Traga sua lista. A gente organiza.');
    expect(marca(w, 'soltar-arquivo').exists()).toBe(true);
    expect(marca(w, 'usar-exemplo').exists()).toBe(false);
  });

  it('em demonstração mostra o link da planilha de exemplo e emite "exemplo"', async () => {
    const w = mount(TelaEnviar, { props: { mostrarExemplo: true } });
    const link = marca(w, 'usar-exemplo');
    expect(link.text()).toBe('Usar uma planilha de exemplo');
    await link.trigger('click');
    expect(w.emitted('exemplo')).toHaveLength(1);
  });

  it('carregando: "Lendo sua planilha…" com esqueleto, sem a área de soltar', () => {
    const w = mount(TelaEnviar, { props: { lendo: true } });
    const lendo = marca(w, 'carregando');
    expect(lendo.text()).toContain('Lendo sua planilha…');
    expect(lendo.attributes('aria-busy')).toBe('true');
    expect(lendo.findAll('.animate-pulse').length).toBeGreaterThan(0);
    expect(marca(w, 'soltar-arquivo').exists()).toBe(false);
  });

  it('erro de leitura: frase e botão que emite "tentar"', async () => {
    const w = mount(TelaEnviar, { props: { erro: 'leitura' } });
    const erro = marca(w, 'erro');
    expect(erro.text()).toContain('Não consegui ler esta planilha.');
    await erro.get('button').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
    expect(marca(w, 'soltar-arquivo').exists()).toBe(true);
  });

  it('arquivo de tipo errado: a frase do tipo aparece na área de soltar', () => {
    const w = mount(TelaEnviar, { props: { erro: 'tipo' } });
    expect(w.get('[role="alert"]').text()).toBe(
      'Este arquivo não é uma planilha. Use Excel ou CSV.'
    );
  });

  it('repassa o arquivo escolhido', async () => {
    const w = mount(TelaEnviar);
    await w.getComponent(SoltarArquivo).vm.$emit('arquivo', arquivo('a.csv'));
    expect(w.emitted('arquivo')[0][0].name).toBe('a.csv');
  });
});

describe('CartoesDeEscolha', () => {
  const opcoes = [
    { id: 'a', rotulo: 'Primeira' },
    { id: 'b', rotulo: 'Segunda' },
    { id: 'c', rotulo: 'Terceira' },
  ];
  const montar = (modelValue = '') =>
    mount(CartoesDeEscolha, {
      props: { opcoes, modelValue, rotuloId: 'titulo' },
      attachTo: document.body,
    });

  it('é um radiogroup com um radio por cartão', () => {
    const w = montar('b');
    expect(w.get('[role="radiogroup"]').attributes('aria-labelledby')).toBe(
      'titulo'
    );
    const radios = w.findAll('[role="radio"]');
    expect(radios.map(r => r.attributes('aria-checked'))).toEqual([
      'false',
      'true',
      'false',
    ]);
    expect(radios.map(r => r.attributes('tabindex'))).toEqual([
      '-1',
      '0',
      '-1',
    ]);
    w.unmount();
  });

  it('sem escolha, o Tab cai no primeiro cartão', () => {
    const w = montar('');
    expect(
      w.findAll('[role="radio"]').map(r => r.attributes('tabindex'))
    ).toEqual(['0', '-1', '-1']);
    w.unmount();
  });

  it('clicar escolhe', async () => {
    const w = montar();
    await w.get('[data-resposta="c"]').trigger('click');
    expect(w.emitted('update:modelValue')).toEqual([['c']]);
    w.unmount();
  });

  it.each([
    ['ArrowRight', 'a', 'b'],
    ['ArrowDown', 'a', 'b'],
    ['ArrowLeft', 'b', 'a'],
    ['ArrowUp', 'b', 'a'],
    ['ArrowRight', 'c', 'a'],
    ['ArrowLeft', 'a', 'c'],
    ['End', 'a', 'c'],
    ['Home', 'c', 'a'],
  ])('%s em %s escolhe %s', async (tecla, de, para) => {
    const w = montar(de);
    await w.get(`[data-resposta="${de}"]`).trigger('keydown', { key: tecla });
    expect(w.emitted('update:modelValue')).toEqual([[para]]);
    w.unmount();
  });

  it('outras teclas não escolhem nada', async () => {
    const w = montar('a');
    await w.get('[data-resposta="a"]').trigger('keydown', { key: 'x' });
    expect(w.emitted('update:modelValue')).toBeUndefined();
    w.unmount();
  });
});

describe('PerguntaDaVez', () => {
  const colunas = [{ nome: 'Nome' }, { nome: 'Situação' }];
  const montar = (pergunta, extra = {}) =>
    mount(PerguntaDaVez, {
      props: { pergunta, respostas: {}, colunas, ...extra },
    });

  it('"Essas pessoas já são clientes?" tem três cartões', () => {
    const w = montar({ id: 'clientes' });
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe('clientes');
    expect(w.get('h1').text()).toBe('Essas pessoas já são clientes?');
    const cartoes = w.findAll('[data-relacionamentos="resposta"]');
    expect(cartoes.map(c => c.attributes('data-resposta'))).toEqual([
      'sim_todas',
      'ainda_nao',
      'algumas',
    ]);
    expect(cartoes.map(c => c.text())).toEqual([
      'Sim, todas',
      'Ainda não',
      'Algumas',
    ]);
  });

  it('a pergunta do telefone usa o nome da coluna', () => {
    const w = montar({ id: 'telefone', coluna: 'Fone 2' });
    expect(w.get('h1').text()).toBe('A coluna “Fone 2” é telefone de quem?');
    expect(
      w.findAll('[data-relacionamentos="resposta"]').map(c => c.text())
    ).toEqual(['Da pessoa', 'Da empresa', 'Não usar']);
  });

  it('Continuar nunca fica desligado por falta de resposta: o clique diz o que falta e emite só depois de escolher', async () => {
    const w = montar({ id: 'clientes' });
    expect(marca(w, 'continuar').attributes('disabled')).toBeUndefined();
    await marca(w, 'continuar').trigger('click');
    expect(w.emitted('continuar')).toBeUndefined();
    expect(w.get('[role="alert"]').text()).toBe('Escolha uma das respostas.');
    await w.setProps({
      podeContinuar: true,
      respostas: { clientes: 'sim_todas' },
    });
    const continuar = marca(w, 'continuar');
    expect(continuar.attributes('disabled')).toBeUndefined();
    await continuar.trigger('click');
    expect(w.emitted('continuar')).toHaveLength(1);
  });

  it('Voltar emite "voltar"', async () => {
    const w = montar({ id: 'clientes' });
    const voltar = w.findAll('button').find(b => b.text() === 'Voltar');
    await voltar.trigger('click');
    expect(w.emitted('voltar')).toHaveLength(1);
  });

  it('escolher um cartão emite "responder" com a pergunta e a resposta', async () => {
    const w = montar({ id: 'clientes' });
    await w.get('[data-resposta="ainda_nao"]').trigger('click');
    expect(w.emitted('responder')).toEqual([['clientes', 'ainda_nao']]);
  });

  it('"Algumas" pergunta qual coluna diz quem é cliente', async () => {
    const w = montar({ id: 'clientes' });
    expect(w.text()).not.toContain('Qual coluna diz quem é cliente?');
    await w.setProps({ respostas: { clientes: 'algumas' } });
    expect(w.text()).toContain('Qual coluna diz quem é cliente?');
    expect(w.find('label').text()).toBe('Qual coluna diz quem é cliente?');
    expect(w.findAll('select')).toHaveLength(0);
  });

  it('não pede coluna nas outras respostas nem na pergunta do telefone', () => {
    expect(
      montar(
        { id: 'clientes' },
        { respostas: { clientes: 'sim_todas' } }
      ).text()
    ).not.toContain('Qual coluna');
    expect(montar({ id: 'telefone', coluna: 'Fone 2' }).text()).not.toContain(
      'Qual coluna'
    );
  });
});
