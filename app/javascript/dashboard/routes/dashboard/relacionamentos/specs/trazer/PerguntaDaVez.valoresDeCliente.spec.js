import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';
// #2896, E3 — a pergunta "Quais destes querem dizer cliente?": a pessoa marca
// os valores da coluna que querem dizer cliente, ou a primeira opção ("toda
// linha com algo escrito"). Nada vem marcado; o Continuar fica ligado e, sem
// nada marcado, diz o que falta.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const PERGUNTA = {
  id: 'valores_cliente',
  coluna: 'Já é cliente?',
  indice: 4,
  preenchidas: 35,
  valores: [
    { chave: 'k-nao', valor: 'Não', linhas: 20 },
    { chave: 'k-sim', valor: 'Sim', linhas: 12 },
    { chave: 'k-2019', valor: 'Sim, desde 2019', linhas: 1 },
  ],
  outros: null,
};
const PREENCHIDAS = { modo: 'preenchidas' };
const comChaves = (...chaves) => ({ modo: 'valores', chaves });

const montar = (extra = {}, pergunta = PERGUNTA) =>
  mount(PerguntaDaVez, {
    attachTo: document.body,
    props: { pergunta, respostas: {}, colunas: [], ...extra },
  });
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const caixas = w => w.findAll('[role="checkbox"]');
const caixa = (w, resposta) =>
  w.get(`[role="checkbox"][data-resposta="${resposta}"]`);
const marcadas = w =>
  caixas(w)
    .filter(item => item.attributes('aria-checked') === 'true')
    .map(item => item.attributes('data-resposta'));

afterEach(() => {
  document.body.innerHTML = '';
});

describe('PerguntaDaVez: quais valores querem dizer cliente', () => {
  it('diz a pergunta e de que coluna é', () => {
    const w = montar();
    expect(w.get('h1').text()).toBe('Quais destes querem dizer cliente?');
    expect(marca(w, 'coluna-da-pergunta').text()).toBe(
      'Coluna “Já é cliente?”'
    );
    expect(w.attributes('data-pergunta')).toBe('valores_cliente');
  });

  it('a coluna sem título aparece pela posição', () => {
    const w = montar({}, { ...PERGUNTA, coluna: '', indice: 2 });
    expect(marca(w, 'coluna-da-pergunta').text()).toBe('Coluna “Coluna 3”');
  });

  it('a primeira opção é "toda linha com algo escrito", com a contagem; depois, cada valor na ordem que veio', () => {
    const textos = caixas(montar()).map(item => item.text());
    expect(textos).toHaveLength(4);
    expect(textos[0]).toContain('Toda linha com algo escrito nesta coluna');
    expect(textos[0]).toContain('35 linhas');
    expect(textos[1]).toContain('Não');
    expect(textos[1]).toContain('20 linhas');
    expect(textos[2]).toContain('12 linhas');
    // O plural acompanha a conta.
    expect(textos[3]).toContain('Sim, desde 2019');
    expect(textos[3]).toContain('1 linha');
    expect(textos[3]).not.toContain('1 linhas');
  });

  it('tudo nasce desmarcado, e não há cartões de escolha única', () => {
    const w = montar();
    expect(marcadas(w)).toEqual([]);
    expect(w.find('[role="radiogroup"]').exists()).toBe(false);
  });

  it('cada opção é um botão de marcar com alvo de toque de 44 px, e o texto longo quebra a linha', () => {
    const w = montar();
    caixas(w).forEach(item => {
      expect(item.element.tagName).toBe('BUTTON');
      expect(item.attributes('type')).toBe('button');
      expect(item.classes()).toContain('min-h-11');
    });
    const texto = caixa(w, 'k-2019').get('[data-relacionamentos="valor"]');
    expect(texto.classes()).toEqual(
      expect.arrayContaining(['min-w-0', 'break-words'])
    );
  });

  // O servidor manda o valor com até 120 caracteres: aparece inteiro, quebra
  // a linha (mesmo sem espaço) e não empurra a contagem para fora.
  it('o valor de 120 caracteres sem espaço aparece inteiro e quebra a linha', () => {
    const longo = 'a'.repeat(120);
    const w = montar(
      {},
      { ...PERGUNTA, valores: [{ chave: 'k-longo', valor: longo, linhas: 3 }] }
    );
    const texto = caixa(w, 'k-longo').get('[data-relacionamentos="valor"]');
    expect(texto.text()).toBe(longo);
    expect(texto.classes()).toEqual(
      expect.arrayContaining(['flex-1', 'min-w-0', 'break-words'])
    );
    expect(texto.classes()).not.toContain('truncate');
    expect(
      caixa(w, 'k-longo')
        .get('[data-relacionamentos="linhas-do-valor"]')
        .classes()
    ).toContain('shrink-0');
  });

  it('marcar um valor responde com a chave dele, nunca com o texto', async () => {
    const w = montar();
    await caixa(w, 'k-sim').trigger('click');
    expect(w.emitted('responder')).toEqual([
      ['valores_cliente', comChaves('k-sim')],
    ]);
  });

  it('marcar a primeira opção responde "preenchidas"', async () => {
    const w = montar();
    await caixa(w, 'preenchidas').trigger('click');
    expect(w.emitted('responder')).toEqual([['valores_cliente', PREENCHIDAS]]);
  });

  it('mostra o que já veio respondido', () => {
    expect(
      marcadas(montar({ respostas: { valores_cliente: PREENCHIDAS } }))
    ).toEqual(['preenchidas']);
    expect(
      marcadas(
        montar({ respostas: { valores_cliente: comChaves('k-sim', 'k-2019') } })
      )
    ).toEqual(['k-sim', 'k-2019']);
  });

  it('a primeira opção e os valores não ficam marcados juntos', async () => {
    const comValores = montar({
      respostas: { valores_cliente: comChaves('k-sim') },
    });
    await caixa(comValores, 'preenchidas').trigger('click');
    expect(comValores.emitted('responder')).toEqual([
      ['valores_cliente', PREENCHIDAS],
    ]);

    const comPrimeira = montar({ respostas: { valores_cliente: PREENCHIDAS } });
    await caixa(comPrimeira, 'k-nao').trigger('click');
    expect(comPrimeira.emitted('responder')).toEqual([
      ['valores_cliente', comChaves('k-nao')],
    ]);
  });

  it('desmarcar o último valor deixa a pergunta sem resposta', async () => {
    const w = montar({ respostas: { valores_cliente: comChaves('k-sim') } });
    await caixa(w, 'k-sim').trigger('click');
    expect(w.emitted('responder')).toEqual([['valores_cliente', null]]);
  });

  it('sem nada marcado, o Continuar está ligado e o clique diz o que falta, com o foco na primeira opção', async () => {
    const w = montar({ podeContinuar: false });
    expect(marca(w, 'continuar').attributes('disabled')).toBeUndefined();
    await marca(w, 'continuar').trigger('click');
    expect(w.emitted('continuar')).toBeUndefined();
    expect(w.get('[role="alert"]').text()).toBe('Marque pelo menos um.');
    expect(document.activeElement).toBe(caixa(w, 'preenchidas').element);
    expect(caixa(w, 'preenchidas').attributes('aria-describedby')).toBe(
      w.get('[role="alert"]').attributes('id')
    );
  });

  it('o aviso some quando a pessoa marca alguma coisa', async () => {
    const w = montar({ podeContinuar: false });
    await marca(w, 'continuar').trigger('click');
    await w.setProps({ respostas: { valores_cliente: comChaves('k-sim') } });
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });

  it('com algo marcado, o Continuar segue', async () => {
    const w = montar({
      respostas: { valores_cliente: PREENCHIDAS },
      podeContinuar: true,
    });
    await marca(w, 'continuar').trigger('click');
    expect(w.emitted('continuar')).toHaveLength(1);
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });
});

describe('PerguntaDaVez: a coluna sem nada escrito', () => {
  const VAZIA = { ...PERGUNTA, preenchidas: 0, valores: [] };

  it('diz que a coluna está vazia, acima das opções, sem esconder a opção nem desligar o Continuar', () => {
    const w = montar({}, VAZIA);
    const frase = marca(w, 'coluna-vazia');
    expect(frase.text()).toBe(
      'Esta coluna está vazia nesta planilha. Volte e escolha outra coluna, ou responda “Ainda não”.'
    );
    const primeira = caixa(w, 'preenchidas');
    expect(primeira.text()).toContain('0 linhas');
    // A frase vem antes da primeira opção, na ordem de leitura.
    expect(
      // eslint-disable-next-line no-bitwise
      frase.element.compareDocumentPosition(primeira.element) &
        Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();
    expect(primeira.attributes('disabled')).toBeUndefined();
  });

  it('com valores na coluna, a frase não aparece', () => {
    expect(marca(montar(), 'coluna-vazia').exists()).toBe(false);
  });
});

describe('PerguntaDaVez: os valores que não couberam na lista', () => {
  const comOutros = outros => montar({}, { ...PERGUNTA, outros });

  it('sem `outros`, não há frase', () => {
    expect(marca(montar(), 'outros-valores').exists()).toBe(false);
  });

  it('diz quantos valores ficaram de fora e em quantas linhas', () => {
    expect(
      marca(comOutros({ valores: 7, linhas: 9 }), 'outros-valores').text()
    ).toBe(
      'E mais 7 valores diferentes, em 9 linhas. Para marcar todos, escolha a primeira opção.'
    );
  });

  it('o plural acompanha cada número', () => {
    expect(
      marca(comOutros({ valores: 1, linhas: 1 }), 'outros-valores').text()
    ).toBe(
      'E mais 1 valor diferente, em 1 linha. Para marcar todos, escolha a primeira opção.'
    );
    expect(
      marca(comOutros({ valores: 1, linhas: 3 }), 'outros-valores').text()
    ).toBe(
      'E mais 1 valor diferente, em 3 linhas. Para marcar todos, escolha a primeira opção.'
    );
  });
});

describe('PerguntaDaVez: o que o servidor diz na pergunta dos valores', () => {
  it('a recusa é dita como alerta e o foco volta à primeira opção', async () => {
    const w = montar({ respostas: { valores_cliente: PREENCHIDAS } });
    await w.setProps({
      recusa: { chave: 'RELACIONAMENTOS_TRAZER.ERROS.FALTA_VALORES_CLIENTE' },
    });
    await w.vm.$nextTick();
    expect(w.get('[role="alert"]').text()).toBe(
      'Antes de trazer, diga quem é cliente.'
    );
    expect(document.activeElement).toBe(caixa(w, 'preenchidas').element);
  });

  it('a pergunta que já nasce com a recusa mostra a frase', () => {
    const w = montar({
      recusa: { chave: 'RELACIONAMENTOS_TRAZER.ERROS.FALTA_VALORES_CLIENTE' },
    });
    expect(w.get('[role="alert"]').text()).toBe(
      'Antes de trazer, diga quem é cliente.'
    );
  });

  it('feita de novo, diz que a coluna que dizia quem é cliente mudou', () => {
    const w = montar({ deNovo: true });
    expect(marca(w, 'pergunta-de-novo').text()).toBe(
      'Você mudou a coluna que dizia quem é cliente. Responda de novo.'
    );
  });
});
