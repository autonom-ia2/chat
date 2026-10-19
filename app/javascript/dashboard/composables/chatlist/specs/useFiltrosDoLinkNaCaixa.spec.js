import { ref } from 'vue';

const rota = ref({ name: 'home', params: {}, query: {} });
const ouvintes = [];
const replace = vi.fn(async destino => {
  rota.value = { ...rota.value, ...destino };
  ouvintes.forEach(ouvinte => ouvinte(rota.value));
});

vi.mock('vue-router', () => ({
  useRoute: () => new Proxy({}, { get: (_alvo, chave) => rota.value[chave] }),
  useRouter: () => ({
    replace,
    afterEach: ouvinte => ouvintes.push(ouvinte),
  }),
}));

const navegar = destino => {
  rota.value = { params: {}, query: {}, ...destino };
  ouvintes.forEach(ouvinte => ouvinte(rota.value));
};

describe('filtrosDoEndereco', () => {
  it('lê da_ia=1 e esperando_min dentro de 1..1440', async () => {
    const { filtrosDoEndereco } = await import('../useFiltrosDoLinkNaCaixa');
    expect(
      filtrosDoEndereco({ query: { da_ia: '1', esperando_min: '30' } })
    ).toEqual({ daIa: true, esperandoMin: 30 });
  });

  it('ignora valor que a caixa não oferece', async () => {
    const { filtrosDoEndereco } = await import('../useFiltrosDoLinkNaCaixa');
    ['0', '1441', '-1', 'abc', '30.5', '0x1e', ''].forEach(valor => {
      expect(
        filtrosDoEndereco({ query: { da_ia: 'sim', esperando_min: valor } })
      ).toEqual({ daIa: false, esperandoMin: null });
    });
  });
});

describe('useFiltrosDoLinkNaCaixa', () => {
  beforeEach(() => {
    vi.resetModules();
    ouvintes.length = 0;
    replace.mockClear();
    rota.value = { name: 'home', params: {}, query: {} };
  });

  it('a lista que abre pelo link liga o filtro', async () => {
    rota.value = { name: 'home', params: {}, query: { da_ia: '1' } };
    const { useFiltrosDoLinkNaCaixa } = await import(
      '../useFiltrosDoLinkNaCaixa'
    );
    const { daIa, esperandoMin } = useFiltrosDoLinkNaCaixa();

    expect(daIa.value).toBe(true);
    expect(esperandoMin.value).toBe(null);
  });

  it('abrir uma conversa mantém o filtro da lista; voltar pelo menu, sem o link, desliga', async () => {
    rota.value = { name: 'home', params: {}, query: { esperando_min: '30' } };
    const { useFiltrosDoLinkNaCaixa } = await import(
      '../useFiltrosDoLinkNaCaixa'
    );
    const { esperandoMin } = useFiltrosDoLinkNaCaixa();

    navegar({ name: 'inbox_conversation', params: { conversation_id: 7 } });
    expect(esperandoMin.value).toBe(30);

    navegar({ name: 'inbox_dashboard', params: { inbox_id: 3 } });
    expect(esperandoMin.value).toBe(null);
  });

  it('outra tela (fora da caixa) não mexe no filtro', async () => {
    rota.value = { name: 'home', params: {}, query: { da_ia: '1' } };
    const { useFiltrosDoLinkNaCaixa } = await import(
      '../useFiltrosDoLinkNaCaixa'
    );
    const { daIa } = useFiltrosDoLinkNaCaixa();

    navegar({ name: 'crm_kanban_index' });
    expect(daIa.value).toBe(true);
  });

  it('limpar tira só os parâmetros do link e mantém o resto do endereço', async () => {
    rota.value = {
      name: 'inbox_dashboard',
      params: { inbox_id: 3 },
      query: { da_ia: '1', esperando_min: '30', pasta: 'spam' },
    };
    const { useFiltrosDoLinkNaCaixa } = await import(
      '../useFiltrosDoLinkNaCaixa'
    );
    const { daIa, esperandoMin, limpar } = useFiltrosDoLinkNaCaixa();

    await limpar();

    expect(replace).toHaveBeenCalledWith({
      name: 'inbox_dashboard',
      params: { inbox_id: 3 },
      query: { pasta: 'spam' },
    });
    expect([daIa.value, esperandoMin.value]).toEqual([false, null]);
  });

  it('limpar dentro de uma conversa desliga sem trocar de tela', async () => {
    rota.value = { name: 'home', params: {}, query: { da_ia: '1' } };
    const { useFiltrosDoLinkNaCaixa } = await import(
      '../useFiltrosDoLinkNaCaixa'
    );
    const { daIa, esperandoMin, limpar } = useFiltrosDoLinkNaCaixa();
    navegar({ name: 'inbox_conversation', params: { conversation_id: 7 } });

    await limpar();

    expect(replace).not.toHaveBeenCalled();
    expect([daIa.value, esperandoMin.value]).toEqual([false, null]);
  });
});
