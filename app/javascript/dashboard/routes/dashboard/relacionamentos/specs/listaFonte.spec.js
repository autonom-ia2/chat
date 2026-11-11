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
    expect(await cheia().resumo()).toMatchObject({
      total: 280,
      clientes: 120,
      sumiu_1_a_3_meses: 42,
    });
  });

  it('traz também as empresas: quantas e quantas estão sem conversa há 3 meses', async () => {
    const { empresas } = await cheia().resumo();
    const todas = await cheia().listarTodos({
      aba: 'empresas',
      grupo: 'todas',
    });
    const paradas = await cheia().listarTodos({
      aba: 'empresas',
      grupo: 'sem_conversa_3_meses',
    });
    expect(empresas).toEqual({
      total: todas.total,
      sem_conversa_3_meses: paradas.total,
    });
    expect(empresas.total).toBe(38);
  });

  it('o número da frase é o total do grupo para onde o botão leva', async () => {
    const { sumiu_1_a_3_meses: sumiram } = await cheia().resumo();
    const grupo = await cheia().listarTodos({ grupo: 'sumiu_1_a_3_meses' });
    expect(sumiram).toBe(grupo.total);
  });

  it('zera tudo na conta vazia', async () => {
    expect(await vazia().resumo()).toMatchObject({
      total: 0,
      clientes: 0,
      sumiu_1_a_3_meses: 0,
    });
  });
});

describe('contagens com busca e filtros', () => {
  it('conta só quem combina com a busca, igual ao que a lista mostra', async () => {
    const fonte = cheia();
    const { itens } = await fonte.listar({ grupo: 'todos' });
    const busca = itens[0].name;
    const contagens = await fonte.contagens('pessoas', { busca });
    const achados = await fonte.listarTodos({ grupo: 'todos', busca });
    expect(contagens.todos).toBe(achados.total);
    expect(contagens.todos).toBeLessThan(280);
    expect(contagens.todos).toBeGreaterThan(0);
  });

  it('busca sem ninguém zera todos os grupos', async () => {
    const contagens = await cheia().contagens('pessoas', { busca: 'zzzzqx' });
    expect(Object.values(contagens).every(n => n === 0)).toBe(true);
  });

  it('conta só quem passa nos filtros', async () => {
    const fonte = cheia();
    const filtros = { cidade: 'Santos' };
    const contagens = await fonte.contagens('pessoas', { filtros });
    const achados = await fonte.listarTodos({ grupo: 'todos', filtros });
    expect(contagens.todos).toBe(achados.total);
    expect(contagens.todos).toBeLessThan(280);
  });

  it('busca em empresas também vale', async () => {
    const fonte = cheia();
    const { itens } = await fonte.listar({ aba: 'empresas', grupo: 'todas' });
    const busca = itens[0].name;
    const contagens = await fonte.contagens('empresas', { busca });
    expect(contagens.todas).toBeGreaterThan(0);
    expect(contagens.todas).toBeLessThan(38);
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

describe('listar: filtros de "Mais filtros" (#2894)', () => {
  const pessoas = () => todasAsPaginas(cheia(), { aba: 'pessoas' });

  it('só traz quem é da empresa escolhida', async () => {
    const todas = await pessoas();
    const empresa = todas.find(p => p.company_id).company_id;
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      filtros: { empresa },
    });
    expect(itens.length).toBeGreaterThan(0);
    expect(itens.every(p => p.company_id === empresa)).toBe(true);
    expect(itens.length).toBeLessThan(todas.length);
  });

  it('só traz quem tem a etiqueta e mora na cidade escolhidas', async () => {
    const todas = await pessoas();
    const { labels, additional_attributes: extra } = todas[0];
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      filtros: { etiqueta: labels[0], cidade: extra.city },
    });
    expect(itens.map(p => p.id)).toContain(todas[0].id);
    expect(
      itens.every(
        p =>
          p.labels.includes(labels[0]) &&
          p.additional_attributes.city === extra.city
      )
    ).toBe(true);
  });

  it('só traz quem chegou no período escolhido', async () => {
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      filtros: { chegouEm: 'ultimos_30' },
    });
    const limite = Date.now() / 1000 - 30 * 24 * 60 * 60;
    expect(itens.every(p => p.created_at >= limite)).toBe(true);
  });

  it('soma filtro com grupo e busca', async () => {
    const clientes = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      grupo: 'clientes',
    });
    const cidade = clientes[0].additional_attributes.city;
    const itens = await todasAsPaginas(cheia(), {
      aba: 'pessoas',
      grupo: 'clientes',
      filtros: { cidade },
    });
    expect(itens.every(p => p.contact_type === 'customer')).toBe(true);
    expect(itens.every(p => p.additional_attributes.city === cidade)).toBe(
      true
    );
  });

  it('não filtra empresas por filtro de pessoa', async () => {
    const { total } = await cheia().listar({
      aba: 'empresas',
      filtros: { cidade: 'Inexistente' },
    });
    expect(total).toBe(38);
  });
});

describe('listarTodos', () => {
  it('traz todos os 42 de um grupo de uma vez, sem paginar', async () => {
    const { itens, total } = await cheia().listarTodos({
      aba: 'pessoas',
      grupo: 'sumiu_1_a_3_meses',
    });
    expect(total).toBe(42);
    expect(itens).toHaveLength(42);
  });

  it('respeita a busca', async () => {
    const { itens } = await cheia().listarTodos({
      aba: 'pessoas',
      busca: 'zzzzqx',
    });
    expect(itens).toEqual([]);
  });
});

describe('opcoesDeFiltro', () => {
  it('oferece só empresas, etiquetas e cidades que existem na base', async () => {
    const { empresas, etiquetas, cidades } = await cheia().opcoesDeFiltro();
    expect(empresas).toHaveLength(38);
    expect(empresas[0]).toEqual({
      value: expect.any(Number),
      label: expect.any(String),
    });
    expect(etiquetas.map(o => o.value)).toEqual(
      [...etiquetas.map(o => o.value)].sort()
    );
    expect(etiquetas.length).toBeGreaterThan(0);
    expect(cidades.length).toBeGreaterThan(0);
  });

  it('não oferece nada na conta vazia', async () => {
    expect(await vazia().opcoesDeFiltro()).toEqual({
      empresas: [],
      etiquetas: [],
      cidades: [],
    });
  });

  it('diz que a fonte real ainda não existe', async () => {
    await expect(
      listaFonte({ demo: null }).opcoesDeFiltro()
    ).rejects.toMatchObject({ name: 'FONTE_REAL_PENDENTE' });
    await expect(
      listaFonte({ demo: null }).listarTodos({})
    ).rejects.toMatchObject({ name: 'FONTE_REAL_PENDENTE' });
  });
});

describe('?demo=carregando', () => {
  it('a fonte nunca responde, em nenhum método', async () => {
    vi.useFakeTimers();
    const fonte = listaFonte({ demo: 'carregando', atraso: 0 });
    let respondeu = 0;
    ['resumo', 'contagens', 'listar', 'listarTodos', 'opcoesDeFiltro'].forEach(
      metodo => {
        fonte[metodo]('pessoas').then(() => {
          respondeu += 1;
        });
      }
    );
    await vi.advanceTimersByTimeAsync(60000);
    expect(respondeu).toBe(0);
    vi.useRealTimers();
  });
});
