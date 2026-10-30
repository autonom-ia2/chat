import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { explicar401 } from '../salvarFuncao';

// Apagar uma função da lista (#2308, especificação 5.E). `apagarRef` é o diálogo (ApagarFuncao), `pessoasDa` diz
// quem usa a função, `carregar` recarrega as funções e `carregarPessoas` as pessoas, pelo caminho da página: uma
// recarga que falha vira "Não deu para ver quem usa", nunca "Ninguém usa" (revisão do #2308, rodada 4). Devolve se
// carregou. As recusas falam de apagar, não de salvar nem de dar, e nunca mostram o texto cru do servidor. `apagar`
// só volta quando acabou: o diálogo fica em "Apagando…" até lá.
export function useApagarFuncao({
  apagarRef,
  pessoasDa,
  carregar,
  carregarPessoas,
}) {
  const store = useStore();
  const { t } = useI18n();

  const pedirParaApagar = (funcao, mensagem) =>
    apagarRef.value?.abrir(funcao, mensagem);

  // O servidor recusou: a lista de agentes estava velha (achou gente), a função de destino sumiu ou saiu do alcance,
  // ou alguém mudou a função no meio. A tela recarrega o que mudou e pergunta de novo, dizendo por quê. Se a recarga
  // das pessoas falhou, pergunta também: o diálogo diz, num alerta só, que ainda tem gente e não deu para ver quem, e
  // oferece tentar. Se a recarga mostra a função vazia (esvaziou no meio), volta sem destino, dizendo que ela mudou
  // (revisão do #2308, rodada 6).
  const motivoDoDestino = (funcao, carregou) => {
    if (!carregou) return 'RECUSA.TEM_GENTE_SEM_VER';
    return pessoasDa(funcao).length ? 'RECUSA.TEM_GENTE' : 'MUDOU';
  };
  const RECUSAS = {
    destination_required: async funcao => {
      const carregou = await carregarPessoas();
      pedirParaApagar(
        funcao,
        t(`FUNCOES_EQUIPE.APAGAR.${motivoDoDestino(funcao, carregou)}`)
      );
    },
    destination_invalid: async funcao => {
      await store.dispatch('customRole/getCustomRole');
      pedirParaApagar(funcao, t('FUNCOES_EQUIPE.APAGAR.INDISPONIVEL'));
    },
    changed_meanwhile: async () => {
      useAlert(t('FUNCOES_EQUIPE.APAGAR.MUDOU'));
      await Promise.all([carregar(), carregarPessoas()]);
    },
  };

  const apagar = async ({ funcao, destino }) => {
    try {
      await store.dispatch('customRole/deleteCustomRole', {
        id: funcao.id,
        destinationRoleId: destino,
      });
      if (destino) carregarPessoas();
      useAlert(t('FUNCOES_EQUIPE.APAGAR.APAGADA', { nome: funcao.name }));
    } catch (error) {
      const recusa = RECUSAS[error?.code];
      if (recusa) {
        await recusa(funcao);
        return;
      }
      if (error?.status !== 401) {
        useAlert(t('FUNCOES_EQUIPE.APAGAR.ERRO'));
        return;
      }
      // Sessão vencida: o app vai para o login, sem mensagem; sessão boa: o motivo, com frases de apagar.
      const { erro } = await explicar401(error.code);
      if (erro) useAlert(t(`FUNCOES_EQUIPE.APAGAR.RECUSA.${erro}`));
    }
  };

  return { pedirParaApagar, apagar };
}
