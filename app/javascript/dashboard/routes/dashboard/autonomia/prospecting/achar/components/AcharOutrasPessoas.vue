<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #2693 — P1 da crítica r5, opção (a) do Rodrigo: "Falar com outra pessoa"
// abre, dentro da gaveta, os outros sócios que a pesquisa achou (sem quem já é
// o dono). Cada um tem "Usar esta pessoa", que vira com quem falar
// (adopt_owner). Sem o link de buscar o dono de novo.
defineProps({
  socios: { type: Array, required: true },
  // Nome de quem está sendo usado agora (o botão dele fica ocupado).
  usando: { type: String, default: '' },
});
const emit = defineEmits(['usar']);

const NS = 'PROSPECTING_ACHAR.GAVETA.OUTRAS';
</script>

<template>
  <section class="flex flex-col gap-4" data-outras-pessoas>
    <h3 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ $t(`${NS}.TITULO`) }}
    </h3>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="socio in socios"
        :key="socio.nome"
        class="flex flex-wrap items-center gap-3 p-4 border border-solid rounded-2xl border-n-weak"
        data-socio
      >
        <div class="flex flex-col flex-1 min-w-0 gap-0.5">
          <span class="text-base font-semibold break-words text-n-slate-12">
            {{ socio.nome }}
          </span>
          <span v-if="socio.cargo" class="text-sm text-n-slate-11">
            {{ socio.cargo }}
          </span>
        </div>
        <Button
          :label="$t(`${NS}.USAR`)"
          :aria-label="$t(`${NS}.USAR_ROTULO`, { nome: socio.nome })"
          :is-loading="usando === socio.nome"
          :disabled="Boolean(usando)"
          slate
          faded
          class="!min-h-11 !rounded-xl shrink-0"
          data-usar-pessoa
          @click="emit('usar', socio.nome)"
        />
      </li>
    </ul>
  </section>
</template>
