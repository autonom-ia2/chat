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
import { resumoVazio } from './resumoDoServidor';
import { useResumoDoServidor } from './useResumoDoServidor';
import {
  horaNoFuso,
  periodoDoDia,
  primeiroNome,
  tempoDeEspera,
  vazioForcado,
} from './telaInicial';

const UM_MINUTO = 60 * 1000;

// Os dados da tela inicial (#1801). Os números e a próxima conversa vêm do servidor
// (GET tela_inicial/resumo); nome, conta, fuso e "com você" vêm do store.
export const useTelaInicial = () => {
  const route = useRoute();
  const router = useRouter();
  const { t, locale } = useI18n();
  const agora = useNow({ interval: UM_MINUTO });

  const usuario = useMapGetter('getCurrentUser');
  const contaId = useMapGetter('getCurrentAccountId');
  const contas = useMapGetter('accounts/getAccount');
  const contadores = useMapGetter('conversationStats/getStats');
  const config = useMapGetter('globalConfig/get');

  const conta = computed(() => contas.value(contaId.value) || {});
  const fuso = computed(() => fusoDaConta(conta.value));

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

  const { resumo: doServidor, estado } = useResumoDoServidor();
  const resumo = computed(() =>
    vazioForcado(route.query) ? resumoVazio(doServidor.value) : doServidor.value
  );
  const pronto = computed(() => estado.value === 'pronto');
  const tudoEmDia = computed(
    () => pronto.value && resumo.value.esperamVoce === 0
  );
  const comVoce = computed(() => contadores.value?.mineCount || 0);

  const esperaHa = proxima => {
    if (!proxima) return '';
    const { unidade, valor } = tempoDeEspera(
      proxima.desde,
      Math.floor(agora.value.getTime() / 1000)
    );
    return t(`TELA_INICIAL.TEMPO.${unidade}`, { count: valor }, valor);
  };

  const abrir = proxima => {
    if (!proxima) return;
    router.push(
      frontendURL(
        conversationUrl({ accountId: contaId.value, id: proxima.displayId })
      )
    );
  };
  const verAba = aba => emitter.emit(BUS_EVENTS.TELA_INICIAL_ABA, aba);
  const { ME, UNASSIGNED, ALL } = wootConstants.ASSIGNEE_TYPE;
  const verMinhas = () => verAba(ME);
  const verSemResponsavel = () => verAba(UNASSIGNED);
  const verTodas = () => verAba(ALL);
  // Com tudo respondido, a ação leva a quem ainda não tem ninguém cuidando; sem elas, a todas.
  const acaoDoVazio = computed(() =>
    resumo.value.semResponsavel > 0
      ? { rotulo: 'VER_SEM_RESPONSAVEL', fazer: verSemResponsavel }
      : { rotulo: 'VER_TODAS', fazer: verTodas }
  );

  return {
    nomeDaConta: computed(() => conta.value?.name || ''),
    logo: computed(() => config.value?.logoThumbnail || ''),
    nome,
    saudacao,
    hoje,
    estado,
    pronto,
    tudoEmDia,
    comVoce,
    esperamVoce: computed(() => resumo.value.esperamVoce),
    semResponsavel: computed(() => resumo.value.semResponsavel),
    foraDoPrazo: computed(() => resumo.value.foraDoPrazo),
    proxima: computed(() => resumo.value.proxima),
    equipe: computed(() => resumo.value.equipe),
    nomeDoCliente: proxima => proxima?.nome || '',
    esperaHa,
    abrir,
    verMinhas,
    verSemResponsavel,
    verTodas,
    acaoDoVazio,
  };
};
