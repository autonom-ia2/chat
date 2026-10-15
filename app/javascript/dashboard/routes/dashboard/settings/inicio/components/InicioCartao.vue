<script setup>
import { computed } from 'vue';

// Um cartão da página inicial de Configurações (#1617), no molde do AutomacaoModelos: o cartão inteiro é o link,
// ícone grande, título, uma frase do que resolve e, no pé tracejado, o estado real ou o que falta.
// Cor do ícone diz o estado: verde = pronto, âmbar = falta, azul = comece por aqui, cinza = só informação.
const props = defineProps({
  cartao: { type: Object, required: true },
  destaque: { type: Boolean, default: false },
});

const TONS = {
  falta: 'bg-n-amber-3 text-n-amber-11',
  erro: 'bg-n-ruby-3 text-n-ruby-11',
  pronto: 'bg-n-teal-3 text-n-teal-11',
  destaque: 'bg-n-blue-3 text-n-blue-11',
  neutro: 'bg-n-slate-3 text-n-slate-11',
};

const tom = computed(() => {
  if (props.destaque) return TONS.destaque;
  return TONS[props.cartao.estado?.tipo] || TONS.neutro;
});
const falta = computed(() => props.cartao.estado?.tipo === 'falta');
const erro = computed(() => props.cartao.estado?.tipo === 'erro');
</script>

<template>
  <li class="flex min-w-0">
    <RouterLink
      :to="cartao.to"
      :data-cartao="cartao.id"
      class="group flex flex-col w-full gap-4 p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand motion-reduce:transition-none motion-reduce:hover:translate-y-0"
    >
      <span class="flex items-start justify-between w-full gap-3">
        <span
          class="grid shrink-0 place-items-center size-14 rounded-2xl"
          :class="tom"
          aria-hidden="true"
        >
          <span class="size-7" :class="cartao.icone" />
        </span>
        <span
          class="inline-flex items-center gap-1.5 pt-1 text-sm font-medium text-n-blue-11 opacity-80 group-hover:opacity-100"
        >
          {{ $t('SETTINGS_INICIO.ABRIR') }}
          <span
            class="i-lucide-arrow-right size-4 rtl:rotate-180"
            aria-hidden="true"
          />
        </span>
      </span>
      <span class="flex flex-col gap-1.5">
        <span class="text-lg font-semibold leading-snug text-n-slate-12">
          {{ cartao.titulo }}
        </span>
        <span class="text-[0.9375rem] leading-relaxed text-n-slate-11">
          {{ cartao.texto }}
        </span>
      </span>
      <span
        v-if="cartao.estado"
        class="flex items-center w-full gap-2 pt-4 mt-auto text-sm border-t border-dashed border-n-weak"
      >
        <span
          v-if="falta"
          data-falta
          class="inline-flex items-center gap-1.5 rounded-full bg-n-amber-3 px-3 py-1 font-semibold text-n-amber-11 ring-1 ring-inset ring-n-amber-6"
        >
          <span class="i-lucide-circle-alert size-4" aria-hidden="true" />
          {{ cartao.estado.texto }}
        </span>
        <span
          v-else-if="erro"
          data-erro
          class="inline-flex items-center gap-1.5 rounded-full bg-n-ruby-3 px-3 py-1 font-semibold text-n-ruby-11 ring-1 ring-inset ring-n-ruby-6"
        >
          <span class="i-lucide-plug-zap size-4" aria-hidden="true" />
          {{ cartao.estado.texto }}
        </span>
        <span
          v-else
          class="inline-flex items-center gap-1.5"
          :class="
            cartao.estado.tipo === 'pronto'
              ? 'text-n-teal-11 font-medium'
              : 'text-n-slate-11'
          "
        >
          <span
            v-if="cartao.estado.tipo === 'pronto'"
            class="i-lucide-circle-check size-4"
            aria-hidden="true"
          />
          <span v-else class="i-lucide-info size-4" aria-hidden="true" />
          {{ cartao.estado.texto }}
        </span>
      </span>
    </RouterLink>
  </li>
</template>
