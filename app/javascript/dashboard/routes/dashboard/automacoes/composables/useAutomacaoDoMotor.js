import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';

// #2889 — a automação do motor novo que o Guia monta na tela da conversa:
// carregar, ligar e desligar. Ligar leva a versão que a tela mostrou; se outra
// pessoa salvou no meio (409), a tela mostra a versão nova antes de deixar
// ligar. O Guia também liga, quando a pessoa pede, e sempre pelo cartão de
// confirmação.
const CONFLITO = 409;

export function useAutomacaoDoMotor(id) {
  const { t } = useI18n();
  const automacao = ref(null);
  const estado = ref(id.value ? 'carregando' : 'pronto');
  const ocupado = ref(false);

  const carregar = async () => {
    if (!id.value) {
      automacao.value = null;
      estado.value = 'pronto';
      return;
    }
    // Recarregar depois de um ajuste do Guia não pisca: o resumo antigo fica
    // até o novo chegar.
    if (automacao.value?.id !== id.value) estado.value = 'carregando';
    try {
      const { data } = await AutomacoesAPI.show(id.value);
      automacao.value = data;
      estado.value = 'pronto';
    } catch {
      automacao.value = null;
      estado.value = 'erro';
    }
  };

  // Ligar e desligar respondem sem a receita: a da tela continua valendo.
  const juntar = dados => {
    automacao.value = {
      ...automacao.value,
      ...dados,
      versao: { ...automacao.value.versao, ...dados.versao },
    };
  };

  const trocar = async ligar => {
    if (!automacao.value || ocupado.value) return;
    ocupado.value = true;
    try {
      const { data } = ligar
        ? await AutomacoesAPI.ligar(
            automacao.value.id,
            automacao.value.versao?.id
          )
        : await AutomacoesAPI.desligar(automacao.value.id);
      juntar(data);
      useAlert(
        ligar ? t('AUTOMACOES.LISTA.LIGOU') : t('AUTOMACOES.LISTA.DESLIGOU')
      );
    } catch (erro) {
      if (erro?.response?.status === CONFLITO) {
        await carregar();
        useAlert(t('AUTOMACAO_MODELOS.GUIA.VERSAO_MUDOU'));
      } else {
        useAlert(
          erro?.response?.data?.error || t('AUTOMACOES.LISTA.FALHA_TROCA')
        );
      }
    } finally {
      ocupado.value = false;
    }
  };

  watch(id, carregar);

  return {
    automacao,
    estado,
    ocupado,
    carregar,
    ligar: () => trocar(true),
    desligar: () => trocar(false),
  };
}
