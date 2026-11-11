import { fraseDoPasso } from '../frases';
import { novoPasso } from '../catalogo';
import { fraseDaListaDeEmail, guardarNomesDasListas } from '../listaDeEmail';

// G52 (#2760) — o passo "Pôr na lista de e-mail": nasce sem lista e a frase
// diz o nome da lista quando o editor já carregou as listas.
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

const CATALOGO = {
  passos: [
    {
      tipo: 'lista_de_email',
      grupo: 'CONTATO',
      frase: 'AUTOMACAO_LIVRE.PASSOS.LISTA_DE_EMAIL',
      campos: [{ nome: 'lista_id', peca: 'lista_de_email' }],
    },
  ],
};

describe('lista de e-mail', () => {
  it('nasce sem lista escolhida', () => {
    expect(novoPasso(CATALOGO.passos[0], 'l1', t)).toEqual({
      id: 'l1',
      tipo: 'lista_de_email',
      lista_id: null,
    });
  });

  it('a frase traz o nome da lista carregada; sem ele, a frase do passo', () => {
    const passo = { id: 'l1', tipo: 'lista_de_email', lista_id: 42 };
    expect(fraseDaListaDeEmail(passo, t)).toBe(
      'AUTOMACAO_LIVRE.PASSOS.LISTA_DE_EMAIL'
    );

    guardarNomesDasListas([{ id: 42, name: 'Dicas do mês' }]);

    expect(fraseDoPasso(passo, CATALOGO, t)).toBe(
      'AUTOMACAO_LIVRE.LISTA_DE_EMAIL.FRASE(Dicas do mês)'
    );
  });
});
