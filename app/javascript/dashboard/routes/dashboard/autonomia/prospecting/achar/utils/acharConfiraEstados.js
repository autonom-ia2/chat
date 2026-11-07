// #2692 — os estados ?demo= que abrem algo por cima da lista (gaveta, folha,
// pronto). Os outros estados da página Confira são estados da própria lista.
// `pessoa` só muda quem fica com as empresas quando o estado diz.
const LUCAS = 7;

export const SOBRE_A_LISTA = {
  gaveta: { gaveta: 'ver' },
  'gaveta-mandar': { gaveta: 'mandar' },
  'gaveta-mandou': { gaveta: 'mandou' },
  'gaveta-leitura': { gaveta: 'ver', leitura: true },
  'gaveta-no-funil': { gaveta: 'ver', empresa: 'no_funil' },
  'gaveta-sem-dono': { gaveta: 'ver', empresa: 'sem_dono' },
  'gaveta-nao-serve': { gaveta: 'nao-serve' },
  'gaveta-nao-quer': { gaveta: 'nao-quer' },
  folha: { folha: null },
  'folha-funil': { folha: 'funil' },
  'folha-funil-agente': { folha: 'funil', semTrocar: true },
  'folha-com-quem': { folha: 'funil', subpainel: 'pessoa' },
  'folha-com-lucas': { folha: 'funil', pessoa: LUCAS },
  'folha-fora': { folha: 'funil', mostrarFora: true },
  'folha-sem-destino': { folha: 'funil' },
  'folha-para-onde': { folha: 'funil', subpainel: 'destino' },
  // Parado no meio do envio (9 de 14), para a tela "Mandando…" ser vista.
  'folha-enviando': { folha: 'funil', enviandoParado: true },
  'folha-erro': { folha: 'funil', enviar: true },
  'folha-lista': { folha: 'lista' },
  pronto: { pronto: 'funil' },
  'pronto-com-lucas': { pronto: 'funil', pessoa: LUCAS },
  'pronto-uma': { pronto: 'funil', uma: true },
  'pronto-ja-estavam': { pronto: 'funil', jaEstavam: 2 },
  guardada: { pronto: 'lista' },
};

export const PASSO_DA_GAVETA = {
  ver: 'gaveta',
  mandar: 'gaveta-mandar',
  mandou: 'gaveta-mandou',
  'nao-serve': 'gaveta-nao-serve',
  'nao-quer': 'gaveta-nao-quer',
};

export const ESTADOS_LEITURA = ['leitura', 'leitura-vazia', 'gaveta-leitura'];

// Que grupos da lista abrem em cada estado. Por padrão todos abrem, menos
// "Ficam de fora". `confira-grupos` e `confira-fora` fecham os de cima para os
// grupos de baixo caberem na tela.
const GRUPOS_ABERTOS = {
  'confira-grupos': ['media', 'pouca'],
  'confira-fora': ['fora'],
};
export const grupoAbre = (estado, chave) =>
  GRUPOS_ABERTOS[estado]
    ? GRUPOS_ABERTOS[estado].includes(chave)
    : chave !== 'fora';

export const ehEstadoDaLista = estado => !SOBRE_A_LISTA[estado];

// Nos estados que abrem os grupos de baixo, a lista já abre rolada até eles
// (o primeiro grupo aberto daquele estado), para que dê para vê-los.
export const grupoEmFoco = estado => GRUPOS_ABERTOS[estado]?.[0] || null;

// Busca de nome sem expressão regular: minúsculas e sem acento, e "contém".
const semAcento = texto =>
  texto
    .normalize('NFD')
    .split('')
    .filter(letra => letra.charCodeAt(0) < 0x300 || letra.charCodeAt(0) > 0x36f)
    .join('')
    .toLowerCase();

export const temNoNome = (nome, procura) =>
  !procura.trim() || semAcento(nome).includes(semAcento(procura.trim()));

const contarPor = (itens, chave) =>
  Object.entries(
    itens.reduce(
      (soma, item) => ({
        ...soma,
        [chave(item)]: (soma[chave(item)] || 0) + 1,
      }),
      {}
    )
  ).map(([motivo, n]) => ({ motivo, n }));

// Por que {n} da busca não vão: os motivos do sistema (no funil, não quer,
// fechou) e as que a própria pessoa tirou. A soma com as escolhidas dá as
// achadas (rodada 2: a conta fecha).
export const naoVao = (empresas, tiradas = 0, mandadas = 0) => [
  ...contarPor(
    empresas.filter(empresa => empresa.fora),
    empresa => empresa.fora.motivo
  ),
  ...(tiradas ? [{ motivo: 'voce_tirou', n: tiradas }] : []),
  ...(mandadas ? [{ motivo: 'voce_mandou', n: mandadas }] : []),
];

// Das escolhidas, quem não pode entrar na lista de mensagem: sem celular nem
// e-mail (o servidor cria contato só de quem entra, v4 F3).
export const foraDaLista = escolhidas => {
  const sem = escolhidas.filter(empresa => !empresa.temContato).length;
  return sem ? [{ motivo: 'sem_contato', n: sem }] : [];
};

// Título e detalhes de T2 (funil) e T3 (lista guardada).
export const textosDoPronto = (t, { pronto, destino, pessoa, nomeLista }) => {
  if (!pronto) return { titulo: '', detalhes: [] };
  const NS = 'PROSPECTING_ACHAR.PRONTO';
  if (pronto.tipo === 'lista') {
    return {
      titulo: t(`${NS}.LISTA.TITULO`),
      detalhes: [
        t(`${NS}.LISTA.DETALHE`, { nome: nomeLista, n: pronto.n }),
        t('PROSPECTING_ACHAR.FOLHA.ONDE_FICA'),
      ],
    };
  }
  const base = { funil: destino?.funil.nome, pessoa };
  return {
    titulo:
      pronto.n === 1
        ? t(`${NS}.UMA`, { ...base, nome: pronto.nome })
        : t(`${NS}.VARIAS`, { ...base, n: pronto.n }),
    detalhes: [
      t(`${NS}.DETALHE`, { etapa: destino?.etapa.nome }),
      pronto.jaEstavam ? t(`${NS}.JA_ESTAVAM`, { n: pronto.jaEstavam }) : '',
    ].filter(Boolean),
  };
};

// Demonstração (rodada 4): a empresa mandada pela gaveta segue para os estados
// seguintes pela URL e sai da conta do "vão" (fonte única de números).
export const comoMandada = (empresa, pessoa) => ({
  ...empresa,
  mandada: 'Vendas',
  noFunil: { funil: 'Vendas', etapa: 'Novo contato', pessoa },
});

// A empresa que a gaveta abre quando a URL da demonstração não diz qual
// (saiu de AcharConfiraPage.vue, trava de 600 linhas).
export const empresaPadraoDaGaveta = (tipo, { deFora, elegiveis }) => {
  if (tipo === 'no_funil') {
    return deFora.find(empresa => empresa.fora.motivo === 'no_funil');
  }
  if (tipo === 'sem_dono') {
    return elegiveis.find(empresa => empresa.dono.estado === 'nenhum');
  }
  return elegiveis[0];
};
