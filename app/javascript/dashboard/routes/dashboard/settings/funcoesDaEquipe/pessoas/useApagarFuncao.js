import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { explicar401 } from '../salvarFuncao';

// Apagar uma função da lista (#2308, especificação 5.E). `apagarRef` é o diálogo (ApagarFuncao), `pessoasDa` diz
// quem usa a função e `carregar` recarrega as funções. As recusas falam de apagar, não de salvar nem de dar.
export function useApagarFuncao({ apagarRef, pessoasDa, carregar }) {
  const store = useStore();
  const { t } = useI18n();

  const pedirParaApagar = (funcao, mensagem) =>
    apagarRef.value?.abrir(funcao, pessoasDa(funcao).length, mensagem);

  // O servidor recusou: a lista de agentes estava velha (achou gente), a função de destino sumiu ou saiu do alcance,
  // ou alguém mudou a função no meio. A tela recarrega o que mudou e pergunta de novo.
  const RECUSAS = {
    destination_required: async (funcao, mensagem) => {
      await store.dispatch('agents/get');
      if (pessoasDa(funcao).length) pedirParaApagar(funcao);
      else useAlert(mensagem);
    },
    destination_invalid: async funcao => {
      await store.dispatch('customRole/getCustomRole');
      pedirParaApagar(funcao, t('FUNCOES_EQUIPE.APAGAR.INDISPONIVEL'));
    },
    changed_meanwhile: async () => {
      useAlert(t('FUNCOES_EQUIPE.APAGAR.MUDOU'));
      await Promise.all([carregar(), store.dispatch('agents/get')]);
    },
  };

  const apagar = async ({ funcao, destino }) => {
    try {
      await store.dispatch('customRole/deleteCustomRole', {
        id: funcao.id,
        destinationRoleId: destino,
      });
      if (destino) store.dispatch('agents/get');
      useAlert(t('FUNCOES_EQUIPE.APAGAR.APAGADA', { nome: funcao.name }));
    } catch (error) {
      const mensagem = error?.message || t('FUNCOES_EQUIPE.APAGAR.ERRO');
      const recusa = RECUSAS[error?.code];
      if (recusa) {
        await recusa(funcao, mensagem);
        return;
      }
      if (error?.status !== 401) {
        useAlert(mensagem);
        return;
      }
      // Sessão vencida: o app vai para o login, sem mensagem; sessão boa: o motivo, com frases de apagar.
      const { erro } = await explicar401(error.code);
      if (erro) useAlert(t(`FUNCOES_EQUIPE.APAGAR.RECUSA.${erro}`));
    }
  };

  return { pedirParaApagar, apagar };
}
