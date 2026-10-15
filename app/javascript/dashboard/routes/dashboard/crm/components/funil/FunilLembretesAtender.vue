<script setup>
import { computed } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import FunilInterruptor from './FunilInterruptor.vue';
import FunilTempoNaFrase from './FunilTempoNaFrase.vue';
import {
  CHAVE_DO_LEMBRETE,
  TEMPOS_DO_LEMBRETE,
  chaveDoTempo,
  lembretesDoModelo,
  tempoDoLembrete,
} from './lembretesAtender';

// #1498 — os lembretes de um funil de Atender, cada um numa frase com
// liga/desliga. #1589 — andamento e "deu certo?" têm o tempo escolhido dentro
// da própria frase (poucos botões); o pagamento segue com dias fixos.
// Saem no horário de atendimento do funil e a mensagem é escrita olhando a
// conversa de cada cliente.
const props = defineProps({
  modelo: { type: String, default: '' },
  sucesso: { type: String, default: '' },
});
const ligados = defineModel({ type: Object, required: true });

const { t } = useI18n();
const L = 'CRM_FUNIL.ATENDER.LEMBRETES';
const ICONES = {
  progress: 'i-lucide-message-circle-more',
  resolved_check: 'i-lucide-circle-check',
  payment: 'i-lucide-receipt',
};
const lembretes = computed(() =>
  lembretesDoModelo(props.modelo).map(chave => ({
    chave,
    icone: ICONES[chave],
    base: `${L}.${CHAVE_DO_LEMBRETE[chave]}`,
    titulo: t(`${L}.${CHAVE_DO_LEMBRETE[chave]}.TITULO`),
    tempos: TEMPOS_DO_LEMBRETE[chave],
  }))
);
const mudar = (chave, valor) => {
  ligados.value = { ...ligados.value, [chave]: valor };
};
const tempo = chave => tempoDoLembrete(ligados.value, chave);
const mudarTempo = (chave, horas) => mudar(chaveDoTempo(chave), horas);
</script>

<template>
  <section class="flex flex-col gap-3" data-lembretes-atender>
    <div
      v-for="item in lembretes"
      :key="item.chave"
      :data-lembrete="item.chave"
      class="flex flex-col gap-2 rounded-2xl border bg-n-solid-1 p-5"
      :class="ligados[item.chave] ? 'border-n-blue-7' : 'border-n-weak'"
    >
      <!-- Título e liga/desliga na mesma linha: a frase com os botões de tempo
      fica com a largura toda (no celular, os quatro cabem numa linha). Os
      botões não podem ficar dentro do label: cada clique ligaria e desligaria
      o lembrete. -->
      <span class="flex items-center gap-3">
        <span
          class="grid size-10 shrink-0 place-items-center rounded-xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="size-5" :class="item.icone" />
        </span>
        <span class="min-w-0 flex-1 text-sm font-medium text-n-slate-11">
          {{ item.titulo }}
        </span>
        <label class="shrink-0 cursor-pointer">
          <FunilInterruptor
            :model-value="Boolean(ligados[item.chave])"
            :rotulo="item.titulo"
            @update:model-value="mudar(item.chave, $event)"
          />
        </label>
      </span>
      <I18nT
        v-if="item.tempos"
        :keypath="`${item.base}.FRASE_TEMPO`"
        tag="p"
        class="mb-0 text-base font-semibold leading-relaxed text-n-slate-12 transition-opacity"
        :class="{ 'opacity-60': !ligados[item.chave] }"
        scope="global"
      >
        <template #tempo>
          <FunilTempoNaFrase
            :model-value="tempo(item.chave)"
            :opcoes="item.tempos"
            :rotulo="t(`${item.base}.TEMPO_ROTULO`, { sucesso })"
            @update:model-value="mudarTempo(item.chave, $event)"
          />
        </template>
        <template #sucesso>{{ sucesso }}</template>
      </I18nT>
      <p
        v-else
        class="mb-0 text-base font-semibold leading-relaxed text-n-slate-12"
      >
        {{ t(`${item.base}.FRASE`, { sucesso }) }}
      </p>
    </div>
  </section>
</template>
