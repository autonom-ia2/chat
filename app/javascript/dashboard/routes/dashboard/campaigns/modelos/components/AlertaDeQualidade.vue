<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { SINAIS } from '../constants';

// Modelo pronto, mas o WhatsApp está vendo bloqueios e denúncias (#1338). Toma o
// lugar da caixa "Pronto para usar": o que acontece, o que fazer e um botão
// principal para melhorar o texto. Usar em campanha continua, em segundo plano.
const props = defineProps({
  sinal: { type: String, required: true },
  // 'alterar' | 'duplicar' | '': o caminho que a pessoa tem para melhorar o texto.
  caminho: { type: String, default: '' },
  podeUsar: { type: Boolean, default: false },
});

const emit = defineEmits(['melhorar', 'usar']);

const visual = computed(() => SINAIS[props.sinal]);
const DICAS = ['QUEM', 'COMECO', 'MENOS'];
</script>

<template>
  <section
    data-situacao
    :data-alerta-de-qualidade="sinal"
    class="flex flex-col items-start gap-3 p-6 rounded-2xl ring-1 ring-inset"
    :class="visual.caixa"
  >
    <div class="flex gap-3">
      <span
        class="size-6 mt-0.5 shrink-0"
        :class="[visual.icone, visual.cor]"
        aria-hidden="true"
      />
      <div class="flex flex-col gap-1">
        <h2 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ $t(`MODELOS_WHATSAPP.SAUDE.SINAIS.${sinal}.TITULO`) }}
        </h2>
        <p class="mb-0 text-base leading-relaxed text-n-slate-12">
          {{ $t(`MODELOS_WHATSAPP.SAUDE.SINAIS.${sinal}.TEXTO`) }}
        </p>
      </div>
    </div>
    <div class="flex flex-col gap-2 ps-9">
      <p class="mb-0 text-base font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.SAUDE.O_QUE_FAZER') }}
      </p>
      <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
        <li
          v-for="dica in DICAS"
          :key="dica"
          class="flex gap-2 text-base leading-relaxed text-n-slate-12"
        >
          <span
            class="i-lucide-check size-4 mt-1.5 shrink-0"
            :class="visual.cor"
            aria-hidden="true"
          />
          {{ $t(`MODELOS_WHATSAPP.SAUDE.DICAS.${dica}`) }}
        </li>
      </ul>
    </div>
    <div class="flex flex-wrap items-center w-full gap-3 mt-1 sm:ps-9">
      <Button
        v-if="caminho"
        data-melhorar
        :label="$t(`MODELOS_WHATSAPP.SAUDE.MELHORAR.${caminho}`)"
        icon="i-lucide-pencil"
        :color="sinal === 'ruim' ? 'ruby' : 'amber'"
        size="lg"
        class="!min-h-12 !rounded-xl"
        @click="emit('melhorar')"
      />
      <Button
        v-if="podeUsar"
        data-usar
        :label="$t('MODELOS_WHATSAPP.SAUDE.USAR_MESMO_ASSIM')"
        icon="i-lucide-send"
        color="slate"
        variant="faded"
        class="min-h-11"
        @click="emit('usar')"
      />
    </div>
  </section>
</template>
