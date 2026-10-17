<script setup>
// #1423 — o retorno do jeito que vai acontecer. Lembrete: o aviso que chega
// para a equipe. Esconder a conversa: some da caixa e volta no dia. Mensagem:
// o balão com exatamente o texto que sai (a mensagem pronta, quando é ela).
// Quando só sabemos o nome da mensagem pronta (outra caixa), o balão diz que
// sai o texto aprovado, sem fingir que o nome é a mensagem. Fora das 24 horas
// sem mensagem pronta, nada de balão do texto livre: ele não sai, e a prévia
// diz o que falta.
defineProps({
  modo: { type: String, required: true },
  titulo: { type: String, default: '' },
  quando: { type: String, default: '' },
  mensagem: { type: String, default: '' },
  pronta: { type: String, default: '' },
  prontaSemTexto: { type: Boolean, default: false },
  // 'digitar' ou 'escolher' quando a mensagem pronta ainda falta.
  prontaFalta: { type: String, default: '' },
  cliente: { type: String, default: '' },
  // #1460/#1462: como repete, as próximas datas e quem recebe.
  repete: { type: String, default: '' },
  proximas: { type: Array, default: () => [] },
  quemRecebe: { type: String, default: '' },
  quemRecebeTipo: { type: String, default: '' },
  // Só com a flag crm_lembretes_v2: desligada, a prévia fica como antes.
  mostrarQuem: { type: Boolean, default: false },
});
</script>

<template>
  <section
    data-card-previa-retorno
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
  >
    <p class="mb-0 flex items-center gap-2 text-sm font-medium text-n-slate-11">
      <span class="i-lucide-calendar-clock size-4" aria-hidden="true" />
      {{ quando || $t('CRM_CARD.RETORNO.ESCOLHA_QUANDO') }}
    </p>
    <div
      v-if="modo === 'auto_send_message'"
      class="flex flex-col gap-2 rounded-xl bg-n-teal-2 p-3"
    >
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ $t('CRM_CARD.RETORNO.VAI_PARA', { nome: cliente }) }}
      </p>
      <p
        v-if="prontaFalta"
        data-previa-pronta-falta
        class="mb-0 flex items-start gap-2 rounded-xl border border-dashed border-n-amber-8 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
      >
        <span
          class="i-lucide-file-clock mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{
          $t(
            prontaFalta === 'digitar'
              ? 'CRM_CARD.RETORNO.PRONTA_FALTA_DIGITAR'
              : 'CRM_CARD.RETORNO.PRONTA_FALTA_ESCOLHER'
          )
        }}
      </p>
      <p
        v-else-if="prontaSemTexto"
        data-previa-pronta-sem-texto
        class="mb-0 me-auto max-w-[90%] rounded-xl rounded-ss-sm border border-dashed border-n-blue-8 bg-n-solid-1 px-3 py-2 text-sm text-n-slate-11"
      >
        {{ $t('CRM_CARD.RETORNO.SAI_TEXTO_APROVADO') }}
      </p>
      <p
        v-else
        data-previa-balao
        class="mb-0 me-auto max-w-[90%] whitespace-pre-line break-words rounded-xl rounded-ss-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
      >
        {{ mensagem || $t('CRM_CARD.RETORNO.SEM_MENSAGEM') }}
      </p>
      <p v-if="pronta" class="mb-0 text-start text-xs text-n-slate-11">
        {{ $t('CRM_CARD.RETORNO.SAI_PRONTA', { nome: pronta }) }}
      </p>
    </div>
    <div v-else class="flex items-start gap-3 rounded-xl bg-n-alpha-2 p-3">
      <span
        class="grid size-9 shrink-0 place-items-center rounded-xl"
        :class="
          modo === 'snooze_conversation'
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-amber-3 text-n-amber-11'
        "
        aria-hidden="true"
      >
        <span
          class="size-4"
          :class="
            modo === 'snooze_conversation'
              ? 'i-lucide-moon'
              : 'i-lucide-bell-ring'
          "
        />
      </span>
      <span class="flex min-w-0 flex-col gap-0.5">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ titulo || $t('CRM_CARD.RETORNO.SEM_TITULO') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{
            $t(
              modo === 'snooze_conversation'
                ? 'CRM_CARD.RETORNO.PREVIA_ESCONDE'
                : 'CRM_CARD.RETORNO.PREVIA_LEMBRETE'
            )
          }}
        </span>
      </span>
    </div>
    <div
      v-if="repete"
      data-previa-repete
      class="flex flex-col gap-1.5 rounded-xl bg-n-blue-2 p-3"
    >
      <p
        class="mb-0 flex items-center gap-2 text-sm font-semibold text-n-blue-11"
      >
        <span class="i-lucide-repeat size-4" aria-hidden="true" />
        {{ repete }}
      </p>
      <p v-if="proximas.length" class="mb-0 text-sm text-n-slate-12">
        {{
          $t('CRM_LEMBRETE.PREVIA.PROXIMAS', { datas: proximas.join(' · ') })
        }}
      </p>
    </div>
    <p
      v-if="mostrarQuem && modo !== 'auto_send_message'"
      data-previa-quem
      class="mb-0 flex items-start gap-2 border-t border-n-weak pt-3 text-sm text-n-slate-12"
    >
      <span
        class="i-lucide-bell-ring mt-0.5 size-4 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{
        quemRecebe
          ? $t(
              quemRecebeTipo === 'dono'
                ? 'CRM_LEMBRETE.PREVIA.AVISA_DONO'
                : 'CRM_LEMBRETE.PREVIA.AVISA',
              { nomes: quemRecebe }
            )
          : $t('CRM_LEMBRETE.PREVIA.AVISA_FALTA')
      }}
    </p>
  </section>
</template>
