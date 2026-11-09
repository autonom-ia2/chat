<script setup>
// #2692 — vazio, erro e aviso da Prospecção nova. Regra de ouro: uma frase e um
// botão. `faixa` é a tira no topo (rubi = erro, âmbar = atenção, verde-água =
// feito); sem ela, o bloco central da tela vazia. Rodada 2: o bloco aceita um
// `link` secundário (ex.: "Mudar o pedido" ao lado de "Procurar mais longe"),
// e a faixa pode só informar, sem botão.
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  tom: { type: String, default: 'vazio' },
  texto: { type: String, required: true },
  botao: { type: String, default: '' },
  link: { type: String, default: '' },
  faixa: { type: Boolean, default: false },
  // #2697: o botão da faixa desligado (ex.: "Desfazer" com a fila gravando).
  desligado: { type: Boolean, default: false },
});

const emit = defineEmits(['acao', 'link']);

const TONS = {
  erro: {
    faixa: 'bg-n-ruby-2 border-n-ruby-6 text-n-ruby-11',
    icone: 'i-lucide-circle-alert',
  },
  aviso: {
    faixa: 'bg-n-amber-2 border-n-amber-6 text-n-amber-11',
    icone: 'i-lucide-triangle-alert',
  },
  feito: {
    faixa: 'bg-n-teal-2 border-n-teal-6 text-n-teal-11',
    icone: 'i-lucide-circle-check',
  },
  vazio: {
    faixa: 'bg-n-slate-2 border-n-weak text-n-slate-11',
    icone: 'i-lucide-search',
  },
};
</script>

<template>
  <div
    v-if="faixa"
    role="status"
    class="flex flex-wrap items-center px-4 py-3 border gap-x-3 gap-y-2 rounded-2xl"
    :class="(TONS[tom] || TONS.vazio).faixa"
    :data-estado="tom"
  >
    <span
      class="size-5 shrink-0"
      :class="(TONS[tom] || TONS.vazio).icone"
      aria-hidden="true"
    />
    <p class="flex-1 m-0 text-base min-w-[12rem]">{{ texto }}</p>
    <Button
      v-if="botao"
      :label="botao"
      slate
      faded
      :disabled="desligado"
      class="!min-h-11 !rounded-xl ms-8 md:ms-0"
      @click="emit('acao')"
    />
  </div>
  <section
    v-else
    class="flex flex-col items-center gap-4 px-5 py-12 text-center border rounded-3xl border-n-weak bg-n-solid-1 md:p-12"
    :data-estado="tom"
  >
    <span
      class="grid rounded-full place-items-center size-14"
      :class="
        tom === 'erro'
          ? 'bg-n-ruby-3 text-n-ruby-11'
          : 'bg-n-slate-3 text-n-slate-11'
      "
      aria-hidden="true"
    >
      <span class="size-7" :class="(TONS[tom] || TONS.vazio).icone" />
    </span>
    <p class="max-w-md m-0 text-lg font-semibold text-n-slate-12">
      {{ texto }}
    </p>
    <Button
      v-if="botao"
      :label="botao"
      class="!min-h-12 !rounded-xl !px-6 !text-base"
      @click="emit('acao')"
    />
    <Button
      v-if="link"
      :label="link"
      variant="link"
      class="!min-h-11"
      @click="emit('link')"
    />
  </section>
</template>
