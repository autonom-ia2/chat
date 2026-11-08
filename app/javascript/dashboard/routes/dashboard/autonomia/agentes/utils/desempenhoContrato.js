// #2226 v2 — leitura do contrato do painel de desempenho (desenho §6), sem nada de tela. Os nomes
// de negócio (tema, marco, resultado, motivo, regra, origem, corte) vivem no `catalogo` do contrato;
// aqui só se procura o nome pelo id. Id sem nome devolve null, e a tela mostra "Sem nome", nunca o id.

// Catálogos em que o nome é texto puro e catálogos em que o nome está dentro de um objeto.
const NOME_DIRETO = ['temas', 'marcos', 'motivos', 'quem'];
const NOME_NO_OBJETO = ['resultados', 'regras', 'origens'];

const textoOuNulo = valor =>
  typeof valor === 'string' && valor.trim() ? valor : null;

export const nomeDe = (catalogo, tipo, id) => {
  const entrada = catalogo?.[tipo]?.[id];
  if (NOME_DIRETO.includes(tipo)) return textoOuNulo(entrada);
  if (NOME_NO_OBJETO.includes(tipo)) return textoOuNulo(entrada?.nome);
  return null;
};

export const nomeDoCorte = (catalogo, corteId, valorId) =>
  textoOuNulo(catalogo?.cortes?.[corteId]?.[valorId]);

// 'fechou' | 'avancou' | 'parou' | 'resolveu' | 'passou' | 'sem_negocio' | null
export const grupoDoResultado = (catalogo, resultadoId) =>
  catalogo?.resultados?.[resultadoId]?.grupo ?? null;

export const fechou = (catalogo, procura) =>
  grupoDoResultado(catalogo, procura?.resultado_id) === 'fechou';

// Os marcos que fazem uma procura chegar a uma etapa. Uma etapa pode juntar mais de um marco
// (ex.: "confirmou ou fez login"); sem a lista, vale o próprio id da etapa.
const marcosDaEtapa = etapa =>
  Array.isArray(etapa.marcos) && etapa.marcos.length
    ? etapa.marcos
    : [etapa.id];

// A etapa do funil mais avançada que a procura alcançou (id da etapa) ou null.
export const marcoMaisLonge = (etapasDoFunil, marcos) => {
  const tem = new Set(marcos || []);
  const alcancada = [...(etapasDoFunil || [])]
    .reverse()
    .find(etapa => marcosDaEtapa(etapa).some(marco => tem.has(marco)));
  return alcancada ? alcancada.id : null;
};

// Porcentagem com 1 casa; null quando a base é 0 (nunca 0 no lugar de "não dá para calcular").
export const pct = (n, m) => {
  const total = Number(m) || 0;
  if (!total) return null;
  return Math.round((1000 * (Number(n) || 0)) / total) / 10;
};

// Os números do topo que aparecem como taxa (o número grande é um %): a comparação é em pontos.
// Os 8 números do topo, na ordem do contrato (§2.1). São universais: o rótulo e a explicação de
// cada um estão no i18n; id fora desta lista não tem texto próprio.
export const KPIS = [
  'procuras',
  'conversas',
  'compra',
  'fecharam',
  'duvidas_resolvidas',
  'sem_pessoa',
  'perdas_evitaveis',
  'tempo_resposta',
];
export const KPIS_EM_TAXA = ['duvidas_resolvidas'];

const sentidoDe = (diferenca, melhor) => {
  if (!diferenca || !melhor) return 'neutro';
  const subiu = diferenca > 0;
  const bom = melhor === 'subir' ? subiu : !subiu;
  return bom ? 'favoravel' : 'desfavoravel';
};

// A comparação de um KPI com o período anterior. Sem anterior, null. Taxa compara em pontos
// ({ diferenca, unidade: 'pontos' }) e só quando há a base anterior; senão, não compara.
export const delta = kpi => {
  if (!kpi || kpi.anterior === null || kpi.anterior === undefined) return null;
  if (KPIS_EM_TAXA.includes(kpi.id)) {
    const agora = pct(kpi.base?.n, kpi.base?.m);
    const antes = pct(kpi.anterior_base?.n, kpi.anterior_base?.m);
    if (agora === null || antes === null) return null;
    const diferenca = Math.round((agora - antes) * 10) / 10;
    return {
      diferenca,
      unidade: 'pontos',
      sentido: sentidoDe(diferenca, kpi.melhor),
    };
  }
  const diferenca = Number(kpi.valor) - Number(kpi.anterior);
  if (Number.isNaN(diferenca)) return null;
  return {
    diferenca,
    unidade: 'valor',
    sentido: sentidoDe(diferenca, kpi.melhor),
  };
};

// Abaixo desta base, a taxa aparece com o aviso "poucos casos" e nunca em destaque.
export const MINIMO_DA_TAXA = 5;
export const poucosCasos = base =>
  Number(base) > 0 && Number(base) < MINIMO_DA_TAXA;

// O nome da IA para usar no meio da frase ("Duda mandou…"): o primeiro nome do agente.
export const nomeCurtoDoAgente = (nome, reserva = '') => {
  const texto = String(nome || '').trim();
  return texto ? texto.split(' ')[0] : reserva;
};

// As ressalvas da conferência que valem para uma parte do painel (campo com `nota` e que afeta a
// parte): ficam perto do número, não só no fim.
export const ressalvasDe = (painel, parte) =>
  (painel?.confianca?.campos || []).filter(
    campo => campo.nota && (campo.afeta || []).includes(parte)
  );

// Link da conversa pelo número que a pessoa vê na caixa (display_id); a conta vem da rota atual.
export const hrefDaConversa = (router, conversa) =>
  router.resolve({
    name: 'inbox_conversation',
    params: { conversation_id: conversa },
  }).href;

// 'AAAA-MM-DDTHH:mm' -> 'AAAA-MM-DD', sem Date (a hora já vem no fuso da conta).
export const diaDe = dataHora => String(dataHora || '').slice(0, 10);

// Uma taxa só ganha cor de destaque ("a maior", "a melhor") com base de pelo menos isto; abaixo, aparece
// sem destaque (e, abaixo de MINIMO_DA_TAXA, com o aviso "poucos casos").
export const MINIMO_DO_DESTAQUE = 20;
export const podeDestacar = base => Number(base) >= MINIMO_DO_DESTAQUE;

// A maior trava de quem pediu compra: o jeito mais comum de uma procura de compra terminar sem
// fechar, na base das procuras de compra do período (sem testes). É o mesmo fato que as sugestões
// usam, na mesma base, para a tela não mostrar dois números para a mesma coisa. Os motivos
// anotados (outra base) ficam só na seção de perdas. Sem procura de compra: null.
export const maiorTravaDaCompra = painel => {
  const compra = (painel?.procuras || []).filter(
    procura => procura.compra && !procura.teste
  );
  if (!compra.length) return null;
  const contagem = compra.reduce((acc, procura) => {
    if (fechou(painel.catalogo, procura)) return acc;
    acc[procura.resultado_id] = (acc[procura.resultado_id] || 0) + 1;
    return acc;
  }, {});
  const [id, n] =
    Object.entries(contagem).sort(
      ([idA, a], [idB, b]) => b - a || idA.localeCompare(idB)
    )[0] || [];
  if (!id) return null;
  return {
    id,
    nome: nomeDe(painel.catalogo, 'resultados', id),
    n,
    m: compra.length,
    pct: pct(n, compra.length),
  };
};

// O ganho que disputa "por onde começar": o do período. Ganho do histórico completo (o período não deu
// para estimar) não compete com ganho do período.
const ganhoDoPeriodo = item =>
  item?.ganho?.historico ? -1 : (item?.ganho?.fechamentos ?? -1);

// A sugestão para começar: entre as que já dá para usar, a de maior ganho estimado em vendas no período.
export const sugestaoPrincipal = painel =>
  (painel?.recomendacoes || [])
    .filter(item => item.pronto === 'ja_da')
    .reduce(
      (melhor, item) =>
        !melhor || ganhoDoPeriodo(item) > ganhoDoPeriodo(melhor)
          ? item
          : melhor,
      null
    );

// Até 90 dias a duração de um ganho fica em dias ("30 dias"); acima, em meses ("4 meses"), igual ao PDF.
const MAIOR_DURACAO_EM_DIAS = 90;
const DIAS_POR_MES = 30.44;
export const duracaoDoGanho = dias =>
  dias <= MAIOR_DURACAO_EM_DIAS
    ? { unidade: 'DIAS', n: dias }
    : { unidade: 'MESES', n: Math.round(dias / DIAS_POR_MES) };

// De que datas é um ganho: o do próprio ganho ou, sem ele, o período do painel.
export const periodoDoGanho = (ganho, painel) =>
  ganho?.periodo || painel?.meta?.periodo || null;
