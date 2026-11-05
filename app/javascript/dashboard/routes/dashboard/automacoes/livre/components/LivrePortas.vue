<script setup>
// #2498 — As portas da automação nova: montar do zero ou começar de uma
// receita pronta (catalogo.receitas). A receita que pede uma flag que a conta
// não tem fica desabilitada, com o porquê, em vez de deixar salvar e recusar.
const props = defineProps({
  receitas: { type: Array, default: () => [] },
  liberado: { type: Function, required: true },
});
const emit = defineEmits(['receita', 'zero']);

// O ícone e a cor de cada receita. Fica aqui, e não no YAML, porque o
// Tailwind só gera as classes que lê nos .vue.
const ESTILO = {
  BOAS_VINDAS: {
    icone: 'i-lucide-message-circle-heart',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  AGRADECER: {
    icone: 'i-lucide-heart-handshake',
    tom: 'bg-n-ruby-3 text-n-ruby-11',
  },
};
const PADRAO = {
  icone: 'i-lucide-sparkles',
  tom: 'bg-n-slate-3 text-n-slate-11',
};
const estilo = chave => ESTILO[chave] || PADRAO;

const faltando = item =>
  (item.requer || []).filter(flag => !props.liberado(flag));
</script>

<template>
  <section data-portas class="flex flex-col gap-6">
    <h2 class="mb-0 text-2xl font-bold tracking-tight text-n-slate-12">
      {{ $t('AUTOMACAO_LIVRE.RECEITAS.COMO_COMECAR') }}
    </h2>

    <div class="grid gap-4 md:grid-cols-2">
      <button
        type="button"
        data-porta-zero
        class="flex items-start gap-4 p-5 transition border text-start rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-6 min-h-11"
        @click="emit('zero')"
      >
        <span
          class="grid place-items-center size-12 shrink-0 rounded-xl bg-n-slate-3 text-n-slate-11"
          aria-hidden="true"
        >
          <span class="i-lucide-list-plus size-6" />
        </span>
        <span class="flex flex-col gap-1">
          <span class="text-lg font-semibold text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.RECEITAS.ZERO_TITULO') }}
          </span>
          <span class="text-[0.9375rem] text-n-slate-11">
            {{ $t('AUTOMACAO_LIVRE.RECEITAS.ZERO_TEXTO') }}
          </span>
        </span>
      </button>
    </div>

    <div v-if="receitas.length" class="flex flex-col gap-3">
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.RECEITAS.OU_RECEITA') }}
      </h3>
      <ul class="grid gap-3 p-0 m-0 list-none md:grid-cols-2">
        <li v-for="item in receitas" :key="item.chave">
          <button
            type="button"
            data-receita
            :data-chave="item.chave"
            :disabled="faltando(item).length > 0"
            class="flex items-start w-full h-full gap-4 p-5 transition border text-start rounded-2xl border-n-weak bg-n-solid-1 min-h-11 disabled:opacity-100"
            :class="
              faltando(item).length
                ? 'cursor-not-allowed'
                : 'hover:border-n-blue-6'
            "
            @click="emit('receita', item.chave)"
          >
            <!-- Só o que a pessoa não pode usar fica pálido. O aviso do porquê
                 fica com o contraste cheio: o botão global apagaria tudo. -->
            <span
              class="grid place-items-center size-11 shrink-0 rounded-xl"
              :class="[
                estilo(item.chave).tom,
                { 'opacity-50': faltando(item).length },
              ]"
              aria-hidden="true"
            >
              <span :class="estilo(item.chave).icone" class="size-5" />
            </span>
            <span class="flex flex-col gap-1">
              <span
                class="text-base font-semibold text-n-slate-12"
                :class="{ 'opacity-60': faltando(item).length }"
              >
                {{ $t(item.frase) }}
              </span>
              <span
                class="text-[0.9375rem] text-n-slate-11"
                :class="{ 'opacity-60': faltando(item).length }"
              >
                {{ $t(`AUTOMACAO_LIVRE.RECEITAS.${item.chave}.TEXTO`) }}
              </span>
              <span
                v-for="flag in faltando(item)"
                :key="flag"
                data-falta-flag
                class="mt-1 text-sm font-medium text-n-amber-11"
              >
                {{
                  $t(`AUTOMACAO_LIVRE.RECEITAS.REQUER.${flag.toUpperCase()}`)
                }}
              </span>
              <span
                v-if="!faltando(item).length"
                class="mt-1 text-sm font-semibold text-n-blue-11"
              >
                {{ $t('AUTOMACAO_LIVRE.RECEITAS.USAR') }}
              </span>
            </span>
          </button>
        </li>
      </ul>
    </div>
  </section>
</template>
