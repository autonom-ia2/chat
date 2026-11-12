import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';
// #2896 — a pergunta "Essas pessoas já são clientes?" com a resposta
// "Algumas": a coluna que diz quem é cliente é escolhida pelo índice dela na
// planilha (o nome pode repetir ou vir vazio).
withFullI18n('pt_BR');

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('PerguntaDaVez: a coluna que diz quem é cliente', () => {
  const COLUNAS = [
    { indice: 0, nome: 'Cliente?', destino: 'informacao' },
    { indice: 6, nome: 'Situação', destino: 'informacao' },
    { indice: 7, nome: '', destino: 'informacao' },
  ];
  const montar = (respostas, colunas = COLUNAS) =>
    mount(PerguntaDaVez, {
      attachTo: document.body,
      props: { pergunta: { id: 'clientes' }, respostas, colunas },
    });
  const abrirEscolha = async w => {
    await w.get('[role="combobox"]').trigger('click');
    await flushPromises();
  };

  it('oferece as colunas pelo índice; a sem título aparece pela posição', async () => {
    const w = montar({ clientes: 'algumas' });
    await abrirEscolha(w);
    const opcoes = w.findAll('[role="option"]');
    expect(opcoes.map(opcao => opcao.attributes('data-value'))).toEqual([
      '0',
      '6',
      '7',
    ]);
    expect(opcoes.map(opcao => opcao.text())).toEqual([
      'Cliente?',
      'Situação',
      'Coluna 8',
    ]);
  });

  it('escolher emite o índice da coluna, inclusive o da primeira (0)', async () => {
    const w = montar({ clientes: 'algumas' });
    await abrirEscolha(w);
    await w.get('[role="option"][data-value="0"]').trigger('click');
    expect(w.emitted('escolherColuna')).toEqual([[0]]);
  });

  it('a primeira coluna (índice 0) escolhida aparece como escolhida', () => {
    const w = montar({ clientes: 'algumas', colunaCliente: 0 });
    expect(w.get('[role="combobox"]').text()).toContain('Cliente?');
  });

  // O servidor recusa a coluna de nome, telefone, e-mail ou empresa: ela nem
  // é oferecida.
  it('só oferece as colunas que podem dizer quem é cliente', async () => {
    const w = montar({ clientes: 'algumas' }, [
      { indice: 0, nome: 'Nome', destino: 'nome' },
      { indice: 1, nome: 'Cel', destino: 'telefone' },
      { indice: 2, nome: 'E-mail', destino: 'email' },
      { indice: 3, nome: 'Empresa', destino: 'empresa' },
      { indice: 4, nome: 'Cidade', destino: 'cidade' },
      { indice: 5, nome: 'Já comprou', destino: 'informacao' },
      { indice: 6, nome: 'Obs', destino: 'nao_guardar' },
    ]);
    await abrirEscolha(w);
    expect(w.findAll('[role="option"]').map(opcao => opcao.text())).toEqual([
      'Cidade',
      'Já comprou',
      'Obs',
    ]);
  });

  it('sem nenhuma coluna que possa dizer, "Algumas" não aparece', () => {
    const w = montar({}, [
      { indice: 0, nome: 'Nome', destino: 'nome' },
      { indice: 1, nome: 'Cel', destino: 'telefone' },
    ]);
    expect(
      w
        .findAll('[data-relacionamentos="resposta"]')
        .map(cartao => cartao.attributes('data-resposta'))
    ).toEqual(['sim_todas', 'ainda_nao']);
  });

  it('a pergunta do telefone de uma coluna sem título usa a posição dela', () => {
    const w = mount(PerguntaDaVez, {
      props: {
        pergunta: { id: 'telefone', coluna: '', indice: 2 },
        respostas: {},
        colunas: COLUNAS,
      },
    });
    expect(w.get('h1').text()).toBe('A coluna “Coluna 3” é telefone de quem?');
  });
});
