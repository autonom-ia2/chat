import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import CampoDaInformacao from '../../components/trazer/CampoDaInformacao.vue';
import LinhaDeColuna from '../../components/trazer/LinhaDeColuna.vue';

// #2896, Fatia 2 — a linha de uma coluna em "O que vou guardar": as frases que
// a revisão do dono pediu (a coluna duvidosa, a que diz quem é cliente, o nome
// da informação nova), os alvos de toque de 44 px e o que ela mostra enquanto a
// planilha é lida de novo.
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);
const SITUACAO = {
  indice: 6,
  nome: 'Situação',
  destino: 'informacao',
  campo: { nome: 'Situação', para_que_serve: '' },
};
const montar = (coluna, props = {}) =>
  mount(LinhaDeColuna, {
    attachTo: document.body,
    props: { coluna, ...props },
  });

beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('as frases da coluna', () => {
  it('a coluna que o sistema não tem certeza pede para conferir', () => {
    const duvidosa = montar({
      indice: 2,
      nome: 'Fone 2',
      destino: 'telefone',
      duvidosa: true,
    });
    expect(marca(duvidosa, 'coluna-duvidosa').text()).toBe(
      'Confira esta coluna.'
    );
    const certa = montar({ indice: 1, nome: 'Cel', destino: 'telefone' });
    expect(marca(certa, 'coluna-duvidosa').exists()).toBe(false);
  });

  it('a coluna que diz quem é cliente fala isso, sem "fica como Se é cliente"', () => {
    const w = montar({ indice: 6, nome: 'Situação', destino: 'cliente' });
    expect(w.get('p').text()).toBe('“Situação” diz quem é cliente.');
    expect(w.text()).not.toContain('Se é cliente');
  });

  it('as outras colunas continuam dizendo para onde vão', () => {
    const w = montar({ indice: 1, nome: 'Cel', destino: 'telefone' });
    expect(w.get('p').text()).toBe('“Cel” fica como Telefone.');
  });

  it('a informação nova fala em nome da informação, não em "campo"', async () => {
    const w = montar(SITUACAO);
    expect(w.text()).toContain('Nome desta informação');
    expect(botao(w, 'Salvar')).toBeDefined();
    expect(w.text()).not.toContain('campo');
    await w.get('input[data-campo="nome"]').setValue('  ');
    await marca(w, 'campo-da-informacao').trigger('submit');
    expect(marca(w, 'erro-do-campo').text()).toBe(
      'Escreva um nome para esta informação.'
    );
  });
});

describe('alvos de toque de 44 px', () => {
  it('"Mudar" e "Não guardar" têm a altura mínima de 44 px', () => {
    const w = montar(SITUACAO);
    expect(botao(w, 'Mudar').classes()).toContain('min-h-11');
    expect(botao(w, 'Não guardar').classes()).toContain('min-h-11');
  });

  it('o "Salvar" e os dois campos da informação nova também', () => {
    const w = mount(CampoDaInformacao, {
      attachTo: document.body,
      props: { coluna: SITUACAO },
    });
    expect(botao(w, 'Salvar').classes()).toContain('min-h-11');
    const campos = w.findAll('input');
    expect(campos).toHaveLength(2);
    campos.forEach(campo => expect(campo.classes()).toContain('!h-11'));
  });
});

describe('enquanto a planilha é lida de novo', () => {
  const CEL = { indice: 1, nome: 'Cel', destino: 'telefone' };
  const trocarPara = async (w, destino) => {
    await botao(w, 'Mudar').trigger('click');
    await flushPromises();
    await w.get(`[role="option"][data-value="${destino}"]`).trigger('click');
    await flushPromises();
  };

  it('a coluna que disparou a troca fica com o botão carregando e diz que está lendo de novo', async () => {
    const w = montar(CEL);
    await trocarPara(w, 'nao_guardar');
    await w.setProps({ ocupado: true, relendo: true });
    const mudar = marca(w, 'trocar-coluna');
    expect(mudar.attributes('disabled')).toBeDefined();
    expect(
      w
        .findComponent('[data-relacionamentos="trocar-coluna"]')
        .props('isLoading')
    ).toBe(true);
    // Quem anuncia é o `status` da tela de conferir; aqui é só o texto ao lado.
    const estado = marca(w, 'relendo-a-coluna');
    expect(estado.attributes('aria-hidden')).toBe('true');
    expect(estado.text()).toBe('Lendo sua planilha de novo…');
  });

  it('as outras colunas só ficam desligadas, sem frase', async () => {
    const w = montar(CEL, { ocupado: true, relendo: true });
    expect(marca(w, 'trocar-coluna').attributes('disabled')).toBeDefined();
    expect(marca(w, 'relendo-a-coluna').exists()).toBe(false);
  });

  it('terminou de ler: o botão volta ao normal e a frase some', async () => {
    const w = montar(CEL);
    await trocarPara(w, 'nao_guardar');
    await w.setProps({ ocupado: true, relendo: true });
    await w.setProps({ ocupado: false, relendo: false });
    expect(marca(w, 'trocar-coluna').attributes('disabled')).toBeUndefined();
    expect(marca(w, 'relendo-a-coluna').exists()).toBe(false);
  });
});
