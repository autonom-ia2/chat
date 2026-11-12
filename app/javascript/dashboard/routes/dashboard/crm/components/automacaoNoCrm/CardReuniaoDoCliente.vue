<script setup>
import { ref, watch } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import CardCartao from '../card/CardCartao.vue';
import { useFonteDasAutomacoes } from './useAutomacaoNoCrm';
import { diaEHora } from './datas';

// #2710 — a reunião do cliente que já comprou, dentro do card ganho: "Maria
// marcou para 15/11 às 10h pelo link do e-mail.", com "Ver" (a Agenda do card).
// Sem reunião (ou card que não é ganho), nada aparece.
const props = defineProps({
  card: { type: Object, required: true },
});

const emit = defineEmits(['abrir']);

const { t, locale } = useI18n();
const fonte = useFonteDasAutomacoes();
const reuniao = ref(null);

watch(
  () => [props.card?.id, props.card?.status],
  async () => {
    reuniao.value = null;
    try {
      reuniao.value = await fonte.reuniaoDoCard(props.card);
    } catch {
      // Sem a reunião, o card segue como antes: a parte só some.
      reuniao.value = null;
    }
  },
  { immediate: true }
);
</script>

<template>
  <!-- `contents`: sem reunião, a parte some sem deixar espaço na coluna do resumo. -->
  <div class="contents">
    <CardCartao
      v-if="reuniao"
      parte="reuniao-do-cliente"
      icone="i-lucide-calendar-check"
      tom="bg-n-teal-3 text-n-teal-11"
      :titulo="t('AUTOMACAO_NO_CRM.CLIENTE.REUNIAO_TITULO')"
      acao="ver"
      @abrir="emit('abrir', 'agenda')"
    >
      <I18nT
        keypath="AUTOMACAO_NO_CRM.CLIENTE.REUNIAO_FRASE"
        tag="p"
        scope="global"
        class="mb-0"
        data-reuniao-frase
      >
        <template #nome>
          <strong class="font-semibold">{{ reuniao.nome }}</strong>
        </template>
        <template #quando>
          <strong class="font-semibold">
            {{ diaEHora(reuniao.inicio, { t, locale: locale }) }}
          </strong>
        </template>
      </I18nT>
    </CardCartao>
  </div>
</template>
