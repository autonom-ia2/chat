import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { PASSO_DA_GAVETA } from '../utils/acharConfiraEstados';

// #2692 — as ações da gaveta da empresa (T1d): mandar uma, "Não serve" / "Não
// quer", usar o contato, chamar e ver no funil. Saiu de AcharConfiraPage.vue
// para a página caber na trava de tamanho (#677). Na demonstração, cada passo
// vira um estado ?demo= (mudarEstado).
export function useGavetaDaLista({
  demo,
  route,
  router,
  fonte,
  mudarEstado,
  gaveta,
  empresaDaGaveta,
  destino,
  enviandoUma,
  aviso,
  trocar,
  fecharGaveta,
}) {
  const { t } = useI18n();

  // Na lista, a empresa mandada pela gaveta deixa o "Vai" e diz onde está.
  const marcarMandada = id =>
    trocar(id, item => ({ ...item, mandada: destino.value?.funil.nome }));

  const mudarPasso = passo => {
    if (demo.value) {
      const id = gaveta.value.id;
      const extra = passo === 'mandou' ? { mandada: id } : {};
      mudarEstado(PASSO_DA_GAVETA[passo], { empresa: id, ...extra });
      return;
    }
    gaveta.value = { ...gaveta.value, passo };
  };

  const mandarUma = async () => {
    enviandoUma.value = true;
    const resumo = await fonte.value.mandarParaFunil({
      ids: [gaveta.value.id],
      funilId: destino.value?.funil.id,
      etapaId: destino.value?.etapa.id,
    });
    enviandoUma.value = false;
    if (!resumo.created.length && !resumo.existing.length) {
      useAlert(t('PROSPECTING_ACHAR.FOLHA.ERRO_FUNIL'));
      return;
    }
    marcarMandada(gaveta.value.id);
    mudarPasso('mandou');
  };

  const marcarFora = async (acao, motivo) => {
    const empresa = empresaDaGaveta.value;
    try {
      await fonte.value[acao]({ id: empresa.id, motivo });
    } catch {
      useAlert(t('PROSPECTING_ACHAR.GAVETA.ERRO'));
      return;
    }
    const original = { ...empresa };
    const naoQuer = acao === 'naoQuer';
    trocar(empresa.id, item => ({
      ...item,
      fora: { motivo: naoQuer ? 'nao_quer' : 'tirou' },
    }));
    aviso.value = {
      texto: t(
        naoQuer
          ? 'PROSPECTING_ACHAR.GAVETA.NAO_QUER.FEITO'
          : 'PROSPECTING_ACHAR.GAVETA.NAO_SERVE.FEITO'
      ),
      // Desfazer só volta a tela na demonstração; na API, o descarte desfeito
      // é outra chamada (fica para a fase 1b).
      desfazer: demo.value ? () => trocar(original.id, () => original) : null,
    };
    fecharGaveta();
  };

  const chamar = tipo => {
    const empresa = empresaDaGaveta.value;
    if (demo.value || !empresa) {
      useAlert(t('PROSPECTING_ACHAR.COMUM.DEMO_WHATSAPP'));
      return;
    }
    const endereco =
      tipo === 'whatsapp' && empresa.whatsappUrl
        ? empresa.whatsappUrl
        : `tel:${empresa.telefone}`;
    window.open(endereco, '_blank', 'noopener');
  };

  const verNoFunil = () => {
    const funilId =
      empresaDaGaveta.value?.noFunil?.funilId ||
      (demo.value ? null : destino.value?.funil.id);
    router.push({
      name: 'crm_kanban_index',
      params: { accountId: route.params.accountId },
      query: funilId ? { pipeline_id: funilId } : {},
    });
  };

  return {
    marcarMandada,
    mudarPasso,
    mandarUma,
    marcarFora,
    chamar,
    verNoFunil,
  };
}
