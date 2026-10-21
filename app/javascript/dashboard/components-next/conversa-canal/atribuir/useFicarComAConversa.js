// #2067: "ficar com a conversa ao enviar" (opt-out). Substitui a faixa "Atribuir a mim".
// - Não aparece quando a conversa já é de quem escreve.
// - Vem ligado sem ninguém ou com a IA; desligado quando é de outra pessoa.
// - Quem atribui é o servidor, depois que a mensagem foi aceita: o envio leva
//   `ficar_com_a_conversa` (Message#claim_conversation_for_person). Digitar e desistir não
//   muda nada.
// - Mudar o ícone vale só para a próxima mensagem: depois de enviar, ou ao trocar de
//   conversa, volta à regra padrão.
import { computed, reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import {
  QUEM_ESTA,
  ficarVemLigada,
  quemEstaComAConversa,
} from './quemEstaComAConversa';

export const useFicarComAConversa = () => {
  const store = useStore();
  const { t } = useI18n();

  const conversa = computed(() => store.getters.getSelectedChat);
  const eu = computed(() => store.getters.getCurrentUser);
  const quem = computed(() =>
    quemEstaComAConversa(conversa.value, eu.value?.id)
  );
  const nome = computed(() => conversa.value?.meta?.assignee?.name || '');

  // null = a regra padrão; true/false = quem escreve mudou para esta mensagem.
  const escolha = ref(null);
  const ligada = computed(() => escolha.value ?? ficarVemLigada(quem.value));
  const aplica = computed(() => quem.value !== QUEM_ESTA.MINHA);

  watch(
    () => [conversa.value?.id, quem.value],
    () => {
      escolha.value = null;
    }
  );

  const frase = computed(() => {
    if (ligada.value) {
      return quem.value === QUEM_ESTA.NINGUEM
        ? t('CONVERSA_CANAL.FICAR.FICA_COM_VOCE')
        : t('CONVERSA_CANAL.FICAR.FICA_COM_VOCE_SAI_DE', { nome: nome.value });
    }
    return quem.value === QUEM_ESTA.NINGUEM
      ? t('CONVERSA_CANAL.FICAR.CONTINUA_SEM_NINGUEM')
      : t('CONVERSA_CANAL.FICAR.CONTINUA_COM', { nome: nome.value });
  });

  const alternar = () => {
    escolha.value = !ligada.value;
  };

  // Na hora de enviar: o valor que vai no pedido, e o ícone volta à regra padrão. Nota
  // privada nunca fica; conversa que já é minha não tem o que pedir. Uma decisão por envio
  // (texto e anexos que saem em várias mensagens levam a mesma).
  const decidir = ({ privada = false } = {}) => {
    const fica = aplica.value && ligada.value && !privada;
    escolha.value = null;
    return fica;
  };

  return reactive({ aplica, ligada, frase, alternar, decidir });
};
