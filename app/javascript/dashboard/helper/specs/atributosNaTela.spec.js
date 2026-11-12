import { naTela, chavesOcultas } from '../atributosNaTela';

// #2435 — as telas tiram o atributo com "Mostrar na tela" desligado; a
// definição chega da API (snake_case) ou do getter (camelCase).
describe('atributosNaTela', () => {
  const definicoes = [
    { attribute_key: 'plano' },
    { attribute_key: 'contador', oculto_na_tela: true },
    { attributeKey: 'codigo_erp', ocultoNaTela: true },
    { attributeKey: 'cidade', ocultoNaTela: false },
  ];

  it('naTela tira os ocultos, nas duas formas, e mantém a ordem', () => {
    expect(naTela(definicoes)).toEqual([
      { attribute_key: 'plano' },
      { attributeKey: 'cidade', ocultoNaTela: false },
    ]);
  });

  it('naTela aceita lista vazia ou ausente', () => {
    expect(naTela(undefined)).toEqual([]);
    expect(naTela([])).toEqual([]);
  });

  it('chavesOcultas devolve as chaves dos ocultos', () => {
    expect([...chavesOcultas(definicoes)]).toEqual(['contador', 'codigo_erp']);
    expect(chavesOcultas(undefined).size).toBe(0);
  });
});
