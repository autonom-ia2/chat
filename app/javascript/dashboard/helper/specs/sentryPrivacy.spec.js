import {
  semQuery,
  breadcrumbSemQuery,
  eventoSemQuery,
  excecaoSemDados,
} from '../sentryPrivacy';

const BUSCA = '/api/v1/accounts/1/contacts/search?q=ana@exemplo.invalid&page=1';

describe('sentryPrivacy — URLs sem query string', () => {
  it('tira query e âncora e deixa o caminho', () => {
    expect(semQuery(BUSCA)).toBe('/api/v1/accounts/1/contacts/search');
    expect(semQuery('https://x.invalid/app#t?q=1')).toBe(
      'https://x.invalid/app'
    );
    expect(semQuery(undefined)).toBeUndefined();
  });

  it.each(['xhr', 'fetch'])('breadcrumb %s sai sem a busca', categoria => {
    const original = {
      category: categoria,
      data: { method: 'GET', url: BUSCA, status_code: 200 },
    };
    const limpo = breadcrumbSemQuery(original);
    expect(limpo.data).toEqual({
      method: 'GET',
      url: '/api/v1/accounts/1/contacts/search',
      status_code: 200,
    });
    expect(original.data.url).toBe(BUSCA);
  });

  it('navegação sai sem a query nos dois lados', () => {
    const limpo = breadcrumbSemQuery({
      category: 'navigation',
      data: { from: '/app?q=ana@exemplo.invalid', to: '/app/c?tel=5511' },
    });
    expect(limpo.data).toEqual({ from: '/app', to: '/app/c' });
  });

  it('outras categorias passam como estão', () => {
    const clique = { category: 'ui.click', message: 'button.salvar' };
    expect(breadcrumbSemQuery(clique)).toBe(clique);
  });

  it('evento: tira query do request e dos breadcrumbs', () => {
    const evento = eventoSemQuery({
      request: { url: `https://app.invalid${BUSCA}`, query_string: 'q=ana' },
      breadcrumbs: [{ category: 'fetch', data: { url: BUSCA } }],
    });
    expect(evento.request).toEqual({
      url: 'https://app.invalid/api/v1/accounts/1/contacts/search',
    });
    expect(evento.breadcrumbs[0].data.url).toBe(
      '/api/v1/accounts/1/contacts/search'
    );
    expect(JSON.stringify(evento)).not.toContain('ana');
  });
});

describe('sentryPrivacy — exceção sem dados', () => {
  it('mantém a classe e os quadros da pilha, sem mensagem nem causa', () => {
    const erro = new TypeError('valor ana@exemplo.invalid', {
      cause: new Error('+5511912345678'),
    });
    const limpa = excecaoSemDados(erro);
    expect(limpa.name).toBe('TypeError');
    expect(limpa.message).toBe('');
    expect(limpa.cause).toBeUndefined();
    expect(limpa.stack).not.toContain('ana@');
    expect(limpa.stack.startsWith('TypeError\n')).toBe(true);
    expect(limpa.stack.split('\n').length).toBeGreaterThan(1);
  });

  it('pilha sem cabeçalho (Firefox/Safari) fica inteira', () => {
    const erro = new Error('segredo');
    erro.stack = 'salvar@https://app.invalid/a.js:1:2\n';
    expect(excecaoSemDados(erro).stack).toBe(
      'Error\nsalvar@https://app.invalid/a.js:1:2\n'
    );
  });
});
