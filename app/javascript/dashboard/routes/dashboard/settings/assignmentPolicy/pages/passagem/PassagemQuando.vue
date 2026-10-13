<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #1385 — quando chamar a equipe, com as palavras de quem configura. O sistema lê a conversa e decide; em branco,
// vale o padrão (o cliente pede para falar com uma pessoa).
const props = defineProps({
  nome: { type: String, required: true },
});

const regra = defineModel({ type: Object, required: true });

const { t } = useI18n();
const Q = 'CRM_KANBAN.PASSAGEM.QUANDO';
const IDEIAS = ['IDEIA_1', 'IDEIA_2', 'IDEIA_3', 'IDEIA_4'];

const texto = computed({
  get: () => regra.value.trigger,
  set: valor => {
    regra.value = { ...regra.value, trigger: valor };
  },
});
const campo = computed(() => `${props.nome}-quando`);
</script>

<template>
  <section class="flex flex-col gap-4" :aria-labelledby="campo">
    <div class="flex flex-col gap-1">
      <h2 :id="campo" class="mb-0 text-lg font-semibold text-n-slate-12">
        {{ t(`${Q}.TITULO`) }}
      </h2>
      <p class="mb-0 text-[0.9375rem] text-n-slate-11">{{ t(`${Q}.AJUDA`) }}</p>
    </div>
    <textarea
      v-model="texto"
      rows="3"
      :aria-labelledby="campo"
      :placeholder="t(`${Q}.EXEMPLO`)"
      class="reset-base !mb-0 w-full resize-y rounded-xl border-0 bg-n-solid-1 px-4 py-3 text-base leading-6 text-n-slate-12 outline outline-1 outline-n-weak placeholder:text-n-slate-10 focus:outline-2 focus:outline-n-brand"
    />
    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-11">{{
        t(`${Q}.IDEIAS`)
      }}</span>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="ideia in IDEIAS"
          :key="ideia"
          type="button"
          class="inline-flex min-h-11 items-center gap-1.5 rounded-full px-3 py-2 text-start text-sm text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="texto = t(`${Q}.${ideia}`)"
        >
          <span
            class="i-lucide-plus size-4 text-n-slate-10"
            aria-hidden="true"
          />
          {{ t(`${Q}.${ideia}`) }}
        </button>
      </div>
    </div>
  </section>
</template>
