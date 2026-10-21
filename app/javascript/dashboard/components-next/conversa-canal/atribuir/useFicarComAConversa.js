// #2067: "ficar com a conversa ao enviar" (opt-out). Substitui a faixa "Atribuir a mim".
// - Não aparece quando a conversa já é de quem escreve.
// - Vem ligada sem ninguém ou com a IA; desligada quando é de outra pessoa.
// - A atribuição só acontece depois que a mensagem sai (digitar e desistir não muda nada).
// - Mudar a opção vale para a próxima mensagem desta conversa: depois de enviar, ou ao
//   trocar de conversa, volta à regra padrão.
import { computed, reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useAlert } from 'dashboard/composables';
import {
  QUEM_ESTA,
  ficarVemLigada,
  quemEstaComAConversa,
} from './quemEstaComAConversa';
import { escolhaDoPrototipo } from './prototipo2067';

export const useFicarComAConversa = () => {
  const store = useStore();
  const route = useRoute();
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

  // Na hora de enviar: fica ou não, e a opção volta à regra padrão. Nota privada não
  // atribui. Uma decisão por envio (texto e anexos que saem em várias mensagens usam a
  // mesma), e a atribuição só acontece depois que a mensagem é aceita (atribuirAMim).
  const decidir = ({ privada = false } = {}) => {
    const fica = aplica.value && ligada.value && !privada;
    escolha.value = null;
    return fica;
  };

  let atribuindo = false;
  const atribuirAMim = async () => {
    if (atribuindo || !aplica.value) return;
    atribuindo = true;
    const conversationId = conversa.value.id;
    try {
      const { data } = await ConversationApi.assignAgent({
        conversationId,
        agentId: eu.value.id,
      });
      store.dispatch('setCurrentChatAssignee', {
        conversationId,
        assignee: data,
        assigneeType: 'User',
      });
    } catch {
      useAlert(t('CONVERSA_CANAL.FICAR.FALHOU'));
    } finally {
      atribuindo = false;
    }
  };

  // Enviar "do outro jeito" (forma C): muda a opção só para este envio.
  const enviarAssim = (ficar, enviar) => {
    escolha.value = ficar;
    enviar();
  };

  const prototipo = computed(() => escolhaDoPrototipo(route?.query));

  return reactive({
    aplica,
    ligada,
    frase,
    alternar,
    decidir,
    atribuirAMim,
    enviarAssim,
    forma: computed(() => prototipo.value.forma),
    lugarDoDevolver: computed(() => prototipo.value.lugar),
  });
};
