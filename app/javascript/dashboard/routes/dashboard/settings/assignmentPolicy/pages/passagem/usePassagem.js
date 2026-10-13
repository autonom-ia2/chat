import { computed, ref } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  ETAPA_DESLIGADA,
  ETAPA_IGUAL,
  ETAPA_PROPRIA,
  faltaPessoa,
  modoDaEtapa,
} from './passagem';

// #1385: a mesma configuração da tela antiga (Crm::Ai::SettingsUpdater), arrumada para quem não é técnico.
// O contrato com o back-end não muda: ai_settings.handoff (regra do funil) e stage_handoff (regra de cada etapa).
const ESPERA_PADRAO_SEGUNDOS = 900;
const SELETORES = ['round_robin', 'direct'];
const FLUXOS = ['r2_direct', 'r3_invite'];
const DESTINOS = ['inbox', 'user'];
const SE_NINGUEM = ['renotify', 'escalate'];

const idPositivo = valor => {
  const numero = Number(valor);
  return Number.isInteger(numero) && numero > 0 ? numero : null;
};

const daLista = (lista, valor, padrao) =>
  lista.includes(valor) ? valor : padrao;

export const regraDoServidor = handoff => ({
  enabled: handoff?.enabled === true,
  mode: daLista(SELETORES, handoff?.mode, 'round_robin'),
  handoff_mode: daLista(FLUXOS, handoff?.handoff_mode, 'r2_direct'),
  trigger: handoff?.trigger || '',
  prefer_online: handoff?.prefer_online !== false,
  pickup_threshold_seconds:
    Number(handoff?.pickup_threshold_seconds) > 0
      ? Math.round(Number(handoff.pickup_threshold_seconds))
      : ESPERA_PADRAO_SEGUNDOS,
  escalation_user_id: idPositivo(handoff?.escalation_user_id),
  pool_type: daLista(DESTINOS, handoff?.pool_type, 'inbox'),
  pool_id: idPositivo(handoff?.pool_id),
  escalation_action: daLista(
    SE_NINGUEM,
    handoff?.escalation_action,
    'renotify'
  ),
});

// O que vai para stage_handoff: "igual" apaga a regra da etapa (custom:false); "desligada" grava a regra do funil
// com enabled:false, para a etapa não herdar o liga/desliga do funil.
const etapaParaServidor = (etapa, regraDoFunil) => {
  if (etapa.modo === ETAPA_IGUAL) return { custom: false };
  if (etapa.modo === ETAPA_DESLIGADA) {
    return { custom: true, ...regraDoFunil, enabled: false };
  }
  return { custom: true, ...etapa.regra, enabled: true };
};

// As caixas do funil e a equipe (quem está nelas) vêm junto do ai_settings (Crm::Ai::SettingsPresenter): quem tem só a
// permissão de IA do CRM não pode abrir a lista de caixas do funil nem a de membros da caixa.
const equipeDoServidor = lista =>
  (lista || []).map(pessoa => ({ id: pessoa.id, name: pessoa.name }));

export function usePassagem() {
  const carregando = ref(false);
  const falhou = ref(false);
  const salvando = ref(false);
  const salvoAgora = ref(false);
  const funis = ref([]);
  const caixas = ref([]);
  const equipe = ref([]);
  const iaDoFunilLigada = ref(true);
  const regra = ref(regraDoServidor({}));
  const etapas = ref([]);
  const original = ref('');
  let copias = [];

  const estado = () =>
    JSON.stringify({ regra: regra.value, etapas: etapas.value });
  const alterado = computed(
    () => !carregando.value && original.value !== estado()
  );

  // Trocar de funil com a leitura anterior em voo: a resposta velha é descartada, para o Salvar não gravar as regras de
  // um funil no outro.
  let pedido = null;
  const carregar = async funilId => {
    pedido = funilId;
    carregando.value = true;
    falhou.value = false;
    salvoAgora.value = false;
    copias = [];
    try {
      const [ajustes, listaDeFunis] = await Promise.all([
        CrmKanbanAPI.getAiSettings(funilId),
        CrmKanbanAPI.getPipelines(),
      ]);
      if (funilId !== pedido) return;
      const dados = ajustes.data.payload || {};
      funis.value = listaDeFunis.data.payload || [];
      caixas.value = dados.inboxes || [];
      equipe.value = equipeDoServidor(dados.team);
      iaDoFunilLigada.value = dados.enabled !== false;
      regra.value = regraDoServidor(dados.handoff);
      etapas.value = (dados.stages || []).map(etapa => ({
        id: etapa.id,
        nome: etapa.name,
        modo: modoDaEtapa(etapa),
        regra: { ...regraDoServidor(etapa.handoff), enabled: true },
      }));
      original.value = estado();
    } catch {
      if (funilId === pedido) falhou.value = true;
    } finally {
      if (funilId === pedido) carregando.value = false;
    }
  };

  const regrasIncompletas = computed(() => {
    const faltas = faltaPessoa(regra.value) ? ['funil'] : [];
    etapas.value.forEach(etapa => {
      if (etapa.modo === ETAPA_PROPRIA && faltaPessoa(etapa.regra)) {
        faltas.push(etapa.id);
      }
    });
    return faltas;
  });

  const salvar = async funilId => {
    salvando.value = true;
    salvoAgora.value = false;
    try {
      const stageHandoff = Object.fromEntries(
        etapas.value.map(etapa => [
          etapa.id,
          etapaParaServidor(etapa, regra.value),
        ])
      );
      await CrmKanbanAPI.updateAiSettings(funilId, {
        ai_settings: { handoff: { ...regra.value } },
        stage_handoff: stageHandoff,
      });
      original.value = estado();
      salvoAgora.value = true;
      return true;
    } catch {
      return false;
    } finally {
      salvando.value = false;
    }
  };

  const voltarPara = texto => {
    const anterior = JSON.parse(texto);
    regra.value = anterior.regra;
    etapas.value = anterior.etapas;
  };

  // Uma cópia ao abrir cada tela de detalhe: "Cancelar" volta para ela; "Salvar" grava e a descarta.
  const guardarCopia = () => {
    copias = [...copias, estado()];
  };
  const descartarCopia = () => {
    copias = copias.slice(0, -1);
  };
  const restaurarCopia = () => {
    const ultima = copias.at(-1);
    descartarCopia();
    if (ultima) voltarPara(ultima);
  };

  return {
    carregando,
    falhou,
    salvando,
    salvoAgora,
    funis,
    caixas,
    equipe,
    iaDoFunilLigada,
    regra,
    etapas,
    alterado,
    regrasIncompletas,
    carregar,
    salvar,
    guardarCopia,
    descartarCopia,
    restaurarCopia,
  };
}
