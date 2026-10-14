<script setup>
import { useI18n } from 'vue-i18n';

// #1385 — o contraste, com falas de cliente: uma pergunta que o atendimento automático responde sozinho e um pedido
// que chama a equipe. O pedido é um exemplo comum; o código não inventa uma mensagem que "bate" com a frase de quem
// configura (quem decide se bate é o sistema, pelo sentido).
const { t } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';
</script>

<template>
  <div class="flex flex-col gap-3">
    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
    >
      <h3
        class="mb-0 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
      >
        <span class="i-lucide-bot size-4 text-n-slate-11" aria-hidden="true" />
        {{ t(`${P}.QUANDO_NAO_TITULO`) }}
      </h3>
      <div class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-3">
        <p
          class="mb-0 max-w-[85%] self-start rounded-xl rounded-es-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
        >
          {{ t(`${P}.QUANDO_NAO_MSG`) }}
        </p>
        <span class="flex max-w-[85%] flex-col items-end gap-0.5 self-end">
          <span class="text-xs text-n-slate-11">{{ t(`${P}.ROBO`) }}</span>
          <span
            class="rounded-xl rounded-ee-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
          >
            {{ t(`${P}.QUANDO_NAO_RESPOSTA`) }}
          </span>
        </span>
      </div>
    </section>
    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-blue-7 bg-n-solid-1 p-4"
    >
      <h3
        class="mb-0 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-user-round-check size-4 text-n-blue-11"
          aria-hidden="true"
        />
        {{ t(`${P}.QUANDO_SIM_TITULO`) }}
      </h3>
      <div class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-3">
        <p
          class="mb-0 max-w-[85%] self-start rounded-xl rounded-es-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
        >
          {{ t(`${P}.QUANDO_SIM_MSG`) }}
        </p>
        <p
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-user-round-check mt-0.5 size-4 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ t(`${P}.QUANDO_SIM_EVENTO`) }}
        </p>
        <span class="flex max-w-[85%] flex-col items-end gap-0.5 self-end">
          <span class="text-xs text-n-slate-11">{{ t(`${P}.ROBO`) }}</span>
          <span
            class="rounded-xl rounded-ee-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
          >
            {{ t(`${P}.QUANDO_SIM_RESPOSTA`) }}
          </span>
        </span>
      </div>
    </section>
    <p class="mb-0 flex items-center gap-2 text-sm text-n-slate-11">
      <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
      {{ t(`${P}.QUANDO_NOTA`) }}
    </p>
  </div>
</template>
