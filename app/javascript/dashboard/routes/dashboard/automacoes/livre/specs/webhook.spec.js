import {
  corpoDasLinhas,
  corpoPronto,
  enderecoPronto,
  fraseDoWebhook,
  gravarPronto,
  hostDoEndereco,
  linhasDoCorpo,
} from '../webhook';

// G13 (#2670) — o passo "mandar dados para outro sistema" no editor: o
// endereço só https, o corpo em linhas (sem linha sumir sem aviso) e a frase.
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

describe('webhook', () => {
  it('aceita só endereço https com host', () => {
    expect(enderecoPronto('https://cobranca.exemplo.com/api')).toBe(true);
    expect(enderecoPronto('http://cobranca.exemplo.com/api')).toBe(false);
    expect(enderecoPronto('https://')).toBe(false);
    expect(enderecoPronto('')).toBe(false);
    expect(enderecoPronto(undefined)).toBe(false);
    expect(hostDoEndereco('https://a.b.com:8443/x?token=1')).toBe(
      'a.b.com:8443'
    );
    expect(hostDoEndereco('não é endereço')).toBe('');
  });

  it('o corpo vai e volta em linhas, na ordem', () => {
    const corpo = {
      cnpj: { $valor: 'card.atributos.cnpj' },
      nome: { $valor: 'contato.nome' },
    };
    const linhas = linhasDoCorpo(corpo);
    expect(linhas.map(l => l.nome)).toEqual(['cnpj', 'nome']);
    expect(corpoDasLinhas(linhas)).toEqual(corpo);
    expect(corpoPronto(corpo)).toBe(true);
    expect(corpoPronto({})).toBe(true);
  });

  it('linha sem nome, com nome repetido ou sem dado segura o salvar', () => {
    const dado = { $valor: 'contato.nome' };
    const semNome = corpoDasLinhas([{ nome: ' ', valor: dado }]);
    const repetido = corpoDasLinhas([
      { nome: 'nome', valor: dado },
      { nome: 'nome ', valor: dado },
    ]);
    const semDado = corpoDasLinhas([{ nome: 'nome', valor: null }]);
    [semNome, repetido, semDado].forEach(corpo =>
      expect(corpoPronto(corpo)).toBe(false)
    );
  });

  it('cada resposta guardada pede o nome e onde guardar', () => {
    expect(gravarPronto([])).toBe(true);
    expect(
      gravarPronto([{ chave: 'numero', destino: 'card.atributos.n' }])
    ).toBe(true);
    expect(gravarPronto([{ chave: ' ', destino: 'card.atributos.n' }])).toBe(
      false
    );
    expect(gravarPronto([{ chave: 'numero', destino: '' }])).toBe(false);
  });

  it('a frase diz para onde vai, sem o token do endereço', () => {
    const passo = {
      url: 'https://cobranca.exemplo.com/x?token=abc',
      descricao: 'Cobrança',
    };
    expect(fraseDoWebhook(passo, t)).toBe(
      'AUTOMACAO_LIVRE.WEBHOOK.FRASE(cobranca.exemplo.com,Cobrança)'
    );
    expect(fraseDoWebhook({ url: '' }, t)).toBe(
      'AUTOMACAO_LIVRE.WEBHOOK.FRASE_SEM_DESCRICAO(AUTOMACAO_LIVRE.WEBHOOK.OUTRO_SISTEMA)'
    );
  });
});
