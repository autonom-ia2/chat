import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useNow } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { idiomaDoPainel } from 'dashboard/components-next/conversa-canal/dataDaConversa';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import wootConstants from 'dashboard/constants/globals';
import {
  esperandoResposta,
  foraDoPrazo,
  horaNoFuso,
  periodoDoDia,
  primeiroNome,
  tempoDeEspera,
  vazioForcado,
} from './telaInicial';

const UM_MINUTO = 60 * 1000;

// Os dados das três opções da tela inicial (#1801), todos do que o painel já carregou:
// usuário, conta, conversas da lista e os contadores das abas.
export const useTelaInicial = () => {
  const route = useRoute();
  const router = useRouter();
  const { t, locale } = useI18n();
  const agora = useNow({ interval: UM_MINUTO });

  const usuario = useMapGetter('getCurrentUser');
  const contaId = useMapGetter('getCurrentAccountId');
  const contas = useMapGetter('accounts/getAccount');
  const conversas = useMapGetter('getAllConversations');
  const contadores = useMapGetter('conversationStats/getStats');
  const config = useMapGetter('globalConfig/get');

  const conta = computed(() => contas.value(contaId.value) || {});
  const fuso = computed(() => fusoDaConta(conta.value));
  const simulandoVazio = computed(() => vazioForcado(route.query));

  const nome = computed(() =>
    primeiroNome(usuario.value?.available_name || usuario.value?.name)
  );
  const periodo = computed(() =>
    periodoDoDia(horaNoFuso(agora.value, fuso.value))
  );
  const saudacao = computed(() =>
    t(`TELA_INICIAL.SAUDACAO.${periodo.value}`, { nome: nome.value })
  );
  const hoje = computed(() =>
    new Intl.DateTimeFormat(idiomaDoPainel(locale.value), {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      timeZone: fuso.value,
    }).format(agora.value)
  );

  const esperando = computed(() =>
    simulandoVazio.value
      ? []
      : esperandoResposta(conversas.value, usuario.value?.id)
  );
  const proxima = computed(() => esperando.value[0] || null);
  // null = a conta não usa prazo de resposta; a tela esconde o número.
  const atrasadas = computed(() => {
    const lista = foraDoPrazo(conversas.value, usuario.value?.id);
    if (lista === null) return null;
    return simulandoVazio.value ? [] : lista;
  });
  const comVoce = computed(() => contadores.value?.mineCount || 0);
  const semResponsavel = computed(() =>
    simulandoVazio.value ? 0 : contadores.value?.unAssignedCount || 0
  );
  const tudoEmDia = computed(() => esperando.value.length === 0);

  const nomeDoCliente = conversa => conversa?.meta?.sender?.name || '';
  const esperaHa = conversa => {
    if (!conversa) return '';
    const { unidade, valor } = tempoDeEspera(
      conversa.waiting_since,
      Math.floor(agora.value.getTime() / 1000)
    );
    return t(`TELA_INICIAL.TEMPO.${unidade}`, { count: valor }, valor);
  };

  const abrir = conversa => {
    if (!conversa) return;
    router.push(
      frontendURL(
        conversationUrl({ accountId: contaId.value, id: conversa.id })
      )
    );
  };
  const verAba = aba => emitter.emit(BUS_EVENTS.TELA_INICIAL_ABA, aba);
  const { ME, UNASSIGNED, ALL } = wootConstants.ASSIGNEE_TYPE;
  const verMinhas = () => verAba(ME);
  const verSemResponsavel = () => verAba(UNASSIGNED);
  // Com tudo respondido, a ação leva a quem ainda não tem ninguém cuidando; sem elas, a todas.
  const acaoDoVazio = computed(() =>
    semResponsavel.value > 0
      ? { rotulo: 'VER_SEM_RESPONSAVEL', fazer: verSemResponsavel }
      : { rotulo: 'VER_TODAS', fazer: () => verAba(ALL) }
  );

  return {
    nomeDaConta: computed(() => conta.value?.name || ''),
    logo: computed(() => config.value?.logoThumbnail || ''),
    nome,
    saudacao,
    hoje,
    esperando,
    proxima,
    atrasadas,
    comVoce,
    semResponsavel,
    tudoEmDia,
    nomeDoCliente,
    esperaHa,
    abrir,
    verMinhas,
    verSemResponsavel,
    acaoDoVazio,
  };
};
