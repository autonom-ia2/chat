<script setup>
// O modelo de e-mail escolhido no "+" (#1786), embaixo do texto da resposta:
// "Vai este modelo: <nome>", os campos para conferir e a prévia ao vivo. Cada campo
// diz de onde veio o valor (do contato, sugerido pela IA ou falta preencher) e muda
// na hora; campo vazio aparece destacado na prévia. O e-mail sai com o texto do
// atendente em cima e o modelo embaixo (montado no servidor).
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { chaveDoNomeDoCampo, preencherModelo } from './modeloDeEmail';

const props = defineProps({
  // { nome, html, campos: [{ chave, valor, origem }] }
  modelo: { type: Object, required: true },
  valores: { type: Object, required: true },
});
const emit = defineEmits(['campo', 'tirar']);

const { t } = useI18n();
const aberto = ref(true);
const moldura = useTemplateRef('moldura');
const altura = ref(320);
const ALTURA_MAXIMA = 520;

const ORIGENS = {
  contato: {
    chave: 'DO_CONTATO',
    cor: 'bg-n-teal-3 text-n-teal-11',
    icone: 'i-lucide-user-round',
  },
  ia: {
    chave: 'SUGERIDO_PELA_IA',
    cor: 'bg-n-iris-3 text-n-iris-11',
    icone: 'i-lucide-sparkles',
  },
  vazio: {
    chave: 'PREENCHA',
    cor: 'bg-n-amber-3 text-n-amber-11',
    icone: 'i-lucide-pencil',
  },
};
const origemDoCampo = campo => {
  if (!String(props.valores[campo.chave] ?? '').trim()) return ORIGENS.vazio;
  if (props.valores[campo.chave] !== campo.valor) return null;
  return ORIGENS[campo.origem] || null;
};
// Campo conhecido com nome traduzido; o resto, legível: "contact.numero_da_cotacao" →
// "Numero da cotacao".
const legivel = chave => {
  const texto = String(chave)
    .split('.')
    .pop()
    .split('_')
    .join(' ')
    .trim();
  return texto.charAt(0).toUpperCase() + texto.slice(1);
};
const rotulo = chave => {
  const nome = chaveDoNomeDoCampo(chave);
  return nome ? t(`CONVERSA_CANAL.EMAIL.CAMPO.${nome}`) : legivel(chave);
};
const faltam = computed(
  () =>
    props.modelo.campos.filter(c => !String(props.valores[c.chave] ?? '').trim())
      .length
);

// Prévia sem script (sandbox) e sem clique nos links do modelo.
const previa = computed(() => {
  const html = preencherModelo(props.modelo.html || '', props.valores, {
    marcar: true,
  });
  const estilo = '<style>a{pointer-events:none}body{margin:0}</style>';
  const fimDoHead = html.indexOf('</head>');
  return fimDoHead < 0
    ? `${estilo}${html}`
    : `${html.slice(0, fimDoHead)}${estilo}${html.slice(fimDoHead)}`;
});
const medir = () => {
  const doc = moldura.value?.contentDocument;
  const total = doc?.documentElement?.scrollHeight || 0;
  if (total) altura.value = Math.min(ALTURA_MAXIMA, total);
};

const LINK =
  'inline-flex items-center gap-1 min-h-9 px-3 rounded-full text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <section
    class="mt-3 mb-1 rounded-xl border border-n-weak bg-n-surface-1"
    data-modelo-da-resposta
  >
    <header
      class="flex flex-wrap items-center justify-between gap-x-2 ps-3 pe-1 py-1"
    >
      <p class="flex items-center gap-2 min-w-0 text-[13px] text-n-slate-12">
        <Icon icon="i-ph-layout-fill" class="size-4 flex-shrink-0 text-n-teal-10" />
        <span class="truncate">
          {{ t('CONVERSA_CANAL.EMAIL.VAI_O_MODELO', { nome: modelo.nome }) }}
        </span>
        <span
          v-if="faltam"
          class="inline-flex items-center h-5 px-1.5 rounded text-[11px] font-medium bg-n-amber-3 text-n-amber-11 whitespace-nowrap"
        >
          {{
            t('CONVERSA_CANAL.EMAIL.CAMPOS_FALTANDO', { total: faltam }, faltam)
          }}
        </span>
      </p>
      <div class="flex items-center gap-1">
        <button
          type="button"
          :class="[LINK, 'text-n-slate-11 hover:bg-n-alpha-2']"
          :aria-expanded="aberto"
          data-ver-modelo
          @click="aberto = !aberto"
        >
          {{
            aberto
              ? t('CONVERSA_CANAL.EMAIL.ESCONDER')
              : t('CONVERSA_CANAL.EMAIL.VER')
          }}
          <Icon
            :icon="aberto ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            class="size-4"
          />
        </button>
        <button
          type="button"
          :class="[LINK, 'text-n-slate-11 hover:bg-n-alpha-2']"
          data-tirar-modelo
          @click="emit('tirar')"
        >
          {{ t('CONVERSA_CANAL.EMAIL.TIRAR_MODELO') }}
        </button>
      </div>
    </header>
    <div v-if="aberto" class="px-3 pb-3">
      <div
        v-if="modelo.campos.length"
        class="grid sm:grid-cols-2 gap-x-3 gap-y-2 mb-3"
        data-campos-do-modelo
      >
        <label
          v-for="campo in modelo.campos"
          :key="campo.chave"
          class="flex flex-col gap-1 min-w-0"
        >
          <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
            <span class="truncate">{{ rotulo(campo.chave) }}</span>
            <span
              v-if="origemDoCampo(campo)"
              class="inline-flex items-center gap-1 h-5 px-1.5 rounded text-[11px] font-medium whitespace-nowrap"
              :class="origemDoCampo(campo).cor"
            >
              <Icon :icon="origemDoCampo(campo).icone" class="size-3" />
              {{ t(`CONVERSA_CANAL.EMAIL.${origemDoCampo(campo).chave}`) }}
            </span>
          </span>
          <input
            type="text"
            :value="valores[campo.chave]"
            class="w-full h-10 px-3 !mb-0 rounded-lg border bg-n-alpha-1 text-sm text-n-slate-12 focus:outline focus:outline-2 focus:outline-n-brand"
            :class="
              String(valores[campo.chave] ?? '').trim()
                ? 'border-n-weak'
                : 'border-n-amber-7'
            "
            :data-campo-do-modelo="campo.chave"
            @input="emit('campo', campo.chave, $event.target.value)"
          />
        </label>
      </div>
      <iframe
        ref="moldura"
        :srcdoc="previa"
        sandbox="allow-same-origin"
        class="block w-full rounded-lg border border-n-weak bg-white"
        :style="{ height: `${altura}px` }"
        :title="t('CONVERSA_CANAL.EMAIL.PREVIA_DO_MODELO')"
        data-previa-do-modelo
        @load="medir"
      />
    </div>
  </section>
</template>
