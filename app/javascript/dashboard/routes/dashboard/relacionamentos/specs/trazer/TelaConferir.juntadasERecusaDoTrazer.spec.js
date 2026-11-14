import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDaTela } from '../../fonte/trazerTraducao';
import { resumoDaTela } from '../../trazer/contagem';
import { ERROS } from '../../trazer/useTrazerLista';
import TelaConferir from '../../components/trazer/TelaConferir.vue';

// #2896 — o Conferir diz quantas linhas a leitura juntou (a mesma pessoa mais
// de uma vez) e a recusa do trazer que não tem "tentar de novo".
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const NADA_PARA_TRAZER =
  'Não sobrou ninguém para trazer. Envie a planilha de novo.';
const DESFAZER_EM_CURSO =
  'Tem uma lista sendo desfeita agora. Espere o Desfazer terminar e tente de novo.';

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

describe('TelaConferir: as linhas juntadas e a recusa do trazer', () => {
  const montar = (leitura, extra = {}) =>
    mount(TelaConferir, {
      attachTo: document.body,
      props: {
        leitura,
        resumo: resumoDaTela(leitura),
        total: resumoDaTela(leitura).entram,
        ...extra,
      },
    });
  const comJuntadas = juntadas =>
    leituraDaTela(pronta({ resumo: { ...PRONTA.resumo, juntadas } }));
  const juntadas = w => w.find('[data-relacionamentos="juntadas"]');
  const aviso = w => w.find('[data-relacionamentos="recusa-do-trazer"]');

  it('sem linha juntada não diz nada', () => {
    expect(juntadas(montar(comJuntadas(0))).exists()).toBe(false);
  });

  it('uma linha juntada: no singular', () => {
    expect(juntadas(montar(comJuntadas(1))).text()).toBe(
      'Juntei 1 linha de uma pessoa que aparecia mais de uma vez.'
    );
  });

  it('várias linhas juntadas: no plural, junto do resumo', () => {
    const w = montar(comJuntadas(12));
    expect(juntadas(w).text()).toBe(
      'Juntei 12 linhas de pessoas que apareciam mais de uma vez.'
    );
    expect(
      w.get('[data-relacionamentos="contadores"]').element.parentElement
    ).toBe(juntadas(w).element.parentElement);
  });

  it('sem recusa do trazer não há aviso', () => {
    expect(aviso(montar(comJuntadas(0))).exists()).toBe(false);
  });

  it('a recusa do trazer "nada para trazer" é dita como alerta, sem "tentar de novo"', () => {
    const w = montar(comJuntadas(0), {
      recusaDoTrazer: ERROS.NADA_PARA_TRAZER,
    });
    expect(aviso(w).attributes('role')).toBe('alert');
    expect(aviso(w).text()).toBe(NADA_PARA_TRAZER);
    expect(w.find('[data-relacionamentos="erro"]').exists()).toBe(false);
    // O botão de trazer continua ligado: nada de botão desligado.
    expect(
      w.get('[data-relacionamentos="trazer-confirmar"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('a recusa do trazer "desfazer em curso" diz o que fazer, como alerta, sem "tentar de novo"', () => {
    const w = montar(comJuntadas(0), {
      recusaDoTrazer: ERROS.DESFAZER_EM_CURSO,
    });
    expect(aviso(w).attributes('role')).toBe('alert');
    expect(aviso(w).text()).toBe(DESFAZER_EM_CURSO);
    expect(w.findAll('[data-relacionamentos="recusa-do-trazer"]')).toHaveLength(
      1
    );
    expect(w.find('[data-relacionamentos="erro"]').exists()).toBe(false);
    // O botão de trazer continua ligado: é por ele que a pessoa tenta depois.
    expect(
      w.get('[data-relacionamentos="trazer-confirmar"]').attributes('disabled')
    ).toBeUndefined();
  });

  it.each([ERROS.TRAZER, ERROS.SEM_NINGUEM, ERROS.JA_TRAZIDA])(
    'o erro "%s" não é recusa do trazer: nenhum alerta ali',
    erro => {
      expect(
        aviso(montar(comJuntadas(0), { recusaDoTrazer: erro })).exists()
      ).toBe(false);
    }
  );
});
