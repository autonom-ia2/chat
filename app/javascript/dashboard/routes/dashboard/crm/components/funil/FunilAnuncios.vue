<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import FunilInterruptor from './FunilInterruptor.vue';

// #1384 — contar aos anúncios quem comprou. Dois cartões com a mesma
// anatomia (ícone, nome, a frase do que acontece, liga/desliga no canto e
// "Alterar"). Começa pronto: o Facebook e o Instagram recebem só a venda
// feita. O detalhe de cada um fica numa tela própria; ligar o Google abre o
// passo a passo.
const props = defineProps({
  // Nome da etapa em que também avisamos, quando houver.
  etapaAvisada: { type: String, default: '' },
});

const emit = defineEmits(['alterarFacebook', 'abrirGoogle']);

const meta = defineModel('meta', { type: Object, required: true });
const google = defineModel('google', { type: Object, required: true });

const { t } = useI18n();
const A = 'CRM_FUNIL.ANUNCIOS';

const ligarFacebook = valor => {
  meta.value = { ...meta.value, enabled: valor };
};
// Ligar o Google pede o passo a passo; desligar é na hora.
const ligarGoogle = valor => {
  if (valor) emit('abrirGoogle');
  else google.value = { ...google.value, enabled: false };
};

const fraseFacebook = computed(() => {
  if (!meta.value.enabled) return t(`${A}.FACEBOOK.DESLIGADO`);
  return t(`${A}.FACEBOOK.LIGADO`);
});
const detalheFacebook = computed(() => {
  if (!meta.value.enabled) return '';
  const extras = [
    props.etapaAvisada && meta.value.events.moved
      ? t(`${A}.FACEBOOK.TAMBEM_ETAPA`, { nome: props.etapaAvisada })
      : '',
    meta.value.events.lost ? t(`${A}.FACEBOOK.TAMBEM_PERDIDA`) : '',
  ].filter(Boolean);
  return extras.length ? extras.join(' ') : t(`${A}.FACEBOOK.SO_VENDA`);
});

const cartoes = computed(() => [
  {
    chave: 'facebook',
    icone: 'i-ri-facebook-circle-fill',
    tom: 'bg-n-blue-3 text-n-blue-11',
    titulo: t(`${A}.FACEBOOK.TITULO`),
    frase: fraseFacebook.value,
    detalhe: detalheFacebook.value,
    ligado: meta.value.enabled,
    ligar: ligarFacebook,
    alterar: () => emit('alterarFacebook'),
  },
  {
    chave: 'google',
    icone: 'i-lucide-search',
    tom: 'bg-n-amber-3 text-n-amber-11',
    titulo: t(`${A}.GOOGLE.TITULO`),
    frase: t(
      google.value.enabled ? `${A}.GOOGLE.LIGADO` : `${A}.GOOGLE.DESLIGADO`
    ),
    detalhe: google.value.enabled ? t(`${A}.GOOGLE.LIGADO_DETALHE`) : '',
    ligado: google.value.enabled,
    ligar: ligarGoogle,
    alterar: () => emit('abrirGoogle'),
  },
]);
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-for="cartao in cartoes"
      :key="cartao.chave"
      :data-anuncio="cartao.chave"
      class="flex flex-col gap-3 rounded-2xl border bg-n-solid-1 p-5 shadow-sm"
      :class="cartao.ligado ? 'border-n-blue-7' : 'border-n-weak'"
    >
      <label class="flex cursor-pointer items-start gap-4">
        <span
          class="grid size-12 shrink-0 place-items-center rounded-2xl"
          :class="cartao.tom"
          aria-hidden="true"
        >
          <span class="size-6" :class="cartao.icone" />
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-11">
            {{ cartao.titulo }}
          </span>
          <span class="text-base font-semibold leading-relaxed text-n-slate-12">
            {{ cartao.frase }}
          </span>
          <span v-if="cartao.detalhe" class="text-[0.9375rem] text-n-slate-11">
            {{ cartao.detalhe }}
          </span>
        </span>
        <FunilInterruptor
          :model-value="cartao.ligado"
          @update:model-value="cartao.ligar($event)"
        />
      </label>
      <Button
        v-if="cartao.ligado"
        :data-anuncio-alterar="cartao.chave"
        :label="$t('CRM_FUNIL.ALTERAR')"
        :aria-label="$t('CRM_FUNIL.ALTERAR_PARTE', { parte: cartao.titulo })"
        icon="i-lucide-pencil"
        slate
        faded
        class="!min-h-11 w-fit sm:ms-16"
        @click="cartao.alterar"
      />
    </section>
  </div>
</template>
