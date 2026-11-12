import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

// #2889 — levar o pedido ao Guia (tela automacoes_nova). O pedido vai no estado da navegação, como no herói: só a
// própria tela pode escrevê-lo. Serve à pergunta do topo e ao "Usar este modelo".
export function useIrAoGuia() {
  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();

  const irAoGuia = estado =>
    router.push({
      name: 'automacoes_nova',
      params: { accountId: route.params.accountId },
      state: estado,
    });

  const pedir = ({ texto, anexos }) =>
    irAoGuia({
      ...(texto ? { pedidoAutomacao: texto } : {}),
      ...(anexos?.length ? { anexosAutomacao: anexos } : {}),
    });

  const falar = () => irAoGuia({ pedidoPorVoz: true });

  const usarModelo = modelo =>
    irAoGuia({
      pedidoAutomacao: t('AUTOMACAO_MODELOS.PEDIDO', {
        titulo: modelo.titulo,
        texto: modelo.texto,
      }),
    });

  return { pedir, falar, usarModelo };
}
