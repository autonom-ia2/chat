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
  'gaveta-outra-pessoa': { gaveta: 'outra-pessoa' },
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
  'outra-pessoa': 'gaveta-outra-pessoa',
};

export const ESTADOS_LEITURA = ['leitura', 'leitura-vazia', 'gaveta-leitura'];

// Que grupos da lista abrem em cada estado. Por padrão todos abrem, menos
// "Ficam de fora". `confira-grupos` e `confira-fora` fecham os de cima para os
// grupos de baixo caberem na tela.
// Sem estado da demonstração, "Ficam de fora" e "Tiradas da lista" começam
// fechados.
const GRUPOS_FECHADOS = ['fora', 'tiradas'];
const GRUPOS_ABERTOS = {
  'confira-grupos': ['media', 'pouca'],
  'confira-fora': ['fora'],
};
export const grupoAbre = (estado, chave) =>
  GRUPOS_ABERTOS[estado]
    ? GRUPOS_ABERTOS[estado].includes(chave)
    : !GRUPOS_FECHADOS.includes(chave);

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

// "Não serve" (o lead descartado, nesta busca ou antes): conta em "você
// tirou", não em "ficam de fora" (que é só quem o sistema barra).
import { MOTIVO_NAO_SERVE } from './acharLead';

export { MOTIVO_NAO_SERVE };

// Barrada pelo sistema: no funil, não quer ou fechou.
export const ehBarrada = empresa =>
  Boolean(empresa.fora) && empresa.fora.motivo !== MOTIVO_NAO_SERVE;

// As contas da lista (P3 da crítica r5), que fecham sempre nas achadas:
// achadas = vão + você tirou + ficam de fora + você já mandou. "Ficam de fora"
// é só quem o sistema barra (no funil, não quer, fechou); a empresa mandada
// tem conta própria; "Não serve" nesta busca soma em "você tirou".
export const contasDaLista = ({ empresas, elegiveis, escolhidas }) => {
  const mandadas = elegiveis.filter(empresa => empresa.mandada).length;
  const barradas = empresas.filter(ehBarrada).length;
  const naoServem = empresas.length - elegiveis.length - barradas;
  return {
    achadas: empresas.length,
    vao: escolhidas.length,
    tiradas: elegiveis.length - escolhidas.length - mandadas + naoServem,
    fora: barradas,
    mandadas,
  };
};

// Por que {n} da busca não vão: os motivos do sistema (no funil, não quer,
// fechou) e as que a própria pessoa tirou. A mandada pela gaveta não entra:
// ela foi, e a folha a mostra à parte.
export const naoVao = (empresas, tiradas = 0) => [
  ...contarPor(empresas.filter(ehBarrada), empresa => empresa.fora.motivo),
  ...(tiradas ? [{ motivo: 'voce_tirou', n: tiradas }] : []),
];

// Das escolhidas, quem não pode entrar na lista de mensagem: sem celular nem
// e-mail (o servidor cria contato só de quem entra, v4 F3).
export const foraDaLista = escolhidas => {
  const sem = escolhidas.filter(empresa => !empresa.temContato).length;
  return sem ? [{ motivo: 'sem_contato', n: sem }] : [];
};

// O título de T2: quantas novas entraram (nenhuma, uma ou várias).
const tituloDoFunil = (t, { pronto, base }) => {
  const NS = 'PROSPECTING_ACHAR.PRONTO';
  if (!pronto.n) return t(`${NS}.NENHUMA_NOVA`, base);
  if (pronto.n === 1) return t(`${NS}.UMA`, { ...base, nome: pronto.nome });
  return t(`${NS}.VARIAS`, { ...base, n: pronto.n });
};

// Quem ficou fora do Público (#2695), pelo motivo do servidor, em frases de
// leigo: uma linha por motivo, com quantas. As falhas do servidor viram uma.
const FORA_DO_PUBLICO = {
  opt_out: 'NAO_QUER',
  contact_blocked: 'BLOQUEADO',
  no_channel: 'SEM_CONTATO',
  same_contact: 'MESMA_PESSOA',
  discarded: 'TIRADA',
  not_found: 'SUMIU',
  invalid_data: 'NAO_DEU',
  unexpected_error: 'NAO_DEU',
  already_in_list: 'JA_ESTAVA',
};

export const foraDoPublico = (t, fora = []) => {
  const porChave = fora.reduce((contas, { motivo }) => {
    const chave = FORA_DO_PUBLICO[motivo] || 'NAO_DEU';
    return { ...contas, [chave]: (contas[chave] || 0) + 1 };
  }, {});
  return Object.entries(porChave).map(([chave, n]) =>
    t(`PROSPECTING_ACHAR.PRONTO.LISTA.FORA.${chave}`, { n }, n)
  );
};

// Título e detalhes de T2 (funil) e T3 (lista guardada).
export const textosDoPronto = (t, { pronto, destino, pessoa, nomeLista }) => {
  if (!pronto) return { titulo: '', detalhes: [] };
  const NS = 'PROSPECTING_ACHAR.PRONTO';
  if (pronto.tipo === 'lista') {
    return {
      titulo: t(`${NS}.LISTA.TITULO`),
      detalhes: [
        // Numa lista que já existia (#2775), o nome é o dela.
        t(`${NS}.LISTA.DETALHE`, {
          nome: pronto.nome || nomeLista,
          n: pronto.n,
        }),
        ...foraDoPublico(t, pronto.fora),
        t('PROSPECTING_ACHAR.FOLHA.ONDE_FICA'),
      ],
    };
  }
  const base = { funil: destino?.funil.nome, pessoa };
  const falharam = pronto.falharam || 0;
  return {
    titulo: tituloDoFunil(t, { pronto, base }),
    detalhes: [
      pronto.n ? t(`${NS}.DETALHE`, { etapa: destino?.etapa.nome }) : '',
      pronto.jaEstavam ? t(`${NS}.JA_ESTAVAM`, { n: pronto.jaEstavam }) : '',
      // As que falharam continuam na lista, com o "Vai": dá para mandar de novo.
      falharam ? t(`${NS}.FALHARAM`, { n: falharam }, falharam) : '',
      falharam ? t(`${NS}.FALHARAM_O_QUE_FAZER`) : '',
    ].filter(Boolean),
  };
};

// A empresa que entrou no funil agora (gaveta ou folha) deixa o "Vai" e diz
// onde está. A nova (created) entrou no destino escolhido, com quem mandou; a
// que já tinha card (existing) está num funil que a resposta não diz qual.
export const mandadaAgora = (
  empresa,
  { destino, pessoa, cardId = null, nova = true }
) => ({
  ...empresa,
  mandada: true,
  fora: null,
  noFunil: nova
    ? {
        funil: destino?.funil.nome,
        etapa: destino?.etapa?.nome,
        pessoa,
        funilId: destino?.funil.id,
        cardId,
      }
    : { cardId },
});

// O resumo do envio aplicado na lista: created e existing viram mandadas.
export const marcarEnviadas = (trocar, resumo, { destino, pessoa }) => {
  resumo.created.forEach(({ id, cardId }) =>
    trocar(id, item => mandadaAgora(item, { destino, pessoa, cardId }))
  );
  resumo.existing.forEach(({ id, cardId }) =>
    trocar(id, item =>
      mandadaAgora(item, { destino, pessoa, cardId, nova: false })
    )
  );
};

// Demonstração (rodada 4): a empresa mandada pela gaveta segue para os estados
// seguintes pela URL e sai da conta do "vão" (fonte única de números).
export const comoMandada = (empresa, pessoa) =>
  mandadaAgora(empresa, {
    destino: { funil: { nome: 'Vendas' }, etapa: { nome: 'Novo contato' } },
    pessoa,
  });

// A empresa nova que chega do servidor fora da busca (evento ao vivo
// prospecting.lead.updated, "Usar esta pessoa", "Buscar de novo") vem no
// formato do lead (LeadPayload), com a prioridade do lead e não a desta busca
// (search_scoring_payload). A empresa fica no grupo em que a busca a pôs.
// E a mandada pela gaveta nesta visita segue "você já mandou", não "já está
// no funil" (P3 da crítica r5).
export const atualizarDaBusca = (antiga, nova) => {
  if (!antiga) return nova;
  const daBusca = {
    ...nova,
    prioridade: antiga.prioridade,
    chance: antiga.chance,
  };
  return antiga.mandada
    ? {
        ...daBusca,
        mandada: antiga.mandada,
        fora: null,
        noFunil: daBusca.noFunil || antiga.noFunil,
      }
    : daBusca;
};

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
