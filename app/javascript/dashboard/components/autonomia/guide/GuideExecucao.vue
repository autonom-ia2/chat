<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import { avisarContaMudou } from './contaMudou';
import { motivoUtilizavel } from 'dashboard/store/modules/autonomiaGuide';
import Button from 'dashboard/components-next/button/Button.vue';

// O que o Guia FEZ num turno (#855), com o botão de desfazer. O Guia age sem
// pedir confirmação; o que protege a conta é poder voltar atrás por 5 dias.
// Este cartão aparece embaixo da resposta e na lista "Feito pelo Guia".
const props = defineProps({
  execucao: {
    type: Object,
    required: true,
  },
  // Na lista, a data diz QUANDO foi; embaixo da resposta, é agora.
  mostrarData: {
    type: Boolean,
    default: false,
  },
});

const { t, locale } = useI18n();

// Data e hora no formato do idioma de quem está olhando.
const quando = iso =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(iso));

// Cópia local: o desfazer devolve a execução atualizada e o cartão passa a
// mostrar o desfecho sem depender de quem o desenhou.
const atual = ref({ ...props.execucao });
const desfazendo = ref(false);
const erro = ref('');

const passos = computed(() => atual.value.passos || []);
const conflitos = computed(() => atual.value.relatorio?.conflitos || []);
const temPendencias = computed(() => (atual.value.pendencias || []).length > 0);
const podeDesfazer = computed(
  () => atual.value.desfazivel && !desfazendo.value
);

const desfazer = async () => {
  if (!podeDesfazer.value) return;
  desfazendo.value = true;
  erro.value = '';
  try {
    const { data } = await AutonomiaGuideAPI.desfazer(atual.value.id);
    atual.value = data.execucao;
    avisarContaMudou();
  } catch (error) {
    erro.value =
      motivoUtilizavel(error?.response?.data?.error) ||
      t('AUTONOMIA_GUIDE.DONE.UNDO_FAILED');
  } finally {
    desfazendo.value = false;
  }
};
</script>

<template>
  <div
    class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2"
  >
    <p class="mb-0 text-xs font-medium text-n-slate-11">
      {{
        mostrarData
          ? $t('AUTONOMIA_GUIDE.DONE.TITLE_AT', {
              quando: quando(atual.criada_em),
            })
          : $t('AUTONOMIA_GUIDE.DONE.TITLE')
      }}
    </p>
    <ul class="flex flex-col gap-1 mb-0 list-none p-0">
      <li
        v-for="(passo, indice) in passos"
        :key="indice"
        class="flex items-start gap-2 text-sm break-words"
        :class="passo.ok ? 'text-n-slate-12' : 'text-n-ruby-11'"
      >
        <span
          class="size-4 shrink-0 mt-1"
          :class="passo.ok ? 'i-lucide-check text-n-teal-11' : 'i-lucide-x'"
          aria-hidden="true"
        />
        <span>
          <span class="sr-only">
            {{
              passo.ok
                ? $t('AUTONOMIA_GUIDE.DONE.STEP_OK')
                : $t('AUTONOMIA_GUIDE.DONE.STEP_FAILED')
            }}
          </span>
          {{ passo.frase }}
        </span>
      </li>
    </ul>
    <p
      v-if="temPendencias && !atual.desfeita_em"
      class="mb-0 text-sm text-n-amber-11"
    >
      {{ $t('AUTONOMIA_GUIDE.DONE.PARTIAL') }}
    </p>
    <template v-if="atual.desfeita_em">
      <p class="mb-0 text-sm font-medium text-n-teal-11">
        {{ $t('AUTONOMIA_GUIDE.DONE.UNDONE') }}
      </p>
      <p v-if="conflitos.length" class="mb-0 text-sm text-n-amber-11">
        {{ $t('AUTONOMIA_GUIDE.DONE.CONFLICTS', { count: conflitos.length }) }}
      </p>
    </template>
    <p v-if="erro" class="mb-0 text-sm text-n-ruby-11">{{ erro }}</p>
    <div v-if="atual.desfazivel" class="flex flex-wrap items-center gap-2">
      <Button
        :label="
          desfazendo
            ? $t('AUTONOMIA_GUIDE.DONE.UNDOING')
            : $t('AUTONOMIA_GUIDE.DONE.UNDO')
        "
        :disabled="desfazendo"
        icon="i-lucide-undo-2"
        class="min-h-11"
        slate
        faded
        @click="desfazer"
      />
      <span class="text-xs text-n-slate-11">
        {{
          $t('AUTONOMIA_GUIDE.DONE.UNTIL', {
            quando: quando(atual.expira_em),
          })
        }}
      </span>
    </div>
  </div>
</template>
