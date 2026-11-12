import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDaTela } from '../../fonte/trazerTraducao';
import { resumoDaTela } from '../../trazer/contagem';
import { destinosDisponiveis } from '../../trazer/destinos';
import LinhaDeColuna from '../../components/trazer/LinhaDeColuna.vue';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';

// #2896 — o telefone da empresa só existe quando a leitura tem empresa
// (`tem_empresa`): a tela não oferece o destino nem a resposta quando não tem.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

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

const pronta = (extra = {}) => ({ ...PRONTA, ...extra });

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('o telefone da empresa só é oferecido quando a leitura tem empresa', () => {
  const rotulos = w =>
    w.findAll('[role="option"]').map(opcao => opcao.attributes('data-value'));

  it('os destinos disponíveis', () => {
    expect(destinosDisponiveis(true)).toContain('telefone_da_empresa');
    expect(destinosDisponiveis(false)).not.toContain('telefone_da_empresa');
    expect(destinosDisponiveis(false)).toHaveLength(
      destinosDisponiveis(true).length - 1
    );
  });

  it.each([
    [true, true],
    [false, false],
  ])('a coluna (temEmpresa: %s)', async (temEmpresa, oferece) => {
    const w = mount(LinhaDeColuna, {
      attachTo: document.body,
      props: {
        coluna: { indice: 6, nome: 'Fone 2', destino: 'cidade' },
        temEmpresa,
      },
    });
    await w.get('[data-relacionamentos="trocar-coluna"]').trigger('click');
    await flushPromises();
    expect(rotulos(w).includes('telefone_da_empresa')).toBe(oferece);
    expect(rotulos(w)).toContain('telefone');
  });

  it.each([
    [true, ['Da pessoa', 'Da empresa', 'Não usar']],
    [false, ['Da pessoa', 'Não usar']],
  ])('a pergunta do telefone (temEmpresa: %s)', (temEmpresa, respostas) => {
    const w = mount(PerguntaDaVez, {
      attachTo: document.body,
      props: {
        pergunta: { id: 'telefone', coluna: 'Celular', indice: 1 },
        respostas: {},
        temEmpresa,
      },
    });
    expect(
      w.findAll('[data-relacionamentos="resposta"]').map(opcao => opcao.text())
    ).toEqual(respostas);
  });

  it('TelaConferir entrega às colunas o que a leitura diz', async () => {
    const leitura = leituraDaTela(pronta({ tem_empresa: false }));
    const w = mount(TelaConferir, {
      attachTo: document.body,
      props: {
        leitura,
        resumo: resumoDaTela(leitura),
        total: resumoDaTela(leitura).entram,
      },
    });
    w.findAllComponents(LinhaDeColuna).forEach(linha =>
      expect(linha.props('temEmpresa')).toBe(false)
    );
    expect(w.findAllComponents(LinhaDeColuna)).toHaveLength(3);
  });
});
