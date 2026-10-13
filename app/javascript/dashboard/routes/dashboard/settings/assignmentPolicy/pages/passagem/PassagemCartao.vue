<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import PassagemInterruptor from './PassagemInterruptor.vue';

// #1385 — uma parte da regra em uma frase, no padrão do cartão do funil (#1384): ícone, nome pequeno, a frase com o
// dado em negrito e, no canto, o liga/desliga ou o "Alterar". Âmbar para aviso; vermelho para o que falta.
const props = defineProps({
  parte: { type: String, required: true },
  icone: { type: String, required: true },
  tom: { type: String, default: 'bg-n-blue-3 text-n-blue-11' },
  titulo: { type: String, required: true },
  aviso: { type: Boolean, default: false },
  erro: { type: Boolean, default: false },
  comAlterar: { type: Boolean, default: true },
  // Com `interruptor`, o cartão ganha o liga/desliga no canto (v-model:ligado).
  interruptor: { type: Boolean, default: false },
  apagado: { type: Boolean, default: false },
  // Gravando o liga/desliga: o interruptor fica parado até terminar.
  ocupado: { type: Boolean, default: false },
});

defineEmits(['alterar']);

const ligado = defineModel('ligado', { type: Boolean, default: false });

const borda = () => {
  if (props.erro) return 'border-n-ruby-8';
  if (props.aviso) return 'border-n-amber-7';
  return 'border-n-weak hover:border-n-slate-7 focus-within:border-n-blue-8 focus-within:shadow-md';
};
const tomDoIcone = () => {
  if (props.erro) return 'bg-n-ruby-3 text-n-ruby-11';
  if (props.aviso) return 'bg-n-amber-3 text-n-amber-11';
  if (props.apagado) return 'bg-n-slate-3 text-n-slate-10';
  return props.tom;
};
</script>

<template>
  <article
    :data-cartao="parte"
    class="flex items-start gap-3 rounded-2xl border bg-n-solid-1 p-4 shadow-sm transition sm:gap-4 sm:p-5"
    :class="borda()"
  >
    <span
      class="grid size-10 shrink-0 place-items-center rounded-2xl sm:size-12"
      :class="tomDoIcone()"
      aria-hidden="true"
    >
      <span class="size-5 sm:size-6" :class="icone" />
    </span>
    <div class="flex min-w-0 flex-1 flex-col gap-1">
      <div class="flex min-h-11 items-center gap-3">
        <h3
          :id="`cartao-${parte}`"
          class="mb-0 min-w-0 flex-1 text-sm font-medium text-n-slate-11"
        >
          {{ titulo }}
        </h3>
        <PassagemInterruptor
          v-if="interruptor"
          v-model="ligado"
          :rotulo="titulo"
          :desligado="ocupado"
        />
        <Button
          v-else-if="comAlterar"
          :label="$t('CRM_KANBAN.PASSAGEM.ALTERAR')"
          :aria-label="
            $t('CRM_KANBAN.PASSAGEM.ALTERAR_PARTE', { parte: titulo })
          "
          icon="i-lucide-pencil"
          slate
          faded
          class="!min-h-11 shrink-0"
          @click="$emit('alterar')"
        />
      </div>
      <p
        class="-mt-2 mb-0 text-base leading-relaxed text-n-slate-12"
        :class="{ 'text-n-slate-11': apagado }"
      >
        <slot />
      </p>
      <slot name="extra" />
    </div>
  </article>
</template>
