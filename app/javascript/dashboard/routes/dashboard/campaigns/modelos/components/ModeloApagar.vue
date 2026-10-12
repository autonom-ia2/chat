<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { diaEMes } from '../helpers/datas';
import ModeloUsos from './ModeloUsos.vue';

// Confirmação de apagar: onde ele está em uso, que some de todos os números e
// que o nome fica preso por 30 dias (regra do WhatsApp).
const props = defineProps({
  nome: { type: String, required: true },
  usos: { type: Array, default: () => [] },
  numeros: { type: Array, default: () => [] },
  apagando: { type: Boolean, default: false },
  // Uso que ainda vai sair (campanha agendada, aviso, follow-up): não apaga.
  bloqueado: { type: Boolean, default: false },
});

const emit = defineEmits(['confirmar']);
const { locale } = useI18n();
const dialogo = ref(null);

const DIAS_DO_NOME_PRESO = 30;
const liberaEm = computed(() =>
  diaEMes(
    new Date(
      Date.now() + DIAS_DO_NOME_PRESO * 24 * 60 * 60 * 1000
    ).toISOString(),
    locale.value
  )
);

defineExpose({
  open: () => dialogo.value?.open(),
  close: () => dialogo.value?.close(),
});

// Mantém a lista de números legível ("A, B e C").
const nomesDosNumeros = computed(() => props.numeros.join(', '));
</script>

<template>
  <Dialog
    ref="dialogo"
    type="alert"
    width="lg"
    :title="
      bloqueado
        ? $t('MODELOS_WHATSAPP.APAGAR.BLOQUEADO_TITULO', { nome })
        : $t('MODELOS_WHATSAPP.APAGAR.TITULO', { nome })
    "
    :confirm-button-label="$t('MODELOS_WHATSAPP.APAGAR.CONFIRMAR')"
    :cancel-button-label="
      bloqueado
        ? $t('MODELOS_WHATSAPP.APAGAR.ENTENDI')
        : $t('MODELOS_WHATSAPP.APAGAR.CANCELAR')
    "
    :show-confirm-button="!bloqueado"
    :is-loading="apagando"
    @confirm="emit('confirmar')"
  >
    <div v-if="bloqueado" data-apagar-bloqueado class="flex flex-col gap-4">
      <p class="mb-0 text-[0.9375rem] text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.APAGAR.BLOQUEADO_TEXTO') }}
      </p>
      <ModeloUsos :usos="usos" sem-moldura sem-titulo />
    </div>
    <div v-else data-apagar-dialogo class="flex flex-col gap-4">
      <ul
        class="flex flex-col gap-2.5 p-0 m-0 list-none text-[0.9375rem] text-n-slate-12"
      >
        <li class="flex gap-2.5">
          <span
            class="i-lucide-smartphone size-5 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          {{ $t('MODELOS_WHATSAPP.APAGAR.SOME', { numeros: nomesDosNumeros }) }}
        </li>
        <li class="flex gap-2.5">
          <span
            class="i-lucide-lock size-5 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          {{ $t('MODELOS_WHATSAPP.APAGAR.NOME_PRESO', { dia: liberaEm }) }}
        </li>
        <li class="flex gap-2.5">
          <span
            class="i-lucide-undo-2 size-5 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          {{ $t('MODELOS_WHATSAPP.APAGAR.SEM_VOLTA') }}
        </li>
      </ul>
      <div
        v-if="usos.length"
        class="p-4 rounded-xl bg-n-ruby-2 ring-1 ring-inset ring-n-ruby-6"
      >
        <p class="mb-3 text-[0.9375rem] font-medium text-n-ruby-11">
          {{ $t('MODELOS_WHATSAPP.APAGAR.PARA_DE_SAIR') }}
        </p>
        <ModeloUsos :usos="usos" sem-moldura sem-titulo />
      </div>
    </div>
  </Dialog>
</template>
