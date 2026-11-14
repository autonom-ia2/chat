import {
  MOTIVO_NAO_SALVOU,
  chaveDaRecusa,
} from '../../trazer/recusaDoConserto';
// #2896, Fatia 2 — o servidor recusou o valor que a pessoa escreveu (422
// `valor_invalido`) e disse o motivo, no código da leitura da planilha. Aqui o
// motivo vira a chave da frase que a linha mostra; motivo que a tela não
// conhece cai na frase do campo.
const BASE = 'RELACIONAMENTOS_TRAZER.PRECISAM.RECUSA';

describe('chaveDaRecusa', () => {
  it.each([
    ['telefone', `${BASE}.CAMPO.TELEFONE`],
    ['email', `${BASE}.CAMPO.EMAIL`],
    ['nome', `${BASE}.CAMPO.NOME`],
  ])('motivo desconhecido no campo %s: a frase do campo', (campo, chave) => {
    expect(chaveDaRecusa(campo, 'qualquer_coisa')).toBe(chave);
    expect(chaveDaRecusa(campo, '')).toBe(chave);
    expect(chaveDaRecusa(campo, undefined)).toBe(chave);
  });

  it('linha sem campo (a repetida): a frase da linha', () => {
    expect(chaveDaRecusa('', 'qualquer_coisa')).toBe(`${BASE}.CAMPO.LINHA`);
  });

  // A escrita falhou sem o servidor recusar o valor (ele caiu, ou a rede caiu):
  // a frase não culpa o que a pessoa escreveu.
  it.each(['telefone', 'email', 'nome', 'contato', ''])(
    'a falha que não é do valor (`nao_salvou`), no campo "%s": a frase da linha',
    campo => {
      expect(chaveDaRecusa(campo, MOTIVO_NAO_SALVOU)).toBe(
        `${BASE}.CAMPO.LINHA`
      );
    }
  );

  it('nome de propriedade de objeto não é motivo conhecido', () => {
    expect(chaveDaRecusa('email', 'constructor')).toBe(`${BASE}.CAMPO.EMAIL`);
    expect(chaveDaRecusa('toString', 'x')).toBe(`${BASE}.CAMPO.LINHA`);
  });
});

describe('a frase de cada motivo que o servidor manda', () => {
  it.each([
    ['telefone', 'blank_phone_number', `${BASE}.TELEFONE`],
    ['telefone', 'invalid_brazilian_mobile_number', `${BASE}.TELEFONE`],
    ['telefone', 'formula_phone_number', `${BASE}.FORMULA`],
    ['email', 'blank_email', `${BASE}.EMAIL`],
    ['email', 'invalid_email', `${BASE}.EMAIL`],
    ['nome', 'blank_name', `${BASE}.NOME`],
    ['nome', 'formula_detected', `${BASE}.FORMULA`],
    ['telefone', 'missing_contact', `${BASE}.CONTATO`],
    ['telefone', 'invalid_email', `${BASE}.EMAIL`],
    ['nome', 'muito_longo', 'RELACIONAMENTOS_TRAZER.ERROS.MUITO_LONGO'],
    [
      'telefone',
      'planilha_apagada',
      'RELACIONAMENTOS_TRAZER.PRECISAM.PLANILHA_APAGADA',
    ],
  ])('campo "%s", motivo `%s`', (campo, motivo, chave) => {
    expect(chaveDaRecusa(campo, motivo)).toBe(chave);
  });

  it('`telefone` e `email` não são motivos do servidor: caem na frase do campo', () => {
    expect(chaveDaRecusa('telefone', 'telefone')).toBe(
      `${BASE}.CAMPO.TELEFONE`
    );
    expect(chaveDaRecusa('email', 'email')).toBe(`${BASE}.CAMPO.EMAIL`);
  });
});
