import { chaveDoTexto } from '../../trazer/textoDoProblema';
// A linha com uma fórmula na empresa: a tela não conserta.
const COM_FORMULA = {
  linha: 9,
  tipo: 'formula',
  campo: 'empresa',
  nome: 'Caio Camargo',
  estado: 'aberto',
};

describe('a frase do cartão: a do motivo, quando o servidor diz o motivo', () => {
  const BASE = 'RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA';

  it.each([
    ['nome', 'formula_detected', 'NOME_FORMULA'],
    ['telefone', 'formula_phone_number', 'TELEFONE_FORMULA'],
    ['telefone', 'formula_detected', 'TELEFONE_FORMULA'],
    ['telefone', 'blank_phone_number', 'TELEFONE_VAZIO'],
    ['email', 'formula_detected', 'EMAIL_FORMULA'],
    ['email', 'blank_email', 'EMAIL_VAZIO'],
  ])('%s aberto com `%s` usa %s', (tipo, motivo, chave) => {
    expect(chaveDoTexto({ tipo, motivo, estado: 'aberto' })).toBe(
      `${BASE}.${chave}`
    );
  });

  it.each([
    ['telefone', 'invalid_brazilian_mobile_number', 'TELEFONE'],
    ['email', 'invalid_email', 'EMAIL'],
    ['nome', 'blank_name', 'NOME'],
    ['sem_contato', 'missing_contact', 'SEM_CONTATO'],
    ['duplicada', 'duplicate_phone_in_file', 'DUPLICADA'],
    ['nome', undefined, 'NOME'],
    ['nome', 'motivo_que_a_tela_nao_conhece', 'NOME'],
    // Nome de método de objeto não pode virar frase.
    ['nome', 'toString', 'NOME'],
  ])('%s aberto com `%s` fica com a frase do tipo', (tipo, motivo, chave) => {
    expect(chaveDoTexto({ tipo, motivo, estado: 'aberto' })).toBe(
      `${BASE}.${chave}`
    );
  });

  it.each(['guardado', 'deixado'])(
    'a linha que já não está aberta (%s) fica com a frase do tipo',
    estado => {
      expect(
        chaveDoTexto({ tipo: 'nome', motivo: 'formula_detected', estado })
      ).toBe(`${BASE}.NOME`);
    }
  );

  it('a fórmula que a tela não conserta: a frase com o campo, a sem o campo e a curta', () => {
    expect(chaveDoTexto(COM_FORMULA)).toBe(`${BASE}.FORMULA`);
    expect(chaveDoTexto({ ...COM_FORMULA, campo: 'outro' })).toBe(
      `${BASE}.FORMULA_SEM_CAMPO`
    );
    expect(chaveDoTexto({ ...COM_FORMULA, estado: 'deixado' })).toBe(
      `${BASE}.FORMULA_RESUMO`
    );
  });
});
