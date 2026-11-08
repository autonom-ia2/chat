import { computed, ref } from 'vue';
import CrmArquivadosAPI from 'dashboard/api/crmArquivados';

// Estado da janela "Arquivar o funil" (#2095, passos 8 e 9 do protótipo; decisões 2 e 7). Separado do componente
// para ser testado sem a janela: o passo (único funil, escolher o novo principal, escolher o que fazer), as escolhas
// já marcadas (mover os cards e passar as caixas para o mesmo funil) e o pedido ao servidor.
export const useArquivarFunil = ({ carregarEtapas }) => {
  const funil = ref(null);
  const outros = ref([]);
  const previa = ref(null);
  const carregando = ref(false);
  const erroPrevia = ref(null);
  const passo = ref('escolha');
  const novoPrincipal = ref(null);
  const destino = ref('mover');
  const funilDestino = ref(null);
  const etapaDestino = ref(null);
  const etapasDestino = ref([]);
  const caixas = ref('passar');
  const funilDasCaixas = ref(null);
  const caixasMexidas = ref(false);
  const etapasPorFunil = ref({});
  // As etapas do funil escolhido não vieram: a janela diz por quê, em vez de travar o botão calada.
  const erroEtapas = ref(null);

  const abertos = computed(() => Number(previa.value?.open_cards_count || 0));
  const caixasQueCriam = computed(() =>
    (previa.value?.inboxes || []).filter(caixa => caixa.auto_create_card)
  );
  // Só os lembretes: a vez seguinte de cada série que repete já é um lembrete (Crm::Pipelines::RetornosDosGuardados).
  const retornos = computed(() => Number(previa.value?.follow_ups_count || 0));
  const reunioes = computed(() =>
    Number(previa.value?.upcoming_meetings_count || 0)
  );

  const etapas = async funilId => {
    if (!funilId) return [];
    if (!etapasPorFunil.value[funilId]) {
      const lista = await carregarEtapas(funilId);
      etapasPorFunil.value = { ...etapasPorFunil.value, [funilId]: lista };
    }
    return etapasPorFunil.value[funilId];
  };
  const primeiraEtapa = funilId => etapasPorFunil.value[funilId]?.[0] || null;

  const escolherDestino = async funilId => {
    funilDestino.value = funilId;
    etapaDestino.value = null;
    erroEtapas.value = null;
    try {
      etapasDestino.value = await etapas(funilId);
    } catch (error) {
      etapasDestino.value = [];
      erroEtapas.value = error;
      return;
    }
    if (funilDestino.value === funilId)
      etapaDestino.value = etapasDestino.value[0]?.id ?? null;
    if (!caixasMexidas.value) funilDasCaixas.value = funilId;
  };
  const escolherFunilDasCaixas = async funilId => {
    funilDasCaixas.value = funilId;
    caixasMexidas.value = true;
    erroEtapas.value = null;
    try {
      await etapas(funilId);
    } catch (error) {
      erroEtapas.value = error;
    }
  };

  const abrir = async ({ alvo, ativos }) => {
    funil.value = alvo;
    outros.value = ativos.filter(item => item.id !== alvo.id);
    previa.value = null;
    erroPrevia.value = null;
    novoPrincipal.value = null;
    destino.value = 'mover';
    caixas.value = 'passar';
    caixasMexidas.value = false;
    if (!outros.value.length) {
      passo.value = 'unico';
      return;
    }
    passo.value = alvo.is_default ? 'principal' : 'escolha';
    carregando.value = true;
    try {
      const { data } = await CrmArquivadosAPI.previaDoArquivarFunil(alvo.id);
      previa.value = data.payload || {};
      await escolherDestino(outros.value[0].id);
    } catch (error) {
      erroPrevia.value = error;
    } finally {
      carregando.value = false;
    }
  };

  // Depois de uma recusa com parte dos cards já levada (#2145): a contagem de abertos da janela é a de agora.
  const recarregarPrevia = async () => {
    try {
      const { data } = await CrmArquivadosAPI.previaDoArquivarFunil(
        funil.value.id
      );
      previa.value = data.payload || {};
    } catch (error) {
      erroPrevia.value = error;
    }
  };

  const continuarComPrincipal = async () => {
    if (!novoPrincipal.value) return;
    passo.value = 'escolha';
    await escolherDestino(novoPrincipal.value);
  };

  const caixasProntas = computed(
    () =>
      !caixasQueCriam.value.length ||
      caixas.value === 'parar' ||
      Boolean(funilDasCaixas.value)
  );
  const cardsProntos = computed(
    () =>
      !abertos.value ||
      destino.value === 'guardar' ||
      Boolean(funilDestino.value && etapaDestino.value)
  );
  const pronto = computed(
    () =>
      passo.value === 'escolha' &&
      Boolean(previa.value) &&
      cardsProntos.value &&
      caixasProntas.value
  );

  const parametros = () => {
    const params = {};
    if (abertos.value && destino.value === 'mover')
      params.move_to_stage_id = etapaDestino.value;
    // "Guardar junto": os retornos dos cards guardados param (decisão 2). Sem isto, o servidor arquiva como antes.
    if (abertos.value && destino.value === 'guardar')
      params.stop_follow_ups = true;
    if (caixasQueCriam.value.length && caixas.value === 'passar')
      params.inboxes_to_pipeline_id = funilDasCaixas.value;
    if (novoPrincipal.value)
      params.new_default_pipeline_id = novoPrincipal.value;
    return params;
  };

  const arquivar = async () => {
    const params = parametros();
    const { data } = await CrmArquivadosAPI.arquivarFunil(
      funil.value.id,
      params
    );
    return { resposta: data.payload || data, params };
  };

  return {
    funil,
    outros,
    previa,
    carregando,
    erroPrevia,
    erroEtapas,
    passo,
    novoPrincipal,
    destino,
    funilDestino,
    etapaDestino,
    etapasDestino,
    caixas,
    funilDasCaixas,
    abertos,
    caixasQueCriam,
    retornos,
    reunioes,
    pronto,
    primeiraEtapa,
    abrir,
    recarregarPrevia,
    continuarComPrincipal,
    escolherDestino,
    escolherFunilDasCaixas,
    arquivar,
  };
};
