import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import CampoDaInformacao from '../../components/trazer/CampoDaInformacao.vue';
import LinhaDeColuna from '../../components/trazer/LinhaDeColuna.vue';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
// #2896 — a coluna que vira informação nova: o nome dela e o "Para que serve?"
// (components/trazer/CampoDaInformacao.vue), dentro da linha da coluna.
withFullI18n('pt_BR');

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);

// As linhas como o servidor as devolve (a planilha `com_problemas` do spec).
const TELEFONE = {
  linha: 4,
  tipo: 'telefone',
  nome: 'Carla Carvalhedo',
  valor: '(11) 2345-678',
  estado: 'aberto',
};

const SEM_NOME = {
  linha: 6,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11987650005',
  estado: 'aberto',
};

const SEM_CONTATO = {
  linha: 7,
  tipo: 'sem_contato',
  nome: 'Elisa Esteveira',
  valor: '',
  estado: 'aberto',
};

const REPETIDA = {
  linha: 8,
  tipo: 'duplicada',
  nome: 'Ana Outra',
  valor: '11987650001',
  estado: 'aberto',
  outraLinha: 2,
  duplicadas: [
    { linha: 2, telefone: '11987650001', email: 'ana@exemplo.com.br' },
    { linha: 8, telefone: '11987650001', email: '' },
  ],
};

const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'telefone', duvidosa: true },
    {
      indice: 3,
      nome: 'Plano',
      destino: 'informacao',
      campo: { nome: 'Plano', para_que_serve: '' },
    },
  ],
  perguntas: [
    { id: 'clientes' },
    { id: 'telefone', coluna: 'Celular', indice: 1 },
  ],
  respostas: {},
  resumo: {
    total: 7,
    novas: 2,
    completadas: 0,
    comProblema: 4,
    juntadas: 0,
    entram: 2,
  },
  exemplos: [],
  problemas: [TELEFONE, SEM_NOME, SEM_CONTATO, REPETIDA],
  problemas_total: 4,
  pagina: 1,
  por_pagina: 200,
};

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('CampoDaInformacao: o nome da informação e o "Para que serve?"', () => {
  const COLUNA = {
    indice: 6,
    nome: 'Venc.',
    destino: 'informacao',
    campo: { nome: 'Venc.', para_que_serve: '' },
  };
  const montar = (coluna = COLUNA, extra = {}) =>
    mount(CampoDaInformacao, {
      attachTo: document.body,
      props: { coluna, ...extra },
    });
  const nome = w => w.get('input[data-campo="nome"]');
  const paraQue = w => w.get('input[data-campo="para-que-serve"]');
  const salvar = w => w.get('form').trigger('submit');

  it('tem os dois campos: o nome já vem com o título da coluna e o "Para que serve?" vem vazio, com a ajuda', () => {
    const w = montar();
    expect(w.findAll('label').map(rotulo => rotulo.text())).toEqual([
      'Nome desta informação',
      'Para que serve?',
    ]);
    expect(nome(w).element.value).toBe('Venc.');
    expect(paraQue(w).element.value).toBe('');
    expect(w.text()).toContain(
      'Uma frase curta. Ex.: mês em que o seguro vence.'
    );
    expect(w.find('textarea').exists()).toBe(false);
  });

  it('sem `campo` (demonstração), o nome vem do título da coluna', () => {
    const w = montar({
      indice: 5,
      nome: 'Aniversário',
      destino: 'informacao',
    });
    expect(nome(w).element.value).toBe('Aniversário');
  });

  it('mostra o que o servidor já guardou', () => {
    const w = montar({
      ...COLUNA,
      campo: { nome: 'Vencimento', para_que_serve: 'mês do seguro' },
    });
    expect(nome(w).element.value).toBe('Vencimento');
    expect(paraQue(w).element.value).toBe('mês do seguro');
  });

  it('Salvar emite o nome e o para que serve, sem espaço sobrando', async () => {
    const w = montar();
    await nome(w).setValue(' Vencimento ');
    await paraQue(w).setValue(' mês em que o seguro vence ');
    await salvar(w);
    expect(w.emitted('salvar')).toEqual([
      [{ nome: 'Vencimento', para_que_serve: 'mês em que o seguro vence' }],
    ]);
  });

  it('o "Para que serve?" é opcional', async () => {
    const w = montar();
    await nome(w).setValue('Vencimento');
    await salvar(w);
    expect(w.emitted('salvar')).toEqual([
      [{ nome: 'Vencimento', para_que_serve: '' }],
    ]);
  });

  it('nada de botão desligado: sem nome, o clique diz o que falta e leva o foco ao campo', async () => {
    const w = montar();
    const acao = botao(w, 'Salvar');
    expect(acao.attributes('disabled')).toBeUndefined();
    expect(acao.attributes('type')).toBe('submit');
    await nome(w).setValue('   ');
    expect(botao(w, 'Salvar').attributes('disabled')).toBeUndefined();
    await salvar(w);
    expect(w.emitted('salvar')).toBeUndefined();
    const alerta = w.get('[role="alert"]');
    expect(alerta.text()).toBe('Escreva um nome para esta informação.');
    expect(document.activeElement).toBe(nome(w).element);
    expect(nome(w).attributes('aria-invalid')).toBe('true');
    expect(nome(w).attributes('aria-describedby')).toBe(
      alerta.attributes('id')
    );
    await nome(w).setValue('Vencimento');
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });

  it('é uma ação secundária: não é o botão azul sólido da tela', () => {
    const classes = botao(montar(), 'Salvar').classes().join(' ');
    expect(classes).not.toContain('bg-n-blue-11');
  });

  it('sem mudança nenhuma, Salvar não escreve de novo e diz "Salvo"', async () => {
    const w = montar();
    await salvar(w);
    expect(w.emitted('salvar')).toBeUndefined();
    expect(w.get('[role="status"]').text()).toBe('Salvo');
  });

  it('diz "Salvo" quando a escrita termina e o servidor devolve o que foi escrito', async () => {
    const w = montar();
    await paraQue(w).setValue('mês do seguro');
    await salvar(w);
    expect(w.get('[role="status"]').text()).toBe('');
    await w.setProps({ ocupado: true });
    await w.setProps({
      ocupado: false,
      coluna: {
        ...COLUNA,
        campo: { nome: 'Venc.', para_que_serve: 'mês do seguro' },
      },
    });
    expect(w.get('[role="status"]').text()).toBe('Salvo');
    // Mexeu de novo: o "Salvo" some.
    await paraQue(w).setValue('outra coisa');
    expect(w.get('[role="status"]').text()).toBe('');
  });

  it('não diz "Salvo" quando a escrita falha (a coluna volta como estava)', async () => {
    const w = montar();
    await paraQue(w).setValue('mês do seguro');
    await salvar(w);
    await w.setProps({ ocupado: true });
    await w.setProps({ ocupado: false });
    expect(w.get('[role="status"]').text()).toBe('');
    expect(paraQue(w).element.value).toBe('mês do seguro');
  });

  it('enquanto outra escrita anda, não escreve', async () => {
    const w = montar(COLUNA, { ocupado: true });
    await paraQue(w).setValue('mês do seguro');
    await salvar(w);
    expect(w.emitted('salvar')).toBeUndefined();
  });

  it('`pendente` (a coluna ainda não é informação nova): salva mesmo sem mudar nada', async () => {
    const w = montar(
      { indice: 2, nome: 'Obs', destino: 'cidade' },
      { pendente: true }
    );
    await salvar(w);
    expect(w.emitted('salvar')).toEqual([
      [{ nome: 'Obs', para_que_serve: '' }],
    ]);
  });
});

describe('CampoDaInformacao: os limites do servidor', () => {
  it('o nome do campo e o "Para que serve?" não deixam passar do limite', () => {
    const w = mount(CampoDaInformacao, {
      attachTo: document.body,
      props: { coluna: PRONTA.colunas[2] },
    });
    expect(w.get('input[data-campo="nome"]').attributes('maxlength')).toBe(
      '255'
    );
    expect(
      w.get('input[data-campo="para-que-serve"]').attributes('maxlength')
    ).toBe('1000');
  });
});

describe('LinhaDeColuna: a coluna que vira informação nova', () => {
  const montar = coluna =>
    mount(LinhaDeColuna, { attachTo: document.body, props: { coluna } });
  const escolherDestino = async (w, destino) => {
    await botao(w, 'Mudar').trigger('click');
    await flushPromises();
    await w.get(`[role="option"][data-value="${destino}"]`).trigger('click');
    await flushPromises();
  };
  const formulario = w => marca(w, 'campo-da-informacao');

  it('coluna que já é informação nova mostra os dois campos; as outras não', () => {
    const informacao = montar({
      indice: 6,
      nome: 'Situação',
      destino: 'informacao',
      campo: { nome: 'Situação', para_que_serve: '' },
    });
    expect(formulario(informacao).exists()).toBe(true);
    expect(
      formulario(
        montar({ indice: 1, nome: 'Cel', destino: 'telefone' })
      ).exists()
    ).toBe(false);
    expect(
      formulario(
        montar({ indice: 7, nome: 'Obs', destino: 'nao_guardar' })
      ).exists()
    ).toBe(false);
  });

  it('Salvar emite a troca com o destino e o campo', async () => {
    const w = montar({
      indice: 6,
      nome: 'Situação',
      destino: 'informacao',
      campo: { nome: 'Situação', para_que_serve: '' },
    });
    await w.get('input[data-campo="para-que-serve"]').setValue('fase da venda');
    await formulario(w).trigger('submit');
    expect(w.emitted('trocar')).toEqual([
      [6, 'informacao', { nome: 'Situação', para_que_serve: 'fase da venda' }],
    ]);
  });

  it('escolher "Informação nova" numa coluna com título salva na hora, com o título como nome do campo', async () => {
    const w = montar({ indice: 4, nome: 'Bairro', destino: 'cidade' });
    await escolherDestino(w, 'informacao');
    expect(w.emitted('trocar')).toEqual([
      [4, 'informacao', { nome: 'Bairro', para_que_serve: '' }],
    ]);
  });

  it('escolher "Informação nova" numa coluna sem título não salva: pede o nome, com o foco no campo', async () => {
    const w = montar({ indice: 4, nome: '', destino: 'nao_guardar' });
    await escolherDestino(w, 'informacao');
    expect(w.emitted('trocar')).toBeUndefined();
    expect(formulario(w).exists()).toBe(true);
    const nome = w.get('input[data-campo="nome"]');
    expect(nome.element.value).toBe('');
    expect(document.activeElement).toBe(nome.element);
    // Sem nome o clique diz o que falta; com nome, salva o destino e o campo.
    await formulario(w).trigger('submit');
    expect(w.get('[role="alert"]').text()).toBe(
      'Escreva um nome para esta informação.'
    );
    await nome.setValue('Observação');
    await formulario(w).trigger('submit');
    expect(w.emitted('trocar')).toEqual([
      [4, 'informacao', { nome: 'Observação', para_que_serve: '' }],
    ]);
  });

  it('os outros destinos continuam saindo só com a coluna e o destino', async () => {
    const w = montar({ indice: 1, nome: 'Cel', destino: 'telefone' });
    await escolherDestino(w, 'cidade');
    expect(w.emitted('trocar')).toEqual([[1, 'cidade']]);
  });

  it('OQueVouGuardar repassa a troca com o campo', async () => {
    const w = mount(OQueVouGuardar, {
      props: {
        colunas: [
          {
            indice: 6,
            nome: 'Situação',
            destino: 'informacao',
            campo: { nome: 'Situação', para_que_serve: '' },
          },
        ],
      },
    });
    await w.get('input[data-campo="nome"]').setValue('Fase');
    await marca(w, 'campo-da-informacao').trigger('submit');
    expect(w.emitted('trocar')).toEqual([
      [6, 'informacao', { nome: 'Fase', para_que_serve: '' }],
    ]);
  });
});
