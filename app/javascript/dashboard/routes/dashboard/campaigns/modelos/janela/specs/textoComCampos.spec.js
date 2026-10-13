import {
  juntar,
  linkInequivoco,
  pareceLink,
  pedacos,
  previa,
} from '../textoComCampos';

// #1335: o texto da conversa aberta guarda os campos do catálogo; link só por
// campo — "://" e "www." travam, o ponto entre letras só avisa.
describe('textoComCampos', () => {
  it('quebra o texto em pedaços e volta igual', () => {
    const texto = 'Oi, {{cliente.primeiro_nome}}! Veja: {{publico.Link}}.';

    expect(pedacos(texto)).toEqual([
      { t: 'texto', v: 'Oi, ' },
      { t: 'campo', v: 'cliente.primeiro_nome' },
      { t: 'texto', v: '! Veja: ' },
      { t: 'campo', v: 'publico.Link' },
      { t: 'texto', v: '.' },
    ]);
    expect(juntar(pedacos(texto))).toBe(texto);
  });

  it('monta a prévia com o exemplo de cada campo', () => {
    expect(
      previa('Oi, {{cliente.primeiro_nome}}!', {
        'cliente.primeiro_nome': 'Ana',
      })
    ).toBe('Oi, Ana!');
  });

  it('trava só o link inequívoco, no texto fixo', () => {
    expect(linkInequivoco('Veja www.loja.com')).toBe(true);
    expect(linkInequivoco('Veja https://x.y')).toBe(true);
    expect(linkInequivoco('Veja {{publico.Link}} hoje.')).toBe(false);
    expect(linkInequivoco('Veja loja.com.br')).toBe(false);
  });

  it('o ponto entre letras só avisa, e não acusa fim de frase nem valor', () => {
    expect(pareceLink('Veja loja.com.br')).toBe(true);
    expect(pareceLink('Falei com o Sr.Paulo')).toBe(true);
    expect(pareceLink('Chegou hoje. Custa R$ 1.250,00.')).toBe(false);
    expect(pareceLink('Veja www.loja.com')).toBe(false);
  });
});
