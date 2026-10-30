// #2283 — os parâmetros da Lista nova para /crm/cards e /crm/cards/summaries.
// Os filtros da gaveta valem como na Lista de sempre (listQueryParams); a aba,
// a chave "De todos | Só meus", o "Ver só estes" e a busca são da Lista nova.
import { listQueryParams } from 'dashboard/store/modules/crmKanban';
import { resultadoDaAba } from './grupos';
import { PADRAO, RESUMO } from './organizar';

export const POR_PAGINA = 50;

export const emAndamento = aba => aba === 'aberto' || aba === 'tudo';

const filtrosDaGaveta = (filtros, pipelineId) =>
  listQueryParams({ ...filtros, result: '', search: '' }, { pipelineId });

// "Organizar por" (#2379). O padrão: o que fazer primeiro em Em andamento e
// Tudo; nas abas de desfecho, o mais recente primeiro.
const ordemDaLista = (organizar, aba) => {
  if (organizar && organizar !== PADRAO) return { sort: organizar };
  return emAndamento(aba)
    ? { sort: 'acao' }
    : { sort: 'updated_at', direction: 'desc' };
};

export const parametrosDaLista = ({
  filtros,
  pipelineId,
  aba,
  statuses,
  quem,
  grupoSo,
  busca,
  organizar,
}) => {
  const resultado = resultadoDaAba(aba, statuses);
  const termo = String(busca || '').trim();
  return {
    ...filtrosDaGaveta(filtros, pipelineId),
    ...(resultado ? { result: resultado } : {}),
    ...ordemDaLista(organizar, aba),
    ...(quem === 'meus' ? { mine: true } : {}),
    // "Ver só estes" é dos grupos de ação (o padrão de "Organizar por").
    ...(grupoSo && emAndamento(aba) && (!organizar || organizar === PADRAO)
      ? { action_group: grupoSo }
      : {}),
    ...(termo ? { search: termo } : {}),
  };
};

// A contagem dos grupos (herói, número do grupo, "Ver só estes"): sempre dos
// clientes em andamento, com os mesmos filtros e a mesma chave de quem.
export const parametrosDaContagem = ({ filtros, pipelineId, quem, busca }) => {
  const termo = String(busca || '').trim();
  return {
    ...filtrosDaGaveta(filtros, pipelineId),
    result: 'open',
    group_by: 'acao',
    ...(quem === 'meus' ? { mine: true } : {}),
    ...(termo ? { search: termo } : {}),
  };
};

// A contagem dos grupos de "Etapa" e "Quem cuida": o mesmo recorte da lista
// (aba, chave, filtros e busca), agrupado no servidor.
export const parametrosDoResumo = estado => {
  const groupBy = RESUMO[estado.organizar];
  if (!groupBy) return null;
  // Sem a ordem: a contagem não precisa dela (e o servidor pularia os JOINs dela).
  const { sort, direction, ...lista } = parametrosDaLista(estado);
  return { ...lista, group_by: groupBy };
};
