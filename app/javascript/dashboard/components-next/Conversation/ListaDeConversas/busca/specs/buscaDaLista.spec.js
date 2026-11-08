import {
  digitosDe,
  nomeNoAvatar,
  pareceTelefone,
  prontoParaBuscar,
  trechoComDestaque,
} from '../buscaDaLista';

const destacados = partes =>
  partes.filter(parte => parte.destaque).map(parte => parte.texto);

describe('buscaDaLista (#2211)', () => {
  describe('quando buscar', () => {
    it.each([
      ['', false],
      ['j', false],
      [' j ', false],
      ['jo', true],
      ['João', true],
    ])('nome "%s" → %s (a partir de 2 letras)', (texto, esperado) => {
      expect(prontoParaBuscar(texto)).toBe(esperado);
    });

    it.each([
      ['119', false],
      ['11 9', false],
      ['1197', true],
      ['11 97862-2068', true],
      ['+55 (11) 9', true],
    ])('telefone "%s" → %s (a partir de 4 dígitos)', (texto, esperado) => {
      expect(prontoParaBuscar(texto)).toBe(esperado);
    });

    it('reconhece telefone só com dígitos e sinais de telefone', () => {
      expect(pareceTelefone('+55 (11) 97862-2068')).toBe(true);
      expect(pareceTelefone('Ana 11')).toBe(false);
      expect(digitosDe('+55 (11) 97862-2068')).toBe('5511978622068');
    });
  });

  describe('trecho com destaque', () => {
    it('destaca sem diferença de acento e mantém o texto original', () => {
      const partes = trechoComDestaque(
        'Fale com a Conceição amanhã',
        'conceicao'
      );
      expect(destacados(partes)).toEqual(['Conceição']);
      expect(partes.map(parte => parte.texto).join('')).toBe(
        'Fale com a Conceição amanhã'
      );
    });

    it('só destaca palavra de 3 letras ou mais (a regra do servidor)', () => {
      const partes = trechoComDestaque('Oi, é a Ana do seguro', 'a do ana');
      expect(destacados(partes)).toEqual(['Ana']);
    });

    it('destaca cada palavra, em qualquer ordem', () => {
      const partes = trechoComDestaque(
        'Preciso da apólice do carro',
        'carro apolice'
      );
      expect(destacados(partes)).toEqual(['apólice', 'carro']);
    });

    it('mensagem longa: começa no espaço antes do achado, com reticências', () => {
      const longo = `${'a '.repeat(60)}renovação ${'b '.repeat(120)}`;
      const partes = trechoComDestaque(longo, 'renovacao');
      expect(partes[0].texto).toBe('…');
      expect(partes[1]).toEqual({ texto: 'renovação', destaque: true });
      expect(partes[partes.length - 1].texto).toBe('…');
    });

    it('mensagem longa: o achado no meio da palavra começa na palavra inteira', () => {
      const longo = `${'a '.repeat(80)}Joana ${'b '.repeat(80)}`;
      const partes = trechoComDestaque(longo, 'ana');
      expect(partes[1]).toEqual({ texto: 'Jo', destaque: false });
      expect(partes[2]).toEqual({ texto: 'ana', destaque: true });
    });

    it('mensagem que cabe em 140 caracteres aparece inteira', () => {
      const texto = `${'palavra '.repeat(15)}Conceição`;
      const partes = trechoComDestaque(texto, 'conceicao');
      expect(partes.map(parte => parte.texto).join('')).toBe(texto);
    });

    it('não quebra com emoji antes do achado', () => {
      const partes = trechoComDestaque('👋 Oi, é a Joana', 'joana');
      expect(destacados(partes)).toEqual(['Joana']);
    });

    it('sem texto, sem partes', () => {
      expect(trechoComDestaque(null, 'x')).toEqual([]);
    });
  });
});

describe('nomeNoAvatar (#2211)', () => {
  it('nome que é só telefone vai vazio (o avatar mostra o ícone de pessoa)', () => {
    expect(nomeNoAvatar('+55 11 95555-4444')).toBe('');
    expect(nomeNoAvatar('5511955554444')).toBe('');
    expect(nomeNoAvatar('Loja 24 horas')).toBe('Loja 24 horas');
    expect(nomeNoAvatar(null)).toBe('');
  });
});
