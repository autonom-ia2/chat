import { modulesWithKeys } from '../../customRoles/permissionMatrix';
import { useTextos } from './useTextos';

// Os textos de um cartão pronto (#2308, especificação 5.B1): capacidades curtas, selo e travas agrupadas por motivo.
// O vazio da lista e a Escolha usam os mesmos.
const TRAVA_POR_MOTIVO = { MISSING: 'NAO_TEM', DELEGATION: 'SO_ADMIN' };

export function useCartao() {
  const { t, te, lista } = useTextos();

  const capacidade = item =>
    item.areas
      ? t(`FUNCOES_EQUIPE.CURTO.${item.chave}`, {
          areas: lista(
            item.areas.map(area => t(`FUNCOES_EQUIPE.AREAS.${area}.CURTO`))
          ),
        })
      : t(`FUNCOES_EQUIPE.CURTO.${item.chave}`);

  const selo = chaves =>
    chaves.length
      ? t('FUNCOES_EQUIPE.CARTAO.SELO', {
          coisas: lista(
            chaves.map(chave => t(`FUNCOES_EQUIPE.CUIDADO.${chave}`))
          ),
        })
      : '';

  // Uma chave sem nome próprio cai na área, com "ver" ou "mudar" pelo nível dela: report_manage é o ver dos
  // Relatórios, e "Sem mudar os relatórios" contradiria o "Vê os relatórios" do cartão (revisão do #2308, rodada 4). A
  // área vai como no meio de uma frase, a mesma forma da Perda de acesso ("Sem ver o desempenho da equipe", rodada 6).
  const semArea = chave => {
    const module = modulesWithKeys([chave])[0];
    const forma = module?.levels?.view === chave ? 'SEM_AREA_VER' : 'SEM_AREA';
    return t(`FUNCOES_EQUIPE.TRAVA.${forma}`, {
      area: t(`FUNCOES_EQUIPE.AREAS.${module?.key}.NA_FRASE`),
    });
  };
  const semCoisa = chave =>
    te(`FUNCOES_EQUIPE.TRAVA.SEM.${chave}`)
      ? t(`FUNCOES_EQUIPE.TRAVA.SEM.${chave}`)
      : semArea(chave);

  const trava = ({ motivo, chaves }) =>
    t(`FUNCOES_EQUIPE.TRAVA.CARTAO.${TRAVA_POR_MOTIVO[motivo]}`, {
      coisas: chaves.map(semCoisa).join(t('FUNCOES_EQUIPE.TRAVA.E_SEM')),
    });

  const nome = chave => t(`FUNCOES_EQUIPE.PRONTAS.${chave}.NOME`);
  const descricao = chave => t(`FUNCOES_EQUIPE.PRONTAS.${chave}.DESCRICAO`);

  return { capacidade, selo, trava, nome, descricao };
}

export const ICONE_DA_CAPACIDADE = {
  pode: 'i-lucide-check text-n-teal-11',
  soOlha: 'i-lucide-eye text-n-slate-11',
  ve: 'i-lucide-eye text-n-slate-11',
  naoFaz: 'i-lucide-x text-n-slate-11',
};
