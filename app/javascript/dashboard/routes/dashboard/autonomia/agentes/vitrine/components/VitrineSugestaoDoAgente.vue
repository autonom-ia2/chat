<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VitrineSugestao from './VitrineSugestao.vue';
import { emDestaque } from '../catalogo';
import { useVitrine } from '../useVitrine';
import { useVitrineLigada } from '../useVitrineLigada';

// #2776 J6 — o cartão "pode ganhar" na página de um agente que já existe. No produto, quem escolhe a ferramenta é o
// modelo, pelo sentido das instruções do agente, com a saída "nenhuma combina" (sem cartão). No PROTÓTIPO a escolha
// é fictícia: a primeira ferramenta em destaque no ramo da conta que o agente ainda não tem e que a pessoa não
// dispensou. Só aparece para quem pode mexer nas ferramentas do agente (a página decide e passa `pode`).
const props = defineProps({
  agenteId: { type: [Number, String], required: true },
  nome: { type: String, required: true },
  pode: { type: Boolean, default: false },
});

const { t } = useI18n();
const { ligada, camadas } = useVitrineLigada();
const vitrine = useVitrine();

const sugerida = computed(() => {
  if (!props.pode || !ligada.value) return null;
  return (
    emDestaque(camadas.value).find(
      item =>
        !vitrine.tem(props.agenteId, item.id) &&
        !vitrine.dispensada(props.agenteId, item.id)
    )?.id ?? null
  );
});

const incluir = () => {
  const id = sugerida.value;
  const ferramenta = t(`AGENTS.VITRINE.FERRAMENTAS.${id}.NOME`);
  vitrine.incluir(
    props.agenteId,
    id,
    t(`AGENTS.VITRINE.FERRAMENTAS.${id}.USE_QUANDO`)
  );
  useAlert(
    t('AGENTS.VITRINE.SUGESTAO.INCLUIDA', { nome: props.nome, ferramenta })
  );
};
</script>

<template>
  <VitrineSugestao
    v-if="sugerida"
    :nome="nome"
    :ferramenta-id="sugerida"
    @incluir="incluir"
    @dispensar="vitrine.dispensar(agenteId, sugerida)"
  />
</template>
