import { listaFonte, POR_PAGINA } from '../fonte/listaFonte';
import { GRUPOS_DE_EMPRESAS, GRUPOS_DE_PESSOAS } from '../fonte/grupos';

// A fonte da lista de Relacionamentos (#2894). Em demonstração responde com a
// base fictícia; fora dela, por enquanto, diz que a fonte real ainda não existe.
const cheia = () => listaFonte({ demo: 'cheio', atraso: 0 });
const vazia = () => listaFonte({ demo: 'vazio', atraso: 0 });

const todasAsPaginas = async (fonte, pedido) => {
  const primeira = await fonte.listar({ ...pedido, pagina: 1 });
  const paginas = Math.ceil(primeira.total / POR_PAGINA);
  const resto = await Promise.all(
    Array.from({ length: Math.max(paginas - 1, 0) }, (_, i) =>
      fonte.listar({ ...pedido, pagina: i + 2 })
    )
  );
  return [primeira, ...resto].flatMap(r => r.itens);
};

describe('resumo', () => {
  it('conta total, clientes e quem sumiu há 1 a 3 meses', async () => {
    expect(await cheia().resumo()).toEqual({
      total: 280,
      clientes: 120,
      sumiu_1_a_3_meses: 42,
    });
  });

  it('zera tudo na conta vazia', async () => {
    expect(await vazia().resumo()).toEqual({
      total: 0,
      clientes: 0,
      sumiu_1_a_3_meses: 0,
    });
  });
});

describe('contagens', () => {
  it('dá o número de cada grupo de pessoas', async () => {
    expect(await cheia().contagens('pessoas')).toEqual({
      todos: 280,
      clientes: 120,
      falou_ha_pouco: 96,
      sumiu_1_a_3_meses: 42,
      sumiu_mais_de_3_meses: 71,
      nunca_conversou: 71,
      nao_quer_mensagens: 9,
    });
  });

  it('dá o número de cada grupo de empresas', async () => {
    const contagens = await cheia().contagens('empresas');
    expect(Object.keys(contagens)).toEqual(GRUPOS_DE_EMPRESAS.map(g => g.id));
    expect(contagens.todas).toBe(38);
    expect(contagens.com_clientes).toBe(14);
    expect(contagens.sem_pessoas).toBe(5);
  });

  it('bate com o total de listar em cada grupo de pessoas', async () => {
    const fonte = cheia();
    const contagens = await fonte.contagens('pessoas');
    const totais = await Promise.all(
      GRUPOS_DE_PESSOAS.map(
        async g =>
          (await fonte.listar({ aba: 'pessoas', grupo: g.id, pagina: 1 })).total
      )
    );
    expect(totais).toEqual(GRUPOS_DE_PESSOAS.map(g => contagens[g.id]));
  });

  it('bate com o total de listar em cada grupo de empresas', async () => {
    const fonte = cheia();
    const contagens = await fonte.contagens('empresas');
    const totais = await Promise.all(
      GRUPOS_DE_EMPRESAS.map(
        async g =>
          (await fonte.listar({ aba: 'empresas', grupo: g.id, pagina: 1 }))
            .total
      )
    );
    expect(totais).toEqual(GRUPOS_DE_EMPRESAS.map(g => contagens[g.id]));
  });

  it('zera todos os grupos na conta vazia', async () => {
    const contagens = await vazia().contagens('pessoas');
    expect(Object.values(contagens).every(n => n === 0)).toBe(true);
    expect(Object.keys(contagens)).toHaveLength(GRUPOS_DE_PESSOAS.length);
  });
});

describe('listar: paginação', () => {
  it('traz 25 por página e diz que tem mais', async () => {
    const { itens, total, temMais } = await cheia().listar({
      aba: 'pessoas',
      grupo: 'todos',
      pagina: 1,
    });
    expect(POR_PAGINA).toBe(25);
    expect(itens).toHaveLength(25);
    expect(total).toBe(280);
    expect(temMais).toBe(true);
  });

  it('traz o resto na última página e diz que acabou', async () => {
    const { itens, temMais } = await cheia().listar({
      aba: 'pessoas',
      grupo: 'todos',
      pagina: 12,
    });
    expect(itens).toHaveLength(5);
    expect(temMais).toBe(false);
  });

  it('não repete nem perde ninguém entre as páginas', async () => {
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      grupo: 'todos',
    });
    expect(itens).toHaveLength(280);
    expect(new Set(itens.map(p => p.id)).size).toBe(280);
  });

  it('começa na página 1 quando a página não vem', async () => {
    const { itens } = await cheia().listar({ aba: 'pessoas' });
    expect(itens).toHaveLength(25);
  });

  it('devolve lista vazia depois da última página', async () => {
    const { itens, temMais } = await cheia().listar({
      aba: 'pessoas',
      pagina: 99,
    });
    expect(itens).toEqual([]);
    expect(temMais).toBe(false);
  });

  it('lista empresas', async () => {
    const { itens, total, temMais } = await cheia().listar({
      aba: 'empresas',
      grupo: 'todas',
      pagina: 1,
    });
    expect(itens).toHaveLength(25);
    expect(total).toBe(38);
    expect(temMais).toBe(true);
    expect(itens[0]).toHaveProperty('cnpj');
  });
});

describe('listar: grupos', () => {
  it('só traz clientes no grupo "clientes"', async () => {
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      grupo: 'clientes',
    });
    expect(itens).toHaveLength(120);
    expect(itens.every(p => p.contact_type === 'customer')).toBe(true);
  });

  it('só traz quem nunca conversou no grupo "nunca conversou"', async () => {
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      grupo: 'nunca_conversou',
    });
    expect(itens).toHaveLength(71);
    expect(itens.every(p => p.last_activity_at === null)).toBe(true);
  });
});

describe('listar: ordem', () => {
  it('ordena por última conversa, da mais recente, com quem nunca conversou no fim', async () => {
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      ordem: 'ultima_conversa',
    });
    const datas = itens.map(p => p.last_activity_at);
    const comData = datas.filter(d => d !== null);
    expect(comData).toEqual([...comData].sort((a, b) => b - a));
    expect(datas.slice(-71).every(d => d === null)).toBe(true);
  });

  it('ordena por nome', async () => {
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      ordem: 'nome',
    });
    const nomes = itens.map(p => p.name);
    expect(nomes).toEqual(
      [...nomes].sort((a, b) => a.localeCompare(b, 'pt-BR'))
    );
  });

  it('ordena por mais novos', async () => {
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      ordem: 'mais_novos',
    });
    const criados = itens.map(p => p.created_at);
    expect(criados).toEqual([...criados].sort((a, b) => b - a));
  });

  it('usa a última conversa quando a ordem não vem', async () => {
    const a = await cheia().listar({ aba: 'pessoas', pagina: 1 });
    const b = await cheia().listar({
      aba: 'pessoas',
      ordem: 'ultima_conversa',
      pagina: 1,
    });
    expect(a.itens.map(p => p.id)).toEqual(b.itens.map(p => p.id));
  });
});

describe('listar: busca', () => {
  const buscarNome = async busca =>
    cheia().listar({ aba: 'pessoas', busca, pagina: 1 });

  it('acha pela parte do nome, sem ligar para maiúscula e acento', async () => {
    const alvo = (
      await cheia().listar({ aba: 'pessoas', ordem: 'nome', pagina: 1 })
    ).itens[0];
    const pedaco = alvo.name.slice(0, 5);
    const { itens } = await buscarNome(pedaco.toUpperCase());
    expect(itens.map(p => p.id)).toContain(alvo.id);
    expect(
      itens.every(p => p.name.toLowerCase().includes(pedaco.toLowerCase()))
    ).toBe(true);
  });

  it('acha nome com acento digitando sem acento', async () => {
    const todas = await todasAsPaginas(cheia(), { aba: 'pessoas' });
    const comAcento = todas.find(p => p.name.normalize('NFD') !== p.name);
    expect(comAcento).toBeDefined();
    const semAcento = comAcento.name
      .normalize('NFD')
      .split('')
      .filter(c => c.charCodeAt(0) < 0x300)
      .join('');
    const { itens } = await buscarNome(semAcento);
    expect(itens.map(p => p.id)).toContain(comAcento.id);
  });

  it('acha pelo telefone, com ou sem formatação', async () => {
    const todas = await todasAsPaginas(cheia(), { aba: 'pessoas' });
    const alvo = todas.find(p => p.phone_number);
    const digitos = alvo.phone_number.slice(-8);
    const formatado = `${digitos.slice(0, 4)}-${digitos.slice(4)}`;
    expect((await buscarNome(digitos)).itens.map(p => p.id)).toContain(alvo.id);
    expect((await buscarNome(formatado)).itens.map(p => p.id)).toContain(
      alvo.id
    );
  });

  it('acha pelo documento', async () => {
    const todas = await todasAsPaginas(cheia(), { aba: 'pessoas' });
    const alvo = todas.find(p => p.custom_attributes.cpf);
    const { itens } = await buscarNome(alvo.custom_attributes.cpf);
    expect(itens.map(p => p.id)).toContain(alvo.id);
  });

  it('devolve zero quando ninguém combina', async () => {
    const { itens, total, temMais } = await buscarNome('zzzzqx');
    expect(itens).toEqual([]);
    expect(total).toBe(0);
    expect(temMais).toBe(false);
  });

  it('trata busca só de espaços como busca vazia', async () => {
    expect((await buscarNome('   ')).total).toBe(280);
  });

  it('combina busca com grupo', async () => {
    const clientes = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      grupo: 'clientes',
    });
    const alvo = clientes[0];
    const { itens } = await cheia().listar({
      aba: 'pessoas',
      grupo: 'nunca_conversou',
      busca: alvo.name,
      pagina: 1,
    });
    expect(itens.map(p => p.id)).not.toContain(alvo.id);
  });

  it('busca empresa pelo nome', async () => {
    const alvo = (
      await cheia().listar({ aba: 'empresas', ordem: 'nome', pagina: 1 })
    ).itens[0];
    const { itens } = await cheia().listar({
      aba: 'empresas',
      busca: alvo.name,
      pagina: 1,
    });
    expect(itens.map(e => e.id)).toContain(alvo.id);
  });
});

describe('demonstração "vazio"', () => {
  it('lista ninguém', async () => {
    expect(
      await vazia().listar({ aba: 'pessoas', grupo: 'todos', pagina: 1 })
    ).toEqual({
      itens: [],
      total: 0,
      temMais: false,
    });
    expect((await vazia().listar({ aba: 'empresas', pagina: 1 })).total).toBe(
      0
    );
  });
});

describe('fonte real', () => {
  it.each(['resumo', 'contagens', 'listar'])(
    '%s diz que a fonte real ainda não existe',
    async metodo => {
      const fonte = listaFonte({ demo: null });
      await expect(fonte[metodo]('pessoas')).rejects.toMatchObject({
        name: 'FONTE_REAL_PENDENTE',
      });
    }
  );

  it('não usa a demonstração quando o módulo de demonstração não carrega', async () => {
    const fonte = listaFonte({ demo: 'cheio', carregarDemo: null });
    await expect(fonte.resumo()).rejects.toMatchObject({
      name: 'FONTE_REAL_PENDENTE',
    });
  });
});
