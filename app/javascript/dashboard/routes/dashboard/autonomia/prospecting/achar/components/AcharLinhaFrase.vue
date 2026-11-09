<script setup>
// #2692 — uma linha-frase com "Alterar" explícito (molde
// automacoes/livre/components/LivreConfira.vue: ícone em quadrado size-11
// rounded-2xl). Serve à porta ("Como vamos procurar"), às prévias da folha e à
// linha de destino da fila. Tracejada quando falta a resposta ("Escolha o
// funil").
// Rodada 2: em 390 a linha empilha — ícone e texto em cima, "Alterar" embaixo,
// alinhado ao texto —, para o texto nunca quebrar letra a letra. `compacta` é
// a versão de uma linha só (rodapé da fila e da gaveta).
// Rodada 3: "Alterar" é sempre o mesmo botão cinza pequeno, à direita do
// texto, nas duas versões e nas duas larguras.
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  icone: { type: String, required: true },
  tom: { type: String, default: 'azul' },
  rotulo: { type: String, default: '' },
  texto: { type: String, required: true },
  podeAlterar: { type: Boolean, default: false },
  tracejada: { type: Boolean, default: false },
  compacta: { type: Boolean, default: false },
  // Rodada 5: campo vazio diz "Escolher" (não há o que alterar).
  rotuloAcao: { type: String, default: '' },
  // Rodada 4: no celular o texto ganha a largura toda e "Alterar" desce,
  // alinhado à direita ("Como vamos procurar" em até 2 linhas).
  alterarEmbaixo: { type: Boolean, default: false },
  // Enquanto a IA lê o pedido em uma frase (#2696), "Alterar" não abre nada.
  bloqueado: { type: Boolean, default: false },
});

const emit = defineEmits(['alterar']);

const TONS = {
  azul: 'bg-n-blue-3 text-n-blue-11',
  verde: 'bg-n-teal-3 text-n-teal-11',
  violeta: 'bg-n-iris-3 text-n-iris-11',
  ambar: 'bg-n-amber-3 text-n-amber-11',
  cinza: 'bg-n-slate-3 text-n-slate-11',
};
</script>

<template>
  <p
    v-if="compacta"
    class="flex items-center m-0 text-sm gap-x-2 text-n-slate-12"
    data-linha-frase
  >
    <span class="size-4 shrink-0 text-n-slate-11" :class="icone" />
    <span class="flex-1 min-w-0 break-words">{{ texto }}</span>
    <Button
      v-if="podeAlterar"
      :label="rotuloAcao || $t('PROSPECTING_ACHAR.COMUM.ALTERAR')"
      slate
      faded
      size="sm"
      class="!min-h-11 !rounded-xl shrink-0"
      :disabled="bloqueado"
      data-alterar
      @click="emit('alterar')"
    />
  </p>
  <div
    v-else
    class="flex items-center gap-3 p-4 rounded-2xl md:gap-4"
    :class="[
      tracejada
        ? 'border-dashed border-2 border-n-slate-7'
        : 'border border-n-slate-6 bg-n-solid-1',
      { 'flex-wrap md:flex-nowrap': alterarEmbaixo },
    ]"
    data-linha-frase
  >
    <div
      class="flex items-center flex-1 min-w-0 gap-3 md:gap-4"
      :class="{ 'basis-full md:basis-auto': alterarEmbaixo }"
    >
      <span
        class="grid shrink-0 place-items-center rounded-2xl size-11"
        :class="[TONS[tom] || TONS.azul, { 'hidden md:grid': alterarEmbaixo }]"
        aria-hidden="true"
      >
        <span class="size-5" :class="icone" />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-0.5">
        <span v-if="rotulo" class="text-sm font-semibold text-n-slate-11">
          {{ rotulo }}
        </span>
        <span class="text-base break-words text-n-slate-12">{{ texto }}</span>
      </div>
    </div>
    <Button
      v-if="podeAlterar"
      :label="rotuloAcao || $t('PROSPECTING_ACHAR.COMUM.ALTERAR')"
      slate
      faded
      size="sm"
      class="!min-h-11 !rounded-xl shrink-0"
      :class="{ 'ms-auto md:ms-0': alterarEmbaixo }"
      :disabled="bloqueado"
      data-alterar
      @click="emit('alterar')"
    />
  </div>
</template>
