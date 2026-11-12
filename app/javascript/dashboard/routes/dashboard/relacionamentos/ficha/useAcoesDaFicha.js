// #2894 — as ações que saem da ficha. No protótipo, o que tem rota simples e real
// leva até ela (Abrir no CRM, voltar para a lista); o resto mostra um aviso curto
// dizendo o que vai acontecer, sem mexer em nada.
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

export const useAcoesDaFicha = () => {
  const router = useRouter();
  const { t } = useI18n();

  const avisar = (chave, nome) => useAlert(t(chave, { nome }));

  const irPara = (name, params, query) => router.push({ name, params, query });

  return {
    avisar,
    voltarParaLista: aba =>
      irPara('relationships_home', undefined, aba ? { aba } : undefined),
    abrirPessoa: contactId => irPara('relacionamentos_pessoa', { contactId }),
    abrirEmpresa: companyId => irPara('relacionamentos_empresa', { companyId }),
    abrirNoCrm: () => irPara('crm_kanban_index'),
  };
};
