<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LivreConfira from '../livre/components/LivreConfira.vue';
import LivreEnsaio from '../livre/components/LivreEnsaio.vue';
import { comTextosDaIa, useCatalogo } from '../livre/catalogo';

// #2889 — o lado direito da conversa com o Guia quando a automação é do motor
// novo: Quando → Só se → Faça com as frases do editor, o teste com conversas
// reais e os botões Ligar e Desligar. Só mostra; quem muda é o Guia (conversa)
// ou o editor (modo manual).
const props = defineProps({
  automacao: { type: Object, required: true },
  podeMudar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['ligar', 'desligar', 'modoManual']);

const { t } = useI18n();
const { catalogo, carregarCatalogo } = useCatalogo();
const falhouCatalogo = ref(false);
onMounted(() =>
  carregarCatalogo().catch(() => {
    falhouCatalogo.value = true;
  })
);

const receita = computed(() => props.automacao.versao?.receita || null);
const catalogoComTextos = computed(() =>
  comTextosDaIa(catalogo.value, receita.value?.passos || [], t)
);
const testando = ref(false);

const ligarRef = ref(null);
// "Está ótima" leva ao botão Ligar.
const focarLigar = () => {
  const botao = ligarRef.value?.$el;
  botao?.scrollIntoView?.({ behavior: 'smooth', block: 'center' });
  botao?.focus?.();
};
defineExpose({ focarLigar });
</script>

<template>
  <div data-motor-novo class="flex flex-col gap-5">
    <div
      class="flex flex-col gap-5 p-5 border shadow-sm rounded-3xl border-n-weak bg-n-solid-1"
    >
      <p
        v-if="falhouCatalogo"
        data-erro-catalogo
        role="alert"
        class="mb-0 text-base text-n-slate-12"
      >
        {{ $t('AUTOMACAO_MODELOS.GUIA.ERRO_RESUMO') }}
      </p>
      <div
        v-else-if="!catalogo || !receita"
        aria-busy="true"
        class="h-48 rounded-2xl bg-n-alpha-2 animate-pulse"
      />
      <LivreConfira v-else :receita="receita" :catalogo="catalogoComTextos" />
    </div>

    <template v-if="catalogo && receita">
      <Button
        v-if="!testando"
        data-testar
        :label="$t('AUTOMACAO_MODELOS.GUIA.TESTAR')"
        icon="i-lucide-flask-conical"
        slate
        faded
        class="min-h-11"
        @click="testando = true"
      />
      <LivreEnsaio
        v-else
        :key="automacao.versao?.id"
        :automacao-id="automacao.id"
        :receita="receita"
        :catalogo="catalogoComTextos"
        @fechar="testando = false"
      />
    </template>

    <template v-if="podeMudar">
      <div v-if="!automacao.ativa" class="flex flex-col gap-2.5">
        <Button
          ref="ligarRef"
          data-ligar
          :label="$t('AUTOMACOES.CONVERSA.LIGAR')"
          icon="i-lucide-power"
          teal
          size="lg"
          justify="center"
          class="w-full !min-h-14 !text-lg !font-bold !rounded-2xl shadow-lg"
          :is-loading="ocupado"
          :disabled="ocupado"
          @click="emit('ligar')"
        />
        <p data-situacao class="mb-0 text-sm text-center text-n-slate-11">
          {{ $t('AUTOMACOES.CONVERSA.DESLIGADA_AVISO') }}
        </p>
      </div>
      <div
        v-else
        data-ligada
        role="status"
        class="flex items-center gap-4 p-5 rounded-2xl bg-n-teal-3"
      >
        <span
          class="grid text-white rounded-full place-items-center size-10 shrink-0 bg-n-teal-10"
        >
          <span class="i-lucide-check size-5" aria-hidden="true" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="mb-0 text-base font-semibold text-n-teal-12">
            {{ $t('AUTOMACOES.CONVERSA.LIGADA_TITULO') }}
          </p>
          <p data-situacao class="mb-0 text-[0.9375rem] text-n-teal-11">
            {{ $t('AUTOMACOES.CONVERSA.LIGADA_AVISO') }}
          </p>
        </div>
        <Button
          data-desligar
          :label="$t('AUTOMACOES.CONVERSA.DESLIGAR')"
          teal
          link
          class="min-h-11 shrink-0 !font-semibold"
          :is-loading="ocupado"
          :disabled="ocupado"
          @click="emit('desligar')"
        />
      </div>
    </template>
    <p
      v-else
      class="mb-0 p-4 text-[0.9375rem] rounded-2xl bg-n-alpha-1 text-n-slate-11"
    >
      {{ $t('AUTOMACOES.CONVERSA.SO_LEITURA') }}
    </p>

    <Button
      data-modo-manual
      :label="$t('AUTOMACOES.CONVERSA.MODO_MANUAL')"
      icon="i-lucide-sliders-horizontal"
      link
      slate
      class="self-center min-h-11"
      @click="emit('modoManual')"
    />
  </div>
</template>
