<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import OrigemFormulario from './OrigemFormulario.vue';

// #2195 — cliente que chegou pelo formulário do anúncio da Meta: de qual formulário e anúncio veio e o que
// respondeu, aberto no card (não há conversa para mostrar ainda).
const props = defineProps({
  formulario: { type: Object, required: true },
});
const { t } = useI18n();

// #2558: quem não vê o anúncio de origem recebe o formulário sem nome, anúncio nem campanha; fica a origem genérica.
const frase = computed(() =>
  props.formulario.form_name || props.formulario.ad_name
    ? t('CRM_CARD.ORIGEM.FORMULARIO_META', {
        formulario: props.formulario.form_name,
        anuncio: props.formulario.ad_name,
      })
    : t('CRM_CARD.ORIGEM.FORMULARIO_META_GENERICO')
);
</script>

<template>
  <section
    data-origem-anuncio-meta
    class="flex flex-col gap-3 rounded-2xl border border-solid border-n-weak bg-n-solid-1 px-4 py-3 sm:px-5"
  >
    <div class="flex items-start gap-3">
      <span
        class="grid size-9 shrink-0 place-items-center rounded-xl bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="i-lucide-megaphone size-5" />
      </span>
      <div class="flex min-w-0 flex-col gap-0.5">
        <h3 class="mb-0 text-sm font-medium text-n-slate-11">
          {{ t('CRM_CARD.ORIGEM.TELA') }}
        </h3>
        <p class="mb-0 text-[0.9375rem] font-medium text-n-slate-12">
          {{ frase }}
        </p>
      </div>
    </div>
    <OrigemFormulario :formulario="formulario" />
  </section>
</template>
