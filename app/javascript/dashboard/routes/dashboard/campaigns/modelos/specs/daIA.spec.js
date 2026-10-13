import {
  campoDaChave,
  chaveDoCampo,
  passaNaRegra,
  pedacosParaTexto,
  textoParaPedacos,
} from '../helpers/daIA';

// Ida e volta entre a tela e o redator com IA (#1333): campos da tela ↔ chaves
// do catálogo, sem expressão regular.
describe('daIA', () => {
  it('maps screen fields to catalog keys and back', () => {
    expect(chaveDoCampo('nome_cliente')).toBe('cliente.primeiro_nome');
    expect(chaveDoCampo('nome_empresa')).toBe('minha_empresa.nome');
    expect(chaveDoCampo('valor')).toBe('publico.valor');
    expect(chaveDoCampo('variavel_2')).toBe('publico.variavel_2');
    expect(chaveDoCampo('horario.data_hora')).toBe('horario.data_hora');
    [
      'nome_cliente',
      'nome_empresa',
      'valor',
      'variavel_2',
      'horario.data_hora',
    ].forEach(campo => expect(campoDaChave(chaveDoCampo(campo))).toBe(campo));
    expect(campoDaChave('publico.Vencimento')).toBe('publico.Vencimento');
  });

  it('reads {{key}} into pieces and writes them back', () => {
    const texto = 'Oi, {{cliente.primeiro_nome}}! Valor: {{publico.valor}}.';
    const pedacos = textoParaPedacos(texto);
    expect(pedacos).toEqual([
      { t: 'texto', v: 'Oi, ' },
      { t: 'campo', v: 'nome_cliente' },
      { t: 'texto', v: '! Valor: ' },
      { t: 'campo', v: 'valor' },
      { t: 'texto', v: '.' },
    ]);
    expect(pedacosParaTexto(pedacos)).toBe(texto);
    expect(textoParaPedacos('Oi {{cliente')).toEqual([
      { t: 'texto', v: 'Oi {{cliente' },
    ]);
  });

  it('applies the structural rule that the AI decides (edges, glued fields, stray braces, buttons)', () => {
    const conteudo = texto => ({
      formato: 'padrao',
      texto: textoParaPedacos(texto),
      exemplos: {},
      rodape: '',
      botoes: [],
    });
    expect(
      passaNaRegra(conteudo('Oi, {{cliente.primeiro_nome}}! Até.'), 'aviso')
    ).toBe(true);
    expect(
      passaNaRegra(conteudo('{{cliente.primeiro_nome}}, até.'), 'aviso')
    ).toBe(false);
    expect(
      passaNaRegra(
        conteudo('Oi {{cliente.nome}} {{publico.data}} ok.'),
        'aviso'
      )
    ).toBe(false);
    expect(passaNaRegra(conteudo('Oi {{cliente'), 'aviso')).toBe(false);
    expect(
      passaNaRegra(
        {
          ...conteudo('Oi, tudo bem?'),
          botoes: [{ tipo: 'resposta', texto: '' }],
        },
        'aviso'
      )
    ).toBe(false);
  });
});
