import { origemDoCampo, quandoNoFuso } from './memoriaDoCampo';

const opcoes = { fuso: 'America/Sao_Paulo', idioma: 'pt-BR' };
const fato = extra => ({
  escopo: 'card',
  tipo: 'fato',
  situacao: 'vigente',
  expirado_em: null,
  chave: 'placa',
  valor: 'ABC1D23',
  fonte: 'cliente',
  valido_desde: '2026-10-17T17:02:00Z',
  registrado_em: '2026-10-17T18:10:00Z',
  prova_message_id: 5,
  prova_conversation_display_id: 9,
  ...extra,
});

describe('memoriaDoCampo', () => {
  it('a hora sai no fuso da conta, dd/mm, hh:mm', () => {
    expect(
      quandoNoFuso('2026-10-17T17:02:00Z', 'America/Sao_Paulo', 'pt-BR')
    ).toBe('17/10, 14:02');
    expect(quandoNoFuso('2026-10-17T17:02:00Z', 'Asia/Tokyo', 'pt-BR')).toBe(
      '18/10, 02:02'
    );
  });

  it('cliente informou: a hora da mensagem e a mensagem de prova', () => {
    expect(origemDoCampo([fato()], 'placa', 'ABC1D23', opcoes)).toEqual({
      texto: 'CLIENTE',
      nome: '',
      quando: '17/10, 14:02',
      conversa: 9,
      mensagem: 5,
    });
  });

  it('corrigido: o nome de quem corrigiu, a hora da correção e sem link', () => {
    const corrigido = fato({
      fonte: 'pessoa_corrigiu',
      corrigido_por_nome: 'Ana',
    });
    expect(
      origemDoCampo([corrigido], 'placa', 'ABC1D23', opcoes)
    ).toMatchObject({
      texto: 'CORRIGIDO',
      nome: 'Ana',
      quando: '17/10, 15:10',
      conversa: null,
      mensagem: null,
    });
  });

  it('sem origem: valor diferente, campo vazio, sugestão, expirado, outro escopo ou eco nosso', () => {
    expect(origemDoCampo([fato()], 'placa', 'XYZ9W87', opcoes)).toBeNull();
    expect(origemDoCampo([fato()], 'placa', '', opcoes)).toBeNull();
    expect(
      origemDoCampo(
        [fato({ situacao: 'sugestao' })],
        'placa',
        'ABC1D23',
        opcoes
      )
    ).toBeNull();
    expect(
      origemDoCampo(
        [fato({ expirado_em: '2026-10-17T19:00:00Z' })],
        'placa',
        'ABC1D23',
        opcoes
      )
    ).toBeNull();
    expect(
      origemDoCampo([fato({ escopo: 'contato' })], 'placa', 'ABC1D23', opcoes)
    ).toBeNull();
    expect(
      origemDoCampo([fato({ fonte: 'ia_nossa' })], 'placa', 'ABC1D23', opcoes)
    ).toBeNull();
  });
});
