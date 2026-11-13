import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDeExemplo } from '../../demo/trazer';
import { resumoDaTela } from '../../trazer/contagem';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
// #2896, E3 — no Conferir, junto dos outros números, uma linha diz quantas das
// pessoas que entram vão entrar como cliente (`resumo.clientes`, que é conta
// do servidor). Com zero, a linha não aparece, a não ser que a pessoa tenha
// respondido "Quais destes querem dizer cliente?": aí a tela diz que ninguém
// entra como cliente (é o sinal de que a escolha não pegou ninguém).
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const DOS_VALORES = {
  id: 'valores_cliente',
  coluna: 'Já é cliente?',
  indice: 7,
  preenchidas: 0,
  valores: [],
  outros: null,
};
const ALGUMAS = { clientes: 'algumas', colunaCliente: 7 };

const conferir = (clientes, extra = {}) => {
  const exemplo = leituraDeExemplo('l1');
  const leitura = {
    ...exemplo,
    ...extra,
    resumo: { ...exemplo.resumo, clientes },
  };
  return mount(TelaConferir, {
    attachTo: document.body,
    props: {
      leitura,
      resumo: resumoDaTela(leitura),
      total: resumoDaTela(leitura).entram,
    },
  });
};

beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('Conferir: quantas entram como cliente', () => {
  it('diz quantas, no plural', () => {
    expect(marca(conferir(12), 'entram-como-clientes').text()).toBe(
      '12 entram como clientes.'
    );
  });

  it('diz uma, no singular', () => {
    expect(marca(conferir(1), 'entram-como-clientes').text()).toBe(
      '1 entra como cliente.'
    );
  });

  it('com zero (ou sem o número), a linha não aparece', () => {
    expect(marca(conferir(0), 'entram-como-clientes').exists()).toBe(false);
    expect(marca(conferir(undefined), 'entram-como-clientes').exists()).toBe(
      false
    );
  });

  it('com zero e a pergunta dos valores respondida, diz que ninguém entra como cliente', () => {
    const w = conferir(0, {
      perguntas: [{ id: 'clientes' }, DOS_VALORES],
      respostas: { ...ALGUMAS, valores_cliente: { modo: 'preenchidas' } },
    });
    expect(marca(w, 'entram-como-clientes').text()).toBe(
      'Ninguém entra como cliente.'
    );
    expect(marca(w, 'entram-como-clientes').element.parentElement).toBe(
      marca(w, 'contadores').element.parentElement
    );
  });

  it('com zero e sem a pergunta dos valores ("ainda não", "sim, todas"), não diz nada', () => {
    const aindaNao = conferir(0, {
      perguntas: [{ id: 'clientes' }],
      respostas: { clientes: 'ainda_nao' },
    });
    expect(marca(aindaNao, 'entram-como-clientes').exists()).toBe(false);
    const todas = conferir(0, {
      perguntas: [{ id: 'clientes' }],
      respostas: { clientes: 'sim_todas' },
    });
    expect(marca(todas, 'entram-como-clientes').exists()).toBe(false);
  });

  it('com zero e a pergunta dos valores ainda sem resposta, não diz nada', () => {
    const w = conferir(0, {
      perguntas: [{ id: 'clientes' }, DOS_VALORES],
      respostas: { ...ALGUMAS },
    });
    expect(marca(w, 'entram-como-clientes').exists()).toBe(false);
  });

  it('fica junto dos outros números, antes das fichas de exemplo', () => {
    const w = conferir(12);
    const linha = marca(w, 'entram-como-clientes').element;
    expect(linha.parentElement).toBe(
      marca(w, 'contadores').element.parentElement
    );
    expect(linha.parentElement).toBe(
      marca(w, 'juntadas').element.parentElement
    );
  });
});
