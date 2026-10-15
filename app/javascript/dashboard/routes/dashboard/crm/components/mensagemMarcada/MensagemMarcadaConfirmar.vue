<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// #1590 — "Confira": o que vai acontecer, em três frases (por onde sai, quem
// é avisado se não sair, onde aparece), e a anotação para a equipe, que fica
// guardada atrás de um botão para não pesar em quem só quer marcar.
defineProps({
  alvo: { type: Object, required: true },
  peloCelular: { type: Boolean, default: false },
  erro: { type: String, default: '' },
});
const anotacao = defineModel({ type: String, default: '' });

const { t } = useI18n();
const M = 'CRM_MENSAGEM_MARCADA.CONFIRMAR';
const comAnotacao = ref(Boolean(anotacao.value));
</script>

<template>
  <section data-passo="confirmar" class="flex flex-col gap-5">
    <p
      v-if="erro"
      role="alert"
      class="mb-0 rounded-2xl border border-n-ruby-7 bg-n-ruby-2 px-4 py-3 text-[0.9375rem] text-n-ruby-11"
    >
      {{ t(`${M}.ERRO.${erro}`) }}
    </p>
    <h3 class="mb-0 text-base font-semibold text-n-slate-12">
      {{ t(`${M}.O_QUE_ACONTECE`) }}
    </h3>
    <ul class="m-0 flex list-none flex-col gap-3 p-0">
      <li class="flex items-start gap-3 text-[0.9375rem] text-n-slate-12">
        <span
          class="i-lucide-smartphone mt-0.5 size-5 shrink-0 text-n-teal-11"
          aria-hidden="true"
        />
        {{
          peloCelular
            ? t(`${M}.SAI_PELO_CELULAR`, { caixa: alvo.caixaNome })
            : t(`${M}.SAI_POR`, { caixa: alvo.caixaNome })
        }}
      </li>
      <li class="flex items-start gap-3 text-[0.9375rem] text-n-slate-12">
        <span
          class="i-lucide-bell mt-0.5 size-5 shrink-0 text-n-amber-11"
          aria-hidden="true"
        />
        {{
          alvo.dono
            ? t(`${M}.SE_FALHAR`, { nome: alvo.dono })
            : t(`${M}.SE_FALHAR_SEM_DONO`)
        }}
      </li>
      <li class="flex items-start gap-3 text-[0.9375rem] text-n-slate-12">
        <span
          class="i-lucide-calendar-check mt-0.5 size-5 shrink-0 text-n-blue-11"
          aria-hidden="true"
        />
        {{ t(`${M}.ONDE_APARECE`) }}
      </li>
    </ul>
    <Button
      v-if="!comAnotacao"
      data-foco
      :label="t(`${M}.ANOTAR`)"
      icon="i-lucide-notebook-pen"
      slate
      faded
      class="!min-h-11 self-start"
      @click="comAnotacao = true"
    />
    <TextArea
      v-else
      v-model="anotacao"
      :label="t(`${M}.ANOTACAO`)"
      :placeholder="t(`${M}.ANOTACAO_EXEMPLO`)"
      :max-length="2000"
      auto-height
      min-height="4rem"
    />
  </section>
</template>
