// #2894 — o catálogo de textos do Trazer (pt_BR e en): frases que não supõem
// gênero e os textos de prazo que saíram.
import pt from 'dashboard/i18n/locale/pt_BR/relacionamentosTrazer.json';
import en from 'dashboard/i18n/locale/en/relacionamentosTrazer.json';
describe('texto sem supor gênero', () => {
  it('a pergunta de clientes fala das pessoas, sem "suas clientes"', () => {
    expect(pt.RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.TITULO).toBe(
      'Essas pessoas já são clientes?'
    );
    expect(en.RELACIONAMENTOS_TRAZER.PERGUNTAS.CLIENTES.TITULO).toBe(
      'Are these people already customers?'
    );
  });

  it('nenhuma frase do catálogo põe "cliente" no feminino ou no masculino de pessoa', () => {
    const textos = JSON.stringify(pt).toLowerCase();
    ['suas clientes', 'seus clientes', 'a cliente ', 'o cliente '].forEach(
      trecho => expect(textos).not.toContain(trecho)
    );
  });
});

describe('sem prazo para desfazer', () => {
  it('os textos de prazo saíram do catálogo', () => {
    const textos = pt.RELACIONAMENTOS_TRAZER;
    expect(textos.HISTORICO.ATE).toBeUndefined();
    expect(textos.HISTORICO.PRAZO_ACABOU).toBeUndefined();
    expect(textos.CONFERIR.CONTADOR.IR_PARA_PRECISAM).toBeUndefined();
    expect(textos.CONFERIR.SOSSEGO).toBe('Você pode desfazer quando quiser.');
  });
});
