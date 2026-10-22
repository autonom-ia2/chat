// #2067: "ficar com a conversa ao enviar" (opt-out). Com a flag da conta
// (`ficar_com_a_conversa_ao_enviar`) substitui a faixa "Atribuir a mim"; sem ela, nada
// aparece e nada vai no envio (a tela e o servidor ficam como antes).
// - Não aparece quando a conversa já é de quem escreve.
// - Vem ligado sem ninguém ou com a IA; desligado quando é de outra pessoa.
// - "Ao enviar" é ao clicar em Enviar: o envio leva `ficar_com_a_conversa` e o dono que a
//   tela viu, e o servidor atribui depois de gravar a mensagem, só se o dono ainda é esse
//   (Message#claim_conversation_for_person). Digitar e desistir não muda nada.
// - Mudar o ícone vale só para a próxima mensagem daquela conversa: fica guardado junto do
//   rascunho (trocar de conversa e voltar mantém), até enviar ou o dono mudar. Se o envio
//   falhar, a escolha volta (`restaurar`).
// - Fora do ícone, na regra de antes (decisão da Orquestração, 22/10): reenviar pelo balão,
//   encaminhar e a mensagem de cotação do Meta Ads (MetaAdsQuoteMessage) não mandam o
//   pedido. O reenvio pelo balão já não leva: MessagesView#handleMessageRetry passa a
//   mensagem por useSnakeCase (MessageApi.create só lê os campos em camelCase), e o
//   reenvio de falha externa (MessageApi.retry) não tem corpo.
// `conversa`: a conversa em que se escreve (padrão: a aberta na tela).
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  QUEM_ESTA,
  chaveDoDono,
  chaveDoVisto,
  donoVisto,
  ficarVemLigada,
  quemEstaComAConversa,
} from './quemEstaComAConversa';

export const useFicarComAConversa = ({ conversa: daConversa = null } = {}) => {
  const store = useStore();
  const { t } = useI18n();
  const selecionada = useMapGetter('getSelectedChat');
  const eu = useMapGetter('getCurrentUser');
  const contaAtual = useMapGetter('getCurrentAccountId');
  const temChave = useMapGetter('accounts/isFeatureEnabledonAccount');
  const rascunho = useMapGetter('draftMessages/get');

  const conversa = daConversa || computed(() => selecionada.value || null);
  const ligadoNaConta = computed(() =>
    Boolean(
      temChave.value?.(
        contaAtual.value,
        FEATURE_FLAGS.FICAR_COM_A_CONVERSA_AO_ENVIAR
      )
    )
  );
  const quem = computed(() =>
    quemEstaComAConversa(conversa.value, eu.value?.id)
  );
  const nome = computed(() => conversa.value?.meta?.assignee?.name || '');

  // A escolha da pessoa para a próxima mensagem desta conversa, guardada com o rascunho e
  // presa ao dono que ela viu: o dono mudou, vale a regra padrão de novo.
  const chave = computed(() =>
    conversa.value?.id ? `ficar-${conversa.value.id}` : null
  );
  const guardada = computed(() => {
    const valor = chave.value && rascunho.value?.(chave.value);
    if (!valor || valor.dono !== chaveDoDono(conversa.value)) return null;
    return valor.ligada;
  });
  const guardar = ligada => {
    if (!chave.value) return;
    if (ligada === null) {
      store.dispatch('draftMessages/delete', { key: chave.value });
      return;
    }
    store.dispatch('draftMessages/set', {
      key: chave.value,
      message: { ligada, dono: chaveDoDono(conversa.value) },
    });
  };

  // O dono desta conversa mudou (evento ao vivo): a escolha feita para o dono anterior acaba.
  // Compara valores (id e dono), não o objeto: a conversa chega de novo a cada evento.
  watch(
    [
      () => conversa.value?.id ?? null,
      () => (conversa.value ? chaveDoDono(conversa.value) : null),
    ],
    ([id, dono], [idAntes, donoAntes]) => {
      if (!id || id !== idAntes || dono === donoAntes) return;
      if (rascunho.value?.(`ficar-${id}`)) guardar(null);
    }
  );

  const ligada = computed(() => guardada.value ?? ficarVemLigada(quem.value));
  // Sem a conversa (a gaveta ainda lendo), nada a decidir.
  const conhecida = computed(() => Boolean(conversa.value?.id));
  const aplica = computed(
    () =>
      ligadoNaConta.value && conhecida.value && quem.value !== QUEM_ESTA.MINHA
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

  const alternar = () => guardar(!ligada.value);

  // Na hora de enviar: o que vai no pedido, e o ícone volta à regra padrão. Uma decisão por
  // envio (texto e anexos que saem em várias mensagens levam a mesma). Sem a flag, null:
  // nada vai no envio. Nota privada nunca fica; conversa que já é minha não tem o que pedir.
  const decidir = ({ privada = false } = {}) => {
    if (!ligadoNaConta.value || !conhecida.value) return null;
    const decisao = {
      fica: aplica.value && ligada.value && !privada,
      de: donoVisto(conversa.value),
      guardada: guardada.value,
      chave: chave.value,
    };
    if (decisao.guardada !== null) guardar(null);
    return decisao;
  };

  // O envio não saiu: a escolha que a pessoa tinha feito volta para a conversa do envio (mesmo
  // que a tela já esteja em outra), presa ao dono que ela viu ao enviar.
  const restaurar = decisao => {
    if (!decisao?.chave || decisao.guardada === null) return;
    store.dispatch('draftMessages/set', {
      key: decisao.chave,
      message: { ligada: decisao.guardada, dono: chaveDoVisto(decisao.de) },
    });
  };

  return reactive({ aplica, ligada, frase, alternar, decidir, restaurar });
};

// Os campos do envio (MessageApi.create) a partir da decisão; vazio sem a flag. `parte`: a
// gaveta manda as partes uma de cada vez (para de mandar quando uma falha), e só a 1ª pede
// para ficar; as outras vão com o ícone desligado (não tomam a conversa pela regra de antes
// nem geram aviso falso). A caixa de resposta manda em paralelo e todas levam o pedido.
export const camposDoEnvio = (decisao, { parte = 0 } = {}) =>
  decisao
    ? {
        ficarComAConversa: parte === 0 ? decisao.fica : false,
        ficarComAConversaDe: decisao.de,
      }
    : {};
