<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import NovaConversaTexto from 'dashboard/components-next/NovaConversa/NovaConversaTexto.vue';
import NovaConversaPronta from 'dashboard/components-next/NovaConversa/NovaConversaPronta.vue';

// #1590 — "O que dizer?". Primeiro, uma frase com o que o WhatsApp deixa
// mandar NA HORA MARCADA (não agora):
// - dentro de 1 dia da última mensagem do cliente: texto livre;
// - passou de 1 dia: só mensagem pronta aprovada, com os campos dela;
// - passou de 1 dia, mas a caixa tem o WhatsApp do celular conectado
//   (Híbrido): texto livre, e a frase diz por onde sai.
const props = defineProps({
  nome: { type: String, required: true },
  carregando: { type: Boolean, default: false },
  erro: { type: Boolean, default: false },
  soPronta: { type: Boolean, default: false },
  peloCelular: { type: Boolean, default: false },
  modelos: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'tentar',
  'update:textoDoModelo',
  'update:camposProntos',
]);
const mensagem = defineModel({ type: Object, required: true });

const { t } = useI18n();
const M = 'CRM_MENSAGEM_MARCADA.MENSAGEM';
const pronta = ref(null);

const aviso = computed(() => {
  if (props.carregando) return { tom: 'neutro', chave: 'CONFERINDO' };
  if (props.erro) return { tom: 'atencao', chave: 'ERRO_JANELA' };
  if (props.soPronta) return { tom: 'atencao', chave: 'SO_PRONTA' };
  if (props.peloCelular) return { tom: 'ok', chave: 'PELO_CELULAR' };
  return { tom: 'ok', chave: 'LIVRE' };
});
const TOM = {
  neutro: 'border-n-weak bg-n-alpha-2 text-n-slate-12',
  ok: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
  atencao: 'border-n-amber-7 bg-n-amber-2 text-n-amber-11',
};
const ICONE = {
  neutro: 'i-lucide-loader-circle animate-spin',
  ok: 'i-lucide-circle-check',
  atencao: 'i-lucide-clock-alert',
};

const texto = computed({
  get: () => mensagem.value.texto,
  set: valor => {
    mensagem.value = { ...mensagem.value, texto: valor };
  },
});
const modelo = computed({
  get: () => mensagem.value.modelo,
  set: valor => {
    mensagem.value = { ...mensagem.value, modelo: valor };
  },
});

defineExpose({ montar: () => pronta.value?.montar() ?? null });
</script>

<template>
  <section data-passo="mensagem" class="flex flex-col gap-5">
    <p
      role="status"
      :data-janela="aviso.chave"
      class="mb-0 flex items-start gap-3 rounded-2xl border px-4 py-3 text-[0.9375rem] leading-relaxed"
      :class="TOM[aviso.tom]"
    >
      <span
        class="mt-0.5 size-5 shrink-0"
        :class="ICONE[aviso.tom]"
        aria-hidden="true"
      />
      <span>{{ t(`${M}.${aviso.chave}`, { nome }) }}</span>
    </p>
    <Button
      v-if="erro"
      :label="t(`${M}.TENTAR`)"
      icon="i-lucide-rotate-cw"
      slate
      faded
      class="!min-h-11 self-start"
      @click="emit('tentar')"
    />

    <template v-else-if="!carregando && soPronta">
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${M}.ESCOLHA_PRONTA`) }}
      </h3>
      <NovaConversaPronta
        ref="pronta"
        v-model="modelo"
        :modelos="modelos"
        @update:campos-prontos="emit('update:camposProntos', $event)"
        @update:texto="emit('update:textoDoModelo', $event)"
      />
    </template>

    <template v-else-if="!carregando">
      <NovaConversaTexto v-model="texto" />
    </template>
  </section>
</template>
