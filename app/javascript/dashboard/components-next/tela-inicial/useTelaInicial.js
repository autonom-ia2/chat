import { computed, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useNow } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { idiomaDoPainel } from 'dashboard/components-next/conversa-canal/dataDaConversa';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import wootConstants from 'dashboard/constants/globals';
import { useResumoDoServidor } from './useResumoDoServidor';
import { tempoDeEspera } from './telaInicial';

const UM_MINUTO = 60 * 1000;

// Os dados da tela inicial (#1801). Os números e a próxima conversa vêm do servidor
// (GET tela_inicial/resumo); a data sai no fuso da conta.
export const useTelaInicial = () => {
  const router = useRouter();
  const { t, locale } = useI18n();
  const agora = useNow({ interval: UM_MINUTO });

  const contaId = useMapGetter('getCurrentAccountId');
  const contas = useMapGetter('accounts/getAccount');

  const conta = computed(() => contas.value(contaId.value) || {});
  const fuso = computed(() => fusoDaConta(conta.value));

  const hoje = computed(() =>
    new Intl.DateTimeFormat(idiomaDoPainel(locale.value), {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      timeZone: fuso.value,
    }).format(agora.value)
  );

  const { resumo, estado, atualizar } = useResumoDoServidor();
  const pronto = computed(() => estado.value === 'pronto');
  // Em dia: ninguém esperando e nada fora do prazo (conta sem prazos conta como em dia).
  const tudoEmDia = computed(
    () =>
      pronto.value &&
      resumo.value.esperamVoce === 0 &&
      !(resumo.value.foraDoPrazo > 0)
  );

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
  // Cada número leva à lista que ele conta. A tela também aparece numa caixa, etiqueta, time ou
  // pasta (lista filtrada), então sempre volta à lista da conta. A aba vai depois da navegação:
  // sair de "Em que participo" reescreve a aba (watcher do ChatList) no mesmo ciclo da rota.
  const irPara = async (rota, aba) => {
    await router.push({ name: rota, params: { accountId: contaId.value } });
    await nextTick();
    if (aba) emitter.emit(BUS_EVENTS.TELA_INICIAL_ABA, aba);
  };
  const { ME, UNASSIGNED, ALL } = wootConstants.ASSIGNEE_TYPE;
  // "Esperam você" é a lista "Não atendidas" do Chatwoot na aba "Minhas": o mesmo critério do número.
  const verEsperam = () => irPara('conversation_unattended', ME);
  const verSemResponsavel = () => irPara('home', UNASSIGNED);
  const verTodas = () => irPara('home', ALL);
  // A linha da equipe conta as não atendidas da conta: a mesma lista, na aba "Todos".
  const verEquipe = () => irPara('conversation_unattended', ALL);
  // Com tudo respondido, a ação leva a quem ainda não tem ninguém cuidando; sem elas, a todas.
  const acaoDoVazio = computed(() =>
    resumo.value.semResponsavel > 0
      ? { rotulo: 'VER_SEM_RESPONSAVEL', fazer: verSemResponsavel }
      : { rotulo: 'VER_TODAS', fazer: verTodas }
  );

  return {
    hoje,
    estado,
    pronto,
    tudoEmDia,
    comVoce: computed(() => resumo.value.comVoce),
    esperamVoce: computed(() => resumo.value.esperamVoce),
    semResponsavel: computed(() => resumo.value.semResponsavel),
    foraDoPrazo: computed(() => resumo.value.foraDoPrazo),
    proxima: computed(() => resumo.value.proxima),
    equipe: computed(() => resumo.value.equipe),
    nomeDoCliente: proxima => proxima?.nome || '',
    esperaHa,
    abrir,
    verEsperam,
    verSemResponsavel,
    verTodas,
    verEquipe,
    tentarDeNovo: atualizar,
    acaoDoVazio,
  };
};
