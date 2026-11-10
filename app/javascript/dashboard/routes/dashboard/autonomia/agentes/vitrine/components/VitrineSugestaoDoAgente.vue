<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import FerramentasProntasAPI from 'dashboard/api/autonomia/ferramentasProntas';
import VitrineSugestao from './VitrineSugestao.vue';
import { chaveDoTexto, ferramentaPorId } from '../catalogo';
import { useVitrine } from '../useVitrine';
import { useVitrineLigada } from '../useVitrineLigada';

// #2858 F3 — o cartão "pode ganhar" na página do agente. Lê a sugestão que o servidor já tem (a nova é feita em
// segundo plano, a página nunca espera o modelo) e mostra a primeira que o agente ainda não tem. "Incluir" usa o
// mesmo caminho da vitrine; "Agora não" grava que aquela não volta para este agente. Falha ao ler: nenhum cartão
// (é uma sugestão, não uma tarefa).
const props = defineProps({
  agenteId: { type: Number, required: true },
  nome: { type: String, required: true },
});

const NS = 'AGENTS.VITRINE';
const { t } = useI18n();
const vitrine = useVitrine();
const { construtor } = useVitrineLigada();
const sugeridas = ref([]);
const incluindo = ref(false);

const primeira = computed(
  () =>
    sugeridas.value.find(
      id => ferramentaPorId(id) && !vitrine.tem(props.agenteId, id)
    ) || null
);

const sair = id => {
  sugeridas.value = sugeridas.value.filter(item => item !== id);
};

// A resposta de um pedido antigo (outro agente, ou a flag mudou no meio) não vale.
let pedido = 0;
const ler = async () => {
  pedido += 1;
  const este = pedido;
  sugeridas.value = [];
  if (!construtor.value) return;
  vitrine.carregar();
  let lidas = [];
  try {
    const { data } = await FerramentasProntasAPI.sugestoes(props.agenteId);
    lidas = data?.ferramentas || [];
  } catch {
    lidas = [];
  }
  if (este === pedido) sugeridas.value = lidas;
};

const incluir = async () => {
  const id = primeira.value;
  if (!id || incluindo.value) return;
  const consegue = t(`${NS}.FERRAMENTAS.${chaveDoTexto(id)}.CONSEGUE`);
  incluindo.value = true;
  try {
    await vitrine.incluir({
      fonte: id,
      agenteId: props.agenteId,
      usarQuando: t(`${NS}.FERRAMENTAS.${chaveDoTexto(id)}.USE_QUANDO`),
    });
    sair(id);
    useAlert(
      t(`${NS}.SUGESTAO.INCLUIDA`, {
        nome: props.nome,
        consegue,
      })
    );
  } catch (falha) {
    useAlert(t(`${NS}.MOTIVOS.${falha.motivo || 'GERAL'}`));
  } finally {
    incluindo.value = false;
  }
};

// Some na hora; se a gravação falhar, a sugestão volta na próxima abertura (nada se perde).
const dispensar = async () => {
  const id = primeira.value;
  if (!id) return;
  sair(id);
  try {
    await FerramentasProntasAPI.dispensar(props.agenteId, id);
  } catch {
    // A próxima leitura mostra de novo; não é um erro para a pessoa.
  }
};

onMounted(ler);
watch(() => [props.agenteId, construtor.value], ler);
</script>

<template>
  <VitrineSugestao
    v-if="construtor && primeira"
    :nome="nome"
    :ferramenta-id="primeira"
    :incluindo="incluindo"
    @incluir="incluir"
    @dispensar="dispensar"
  />
</template>
