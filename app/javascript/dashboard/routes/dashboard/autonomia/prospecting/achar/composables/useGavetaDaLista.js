import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import {
  MOTIVO_NAO_SERVE,
  PASSO_DA_GAVETA,
  atualizarDaBusca,
  marcarEnviadas,
} from '../utils/acharConfiraEstados';
import { TEXTO_DO_ERRO, erroDoDono } from './useDonoDaLista';

// P1 (crítica r5): uma frase leiga para cada desfecho de adopt_owner
// (contact_outcome). Só "updated" afirma que o contato virou a pessoa.
const FRASE_DO_RESULTADO = {
  updated: 'FEITO',
  shared_with_other_lead: 'FEITO_DIVIDIDO',
  kept_existing_contact: 'FEITO_MANTIDO',
};

// WhatsApp quando pedido e há link; senão o telefone. Sem nenhum dos dois,
// não há o que abrir (a tela nem mostra o botão: podeChamar).
export const enderecoParaChamar = (empresa, tipo) => {
  if (tipo === 'whatsapp' && empresa.whatsappUrl) return empresa.whatsappUrl;
  return empresa.telefone ? `tel:${empresa.telefone}` : '';
};

export const fraseDaPessoa = (t, { resultado, nome, outra }) => {
  const NS = 'PROSPECTING_ACHAR.GAVETA.OUTRAS';
  const chave = FRASE_DO_RESULTADO[resultado] || 'FEITO';
  if (chave === 'FEITO_DIVIDIDO' && !outra) {
    return t(`${NS}.FEITO_DIVIDIDO_SEM_NOME`, { nome });
  }
  return t(`${NS}.${chave}`, { nome, outra });
};

// #2692 — as ações da gaveta da empresa (T1d): mandar uma, "Não serve" / "Não
// quer", falar com outra pessoa (P1 da crítica r5), chamar e ver no funil.
// Saiu de AcharConfiraPage.vue para a página caber na trava de tamanho (#677).
// Na demonstração, cada passo vira um estado ?demo= (mudarEstado).
export function useGavetaDaLista({
  demo,
  route,
  router,
  fonte,
  mudarEstado,
  gaveta,
  empresaDaGaveta,
  destino,
  donoId,
  pessoaNome,
  enviandoUma,
  aviso,
  recado,
  trocar,
  fecharGaveta,
}) {
  const { t } = useI18n();
  const usandoPessoa = ref('');

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
      donoId: donoId.value,
    });
    enviandoUma.value = false;
    if (!resumo.created.length && !resumo.existing.length) {
      const erro = erroDoDono(resumo);
      useAlert(
        t(erro ? TEXTO_DO_ERRO[erro] : 'PROSPECTING_ACHAR.FOLHA.ERRO_FUNIL')
      );
      return;
    }
    // Na lista, a empresa mandada deixa o "Vai" e diz onde está; ao reabrir a
    // gaveta, "Mandar / Não serve / Não quer" não voltam (noFunil).
    marcarEnviadas(trocar, resumo, {
      destino: destino.value,
      pessoa: pessoaNome.value,
    });
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
      fora: naoQuer
        ? { motivo: 'nao_quer' }
        : { motivo: MOTIVO_NAO_SERVE, razao: motivo || '' },
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

  const voltarParaVer = () => {
    if (demo.value)
      mudarEstado(PASSO_DA_GAVETA.ver, { empresa: gaveta.value.id });
    else gaveta.value = { ...gaveta.value, passo: 'ver' };
  };

  // "Usar esta pessoa": o sócio vira com quem falar e a gaveta volta ao
  // começo, com a frase do que aconteceu com o contato.
  const usarPessoa = async nome => {
    const empresa = empresaDaGaveta.value;
    usandoPessoa.value = nome;
    try {
      const resposta = await fonte.value.usarPessoa({ empresa, nome });
      trocar(empresa.id, antiga => atualizarDaBusca(antiga, resposta.empresa));
      recado.value = fraseDaPessoa(t, { ...resposta, nome });
      voltarParaVer();
    } catch {
      useAlert(t('PROSPECTING_ACHAR.GAVETA.OUTRAS.ERRO'));
    } finally {
      usandoPessoa.value = '';
    }
  };

  // "Buscar de novo" do dono não achado: pede a pesquisa de novo e fecha.
  const procurarDono = async () => {
    const empresa = empresaDaGaveta.value;
    try {
      const nova = await fonte.value.procurarDono({ empresa });
      trocar(empresa.id, antiga => atualizarDaBusca(antiga, nova));
    } catch {
      useAlert(t('PROSPECTING_ACHAR.GAVETA.ERRO_PROCURAR'));
      return;
    }
    aviso.value = { texto: t('PROSPECTING_ACHAR.GAVETA.PROCURANDO_DE_NOVO') };
    fecharGaveta();
  };

  const chamar = tipo => {
    const empresa = empresaDaGaveta.value;
    if (demo.value || !empresa) {
      useAlert(t('PROSPECTING_ACHAR.COMUM.DEMO_WHATSAPP'));
      return;
    }
    const endereco = enderecoParaChamar(empresa, tipo);
    if (!endereco) return;
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
    mudarPasso,
    mandarUma,
    marcarFora,
    chamar,
    verNoFunil,
    usarPessoa,
    procurarDono,
    usandoPessoa,
  };
}
