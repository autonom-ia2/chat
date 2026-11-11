<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatarDiaMes } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import { chaveDaOrigem, podeLiberar } from '../../ficha/origemDaRecusa';
import DialogoDaFicha from './DialogoDaFicha.vue';

// #2894 — a faixa âmbar de quem pediu para não receber mensagens. "Liberar" só
// aparece nas origens que a casa já deixa desfazer; pede confirmação antes (a
// recusa é da pessoa, não da equipe). A frase de apoio diz o que a recusa
// significa (responder a quem escreve segue normal). É aviso fixo, não região
// viva: o resultado de Liberar é anunciado pela região viva da página.
const props = defineProps({
  pessoa: { type: Object, required: true },
  liberando: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['liberar']);

const { t } = useI18n();
const idioma = useIdioma();
const confirmacao = ref(null);

const frase = computed(() => {
  const data = formatarDiaMes(
    props.pessoa.opted_out_at,
    idioma.value,
    props.agora
  );
  const chave = chaveDaOrigem(props.pessoa.opt_out_source);
  // Origem que a casa não conhece: só a primeira frase.
  if (chave === 'outra') {
    return t('RELACIONAMENTOS_FICHA.FAIXA.TEXTO_SIMPLES', { data });
  }
  return t('RELACIONAMENTOS_FICHA.FAIXA.TEXTO', {
    data,
    origem: t(`RELACIONAMENTOS_FICHA.FAIXA.ORIGEM.${chave}`),
  });
});
const liberavel = computed(() => podeLiberar(props.pessoa.opt_out_source));
</script>

<template>
  <div
    data-relacionamentos="faixa-nao-quer"
    class="flex flex-col gap-3 px-5 py-4 rounded-2xl bg-n-amber-3 text-n-amber-11 sm:flex-row sm:items-center sm:justify-between"
  >
    <div class="flex items-start min-w-0 gap-3">
      <span
        class="mt-0.5 i-lucide-bell-off size-5 shrink-0"
        aria-hidden="true"
      />
      <div class="flex flex-col min-w-0 gap-1">
        <p class="m-0 text-base font-medium">{{ frase }}</p>
        <p data-relacionamentos="faixa-apoio" class="m-0 text-sm">
          {{ t('RELACIONAMENTOS_FICHA.FAIXA.APOIO') }}
        </p>
      </div>
    </div>
    <button
      v-if="liberavel"
      type="button"
      data-relacionamentos="liberar"
      class="inline-flex items-center justify-center px-4 text-sm font-medium rounded-xl min-h-11 shrink-0 whitespace-nowrap bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-amber-8 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="confirmacao?.open()"
    >
      {{ t('RELACIONAMENTOS_FICHA.FAIXA.LIBERAR') }}
    </button>
    <DialogoDaFicha
      ref="confirmacao"
      :titulo="
        t('RELACIONAMENTOS_FICHA.FAIXA.CONFIRMA_TITULO', { nome: pessoa.name })
      "
      :texto="t('RELACIONAMENTOS_FICHA.FAIXA.CONFIRMA_TEXTO')"
      :confirmar="t('RELACIONAMENTOS_FICHA.FAIXA.CONFIRMA_BOTAO')"
      :cancelar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
      marca-confirmar="liberar-confirmar"
      :carregando="liberando"
      @confirm="emit('liberar')"
    />
  </div>
</template>
