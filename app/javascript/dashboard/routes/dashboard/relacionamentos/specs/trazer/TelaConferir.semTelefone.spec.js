import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraComProblema, leituraDaTela } from '../../fonte/trazerTraducao';
import { resumoDaTela } from '../../trazer/contagem';
import TelaConferir from '../../components/trazer/TelaConferir.vue';

// #2896 — o Conferir avisa quantas pessoas vão entrar sem o telefone que
// estava escrito na planilha (o número não deu para ler e a linha entra pelo
// e-mail). O aviso diz o que fazer e não trava o trazer. O número é de quem
// entra agora: a resposta de cada conserto traz a conta nova.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const UMA =
  '1 pessoa vai entrar sem o telefone: o número que está na planilha não parece um celular com DDD. Você pode trazer assim mesmo. Se for um celular, escreva o DDD junto do número, na mesma coluna, e envie a planilha de novo: ela fica com o telefone.';
const VARIAS =
  '98 pessoas vão entrar sem o telefone: o número que está na planilha não parece um celular com DDD. Você pode trazer assim mesmo. Se for um celular, escreva o DDD junto do número, na mesma coluna, e envie a planilha de novo: elas ficam com o telefone.';

// A leitura como o servidor a devolve: uma planilha com o DDD numa coluna à
// parte, em que quem tem e-mail entra só com ele.
const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    {
      indice: 1,
      nome: 'DDD',
      destino: 'informacao',
      campo: { nome: 'DDD', para_que_serve: '' },
    },
    { indice: 2, nome: 'Celular', destino: 'telefone' },
    { indice: 3, nome: 'E-mail', destino: 'email' },
  ],
  perguntas: [{ id: 'clientes' }],
  respostas: {},
  resumo: {
    total: 200,
    novas: 98,
    completadas: 0,
    comProblema: 102,
    juntadas: 0,
    semTelefone: 98,
    entram: 98,
    clientes: 0,
  },
  exemplos: [],
  problemas: [],
  problemas_total: 0,
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

describe('TelaConferir: quem entra sem o telefone da planilha', () => {
  const comSemTelefone = semTelefone =>
    leituraDaTela({ ...PRONTA, resumo: { ...PRONTA.resumo, semTelefone } });
  const montar = leitura =>
    mount(TelaConferir, {
      attachTo: document.body,
      props: {
        leitura,
        resumo: resumoDaTela(leitura),
        total: resumoDaTela(leitura).entram,
      },
    });
  const aviso = w => w.find('[data-relacionamentos="entram-sem-telefone"]');
  const trazer = w => w.get('[data-relacionamentos="trazer-confirmar"]');

  it('com zero, nada aparece', () => {
    expect(aviso(montar(comSemTelefone(0))).exists()).toBe(false);
  });

  it('sem o número na resposta do servidor, nada aparece', () => {
    const resumo = { total: 200, novas: 98, comProblema: 102, entram: 98 };
    const w = montar(leituraDaTela({ ...PRONTA, resumo }));
    expect(aviso(w).exists()).toBe(false);
  });

  it('uma pessoa: no singular, dizendo o que aconteceu e o que fazer', () => {
    expect(aviso(montar(comSemTelefone(1))).text()).toBe(UMA);
  });

  it('várias pessoas: no plural, junto dos outros números', () => {
    const w = montar(comSemTelefone(98));
    expect(aviso(w).text()).toBe(VARIAS);
    expect(aviso(w).element.parentElement).toBe(
      w.get('[data-relacionamentos="contadores"]').element.parentElement
    );
  });

  // A linha 3 não tinha nome; tem e-mail bom e um celular sem DDD. A pessoa
  // conserta o nome, a linha passa a entrar só com o e-mail, e o servidor
  // responde com a conta nova (fonte/trazerFonte.js a põe na leitura).
  it('acompanha o conserto: a resposta de quem mexe numa linha faz o aviso aparecer e sumir', () => {
    const semNome = {
      linha: 3,
      tipo: 'nome',
      nome: '',
      valor: '',
      contato: 'bruno.brandolim@exemplo.com.br',
      estado: 'aberto',
    };
    const lida = leituraDaTela({
      ...PRONTA,
      resumo: { ...PRONTA.resumo, semTelefone: 0 },
      problemas: [semNome],
      problemas_total: 1,
    });
    expect(aviso(montar(lida)).exists()).toBe(false);

    const guardado = {
      ...semNome,
      estado: 'guardado',
      corrigido: 'Bruno Brandolim',
    };
    const consertada = leituraComProblema(lida, guardado, 99, 0, 1);
    expect(aviso(montar(consertada)).text()).toBe(UMA);

    const deixada = { ...semNome, estado: 'deixado' };
    const deFora = leituraComProblema(consertada, deixada, 98, 0, 0);
    expect(aviso(montar(deFora)).exists()).toBe(false);
  });

  it('não trava: o botão de trazer continua ligado e manda trazer', async () => {
    const w = montar(comSemTelefone(98));
    expect(trazer(w).attributes('disabled')).toBeUndefined();
    await trazer(w).trigger('click');
    expect(w.emitted('trazer')).toHaveLength(1);
  });

  it('é um aviso, não um erro: sem `role="alert"` e sem "tentar de novo"', () => {
    const w = montar(comSemTelefone(98));
    expect(aviso(w).attributes('role')).toBeUndefined();
    expect(w.find('[data-relacionamentos="erro"]').exists()).toBe(false);
  });
});
