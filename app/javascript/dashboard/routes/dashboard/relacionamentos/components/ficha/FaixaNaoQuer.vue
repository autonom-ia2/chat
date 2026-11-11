<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { formatarDiaMes } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import { chaveDaOrigem, podeLiberar } from '../../ficha/origemDaRecusa';

// #2894 — a faixa âmbar de quem pediu para não receber mensagens. "Liberar" só
// aparece nas origens que a casa já deixa desfazer; pede confirmação antes. É
// aviso fixo, não região viva: o resultado de Liberar é anunciado pela região
// viva da página.
const props = defineProps({
  pessoa: { type: Object, required: true },
  liberando: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['liberar']);

const { t } = useI18n();
const idioma = useIdioma();
const confirmacao = ref(null);

const frase = computed(() =>
  t('RELACIONAMENTOS_FICHA.FAIXA.TEXTO', {
    data: formatarDiaMes(props.pessoa.opted_out_at, idioma.value, props.agora),
    origem: t(
      `RELACIONAMENTOS_FICHA.FAIXA.ORIGEM.${chaveDaOrigem(props.pessoa.opt_out_source)}`
    ),
  })
);
const liberavel = computed(() => podeLiberar(props.pessoa.opt_out_source));
</script>

<template>
  <div
    data-relacionamentos="faixa-nao-quer"
    class="flex flex-col gap-3 px-5 py-4 rounded-2xl bg-n-amber-3 text-n-amber-11 sm:flex-row sm:items-center sm:justify-between"
  >
    <p class="flex items-start gap-3 m-0 text-base font-medium">
      <span
        class="mt-0.5 i-lucide-bell-off size-5 shrink-0"
        aria-hidden="true"
      />
      {{ frase }}
    </p>
    <Button
      v-if="liberavel"
      amber
      faded
      class="min-h-11 shrink-0"
      :label="t('RELACIONAMENTOS_FICHA.FAIXA.LIBERAR')"
      @click="confirmacao?.open()"
    />
    <Dialog
      ref="confirmacao"
      :title="
        t('RELACIONAMENTOS_FICHA.FAIXA.CONFIRMA_TITULO', { nome: pessoa.name })
      "
      :description="
        t('RELACIONAMENTOS_FICHA.FAIXA.CONFIRMA_TEXTO', { nome: pessoa.name })
      "
      :confirm-button-label="t('RELACIONAMENTOS_FICHA.FAIXA.LIBERAR')"
      :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
      :is-loading="liberando"
      width="sm"
      @confirm="emit('liberar')"
    />
  </div>
</template>
