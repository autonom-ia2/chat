// #2283 — os parâmetros da Lista nova para /crm/cards e /crm/cards/summaries.
// Os filtros da gaveta valem como na Lista de sempre (listQueryParams); a aba,
// a chave "De todos | Só meus", o "Ver só estes" e a busca são da Lista nova.
import { listQueryParams } from 'dashboard/store/modules/crmKanban';
import { resultadoDaAba } from './grupos';

export const POR_PAGINA = 50;

export const emAndamento = aba => aba === 'aberto' || aba === 'tudo';

const filtrosDaGaveta = (filtros, pipelineId) =>
  listQueryParams({ ...filtros, result: '', search: '' }, { pipelineId });

export const parametrosDaLista = ({
  filtros,
  pipelineId,
  aba,
  statuses,
  quem,
  grupoSo,
  busca,
}) => {
  const resultado = resultadoDaAba(aba, statuses);
  const termo = String(busca || '').trim();
  return {
    ...filtrosDaGaveta(filtros, pipelineId),
    ...(resultado ? { result: resultado } : {}),
    // Em andamento e Tudo: o que fazer primeiro. Ganhos, Perdidos e
    // Arquivados: o mais recente primeiro.
    ...(emAndamento(aba)
      ? { sort: 'acao' }
      : { sort: 'updated_at', direction: 'desc' }),
    ...(quem === 'meus' ? { mine: true } : {}),
    ...(grupoSo && emAndamento(aba) ? { action_group: grupoSo } : {}),
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
