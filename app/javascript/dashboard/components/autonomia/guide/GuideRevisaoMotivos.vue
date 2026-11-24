<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

// #3158 (B8b) — os motivos da revisão de conversas, do mais comum ao menos.
// Tocar num motivo abre a lista das conversas dele, cada uma com o link.
const props = defineProps({
  revisao: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const aberto = ref(null);

const categorias = computed(() => props.revisao.categorias || []);
const maior = computed(() =>
  Math.max(1, ...categorias.value.map(c => c.conversas.length))
);

const diaMes = iso => {
  const [, mes, dia] = String(iso || '').split('-');
  return dia && mes ? `${dia}/${mes}` : '';
};

const periodo = computed(() =>
  t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.PERIODO', {
    de: diaMes(props.revisao.de),
    ate: diaMes(props.revisao.ate),
  })
);

// "nenhuma faltando" só quando leu tudo o que escolheu.
const situacao = computed(() => {
  const { lidas, falhas, faltam } = props.revisao;
  if (faltam > 0)
    return t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.FALTAM', { lidas, faltam });
  if (falhas > 0)
    return t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.NAO_ABRIRAM', { lidas, falhas });
  return t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.COMPLETA', { lidas });
});
const completa = computed(
  () => props.revisao.faltam === 0 && props.revisao.falhas === 0
);

const nome = categoria =>
  categoria.outros
    ? t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.OUTROS')
    : categoria.nome;

const largura = categoria =>
  `${Math.round((categoria.conversas.length / maior.value) * 100)}%`;

const alternar = indice => {
  aberto.value = aberto.value === indice ? null : indice;
};

const linkDaConversa = numero =>
  frontendURL(conversationUrl({ accountId: accountId.value, id: numero }));
</script>

<template>
  <section
    class="rounded-lg border border-n-weak bg-n-solid-1 p-3 flex flex-col gap-2"
    :aria-label="t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.TITULO')"
  >
    <p class="mb-0 text-sm font-medium text-n-slate-12">
      {{ t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.TITULO') }}
    </p>
    <p class="mb-0 text-xs text-n-slate-11">{{ periodo }}</p>
    <p
      class="mb-0 flex items-center gap-1 text-xs"
      :class="completa ? 'text-n-teal-11' : 'text-n-amber-11'"
    >
      <span
        class="size-4 shrink-0"
        :class="completa ? 'i-lucide-circle-check' : 'i-lucide-circle-alert'"
        aria-hidden="true"
      />
      {{ situacao }}
    </p>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.TOQUE') }}
    </p>
    <ul class="flex flex-col m-0 p-0 list-none">
      <li v-for="(categoria, indice) in categorias" :key="indice">
        <button
          type="button"
          class="w-full min-h-11 py-2 flex flex-col gap-1 text-left"
          :aria-expanded="aberto === indice ? 'true' : 'false'"
          :aria-controls="`revisao-${revisao.id}-motivo-${indice}`"
          @click="alternar(indice)"
        >
          <span class="w-full flex items-center gap-2 text-sm text-n-slate-12">
            <span class="flex-1 min-w-0 break-words">{{
              nome(categoria)
            }}</span>
            <span class="font-medium tabular-nums">
              {{ categoria.conversas.length }}
            </span>
            <span
              class="size-4 shrink-0 text-n-slate-10"
              :class="
                aberto === indice
                  ? 'i-lucide-chevron-down'
                  : 'i-lucide-chevron-right'
              "
              aria-hidden="true"
            />
          </span>
          <span class="block w-full h-1.5 rounded-full bg-n-alpha-2">
            <span
              class="block h-1.5 rounded-full bg-n-brand"
              :style="{ width: largura(categoria) }"
            />
          </span>
        </button>
        <ul
          v-if="aberto === indice"
          :id="`revisao-${revisao.id}-motivo-${indice}`"
          class="flex flex-col gap-1 m-0 mb-2 p-0 list-none"
        >
          <li
            v-for="conversa in categoria.conversas"
            :key="conversa.numero"
            class="text-sm"
          >
            <router-link
              :to="linkDaConversa(conversa.numero)"
              class="flex min-h-11 items-start gap-2 rounded-lg px-2 py-2 hover:bg-n-alpha-2"
            >
              <span class="text-n-blue-11 tabular-nums">
                {{
                  t('AUTONOMIA_GUIDE.REVISAO.MOTIVOS.CONVERSA', {
                    numero: conversa.numero,
                  })
                }}
              </span>
              <span class="flex-1 min-w-0 text-n-slate-11 break-words">
                {{ conversa.motivo }}
              </span>
            </router-link>
          </li>
        </ul>
      </li>
    </ul>
  </section>
</template>
