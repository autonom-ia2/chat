<script setup>
// #3101 — no passo "Mandar mensagem" (e "Mandar e-mail") da automação: quando a mensagem sai. "Assim que chegar aqui"
// é o de hoje; "No melhor horário do cliente" espera a hora em que ele costuma responder (no máximo 24 horas), dentro
// do horário permitido da conta. Quem nunca respondeu recebe na hora. A resposta a quem acabou de escrever não espera:
// sai na hora, como no limite de mensagens.
import { useI18n } from 'vue-i18n';

defineProps({
  rotulo: { type: String, required: true },
  // O horário permitido da conta em palavras; vazio = a qualquer hora.
  horarioPermitido: { type: String, default: '' },
});
const quando = defineModel({ type: String, default: 'na_hora' });

// O valor que a receita guarda no passo (campo `quando`).
const NA_HORA = 'na_hora';
const MELHOR_HORARIO = 'melhor_horario';

const NS = 'REENVIO_HORARIO.AUTOMACAO';
const { t } = useI18n();
const OPCOES = [
  { valor: NA_HORA, icone: 'i-lucide-zap', chave: 'NA_HORA' },
  { valor: MELHOR_HORARIO, icone: 'i-lucide-clock-4', chave: 'MELHOR_HORARIO' },
];
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-2 border-0 p-0" data-peca="quando">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <div
      class="grid gap-2 sm:grid-cols-2"
      role="radiogroup"
      :aria-label="rotulo"
    >
      <button
        v-for="opcao in OPCOES"
        :key="opcao.valor"
        type="button"
        role="radio"
        :aria-checked="quando === opcao.valor"
        :data-quando="opcao.valor"
        class="flex min-h-11 items-start gap-3 rounded-xl border border-solid px-4 py-3 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          quando === opcao.valor
            ? 'border-n-blue-8 bg-n-blue-2'
            : 'border-n-slate-6 hover:bg-n-alpha-1'
        "
        @click="quando = opcao.valor"
      >
        <span
          :class="[
            opcao.icone,
            quando === opcao.valor ? 'text-n-blue-11' : 'text-n-slate-11',
          ]"
          class="mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.${opcao.chave}`) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t(`${NS}.${opcao.chave}_AJUDA`) }}
          </span>
        </span>
        <!-- A escolhida não depende só do fundo claro: leva a marca. -->
        <span
          v-if="quando === opcao.valor"
          class="i-lucide-circle-check mt-0.5 size-5 shrink-0 text-n-blue-11"
          aria-hidden="true"
          data-quando-marca
        />
      </button>
    </div>
    <p
      v-if="quando === MELHOR_HORARIO"
      class="m-0 flex items-start gap-2 text-xs text-n-slate-11"
      data-quando-regras
    >
      <span
        class="i-lucide-shield-check mt-0.5 size-3.5 shrink-0"
        aria-hidden="true"
      />
      {{
        horarioPermitido
          ? t(`${NS}.REGRAS`, { horario: horarioPermitido })
          : t(`${NS}.REGRAS_QUALQUER_HORA`)
      }}
    </p>
  </fieldset>
</template>
