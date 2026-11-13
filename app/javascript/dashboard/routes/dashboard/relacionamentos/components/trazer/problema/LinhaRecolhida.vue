<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useErroDoCartao } from '../../../trazer/useErroDoCartao';

// #2896, Fatia 2 — a linha de que a pessoa já cuidou, recolhida numa frase só:
// guardada ("Pronto", com o valor que ficou salvo) ou deixada de fora. Só
// oferece "Voltar atrás", com 44 px de altura (alvo de toque).
// `recusa` (`{ linha, motivo }`): o "Voltar atrás" não deu certo. A linha diz a
// frase ali mesmo, como alerta, e o foco volta ao botão (quando ele religa). A
// frase é a da linha, não a de um campo: voltar atrás não confere valor nenhum.
const props = defineProps({
  linha: { type: Number, required: true },
  texto: { type: String, required: true },
  guardada: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['reabrir']);

const { t } = useI18n();

const raiz = ref(null);
const idDoErro = useId();
const { erro } = useErroDoCartao({
  recusa: () => props.recusa,
  campo: '',
  raiz,
  ocupado: () => props.ocupado,
});
</script>

<template>
  <div ref="raiz" class="flex flex-col gap-2">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="flex items-center gap-2 m-0 text-base text-n-slate-11">
        <span
          class="size-5 shrink-0"
          :class="
            guardada
              ? 'i-lucide-circle-check text-n-teal-11'
              : 'i-lucide-circle-minus'
          "
          aria-hidden="true"
        />
        <span>{{ texto }}</span>
        <span class="font-medium text-n-slate-12">
          {{
            t(
              guardada
                ? 'RELACIONAMENTOS_TRAZER.PRECISAM.PRONTO'
                : 'RELACIONAMENTOS_TRAZER.PRECISAM.DEIXADA'
            )
          }}
        </span>
      </p>
      <Button
        ghost
        slate
        type="button"
        class="min-h-11"
        data-relacionamentos="voltar-atras"
        :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.VOLTAR_ATRAS')"
        :aria-label="
          t('RELACIONAMENTOS_TRAZER.PRECISAM.VOLTAR_ATRAS_LINHA', { linha })
        "
        :aria-describedby="erro ? idDoErro : undefined"
        :disabled="ocupado"
        @click="emit('reabrir', linha)"
      />
    </div>
    <p
      v-if="erro"
      :id="idDoErro"
      data-relacionamentos="erro-da-linha"
      role="alert"
      class="m-0 text-sm font-medium text-n-ruby-11"
    >
      {{ erro }}
    </p>
  </div>
</template>
