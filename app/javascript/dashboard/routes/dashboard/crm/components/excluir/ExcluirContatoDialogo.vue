<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import EscolhaRadio from 'dashboard/routes/dashboard/autonomia/agentes/components/EscolhaRadio.vue';
import CrmExcluirAPI from 'dashboard/api/crmExcluir';
import { dataDaReuniao } from '../../composables/useAvisoDeReuniao';
import { useFormato } from '../card/useFormato';
import CampoDeConfirmar from './CampoDeConfirmar.vue';
import {
  PALAVRA_DE_CONFIRMAR,
  avisoDeReunioes,
  confere,
  ehVenda,
  linhaDoCardDoContato,
  motivoDoExcluir,
  somaDasVendas,
} from './textosDoExcluir';

// Excluir um contato que tem cards no CRM (#2096, passo 11 do protótipo; decisões 1 e 10). Só o administrador, com a
// flag crm_arquivados. Lista os cards do contato e pergunta, sem nada marcado, se eles saem junto ("Sim, apagar") ou
// ficam sem dado pessoal ("Não, manter"). Nos dois casos a reunião futura é cancelada antes. Pede EXCLUIR digitado.
const props = defineProps({
  // { id, name }
  contato: { type: Object, default: null },
});
const emit = defineEmits(['excluido', 'close']);

const { t, locale } = useI18n();
const formato = useFormato({ t, locale });
const dialogo = ref(null);
const previa = ref(null);
const carregando = ref(false);
const erroPrevia = ref('');
const escolha = ref(null);
const digitado = ref('');
const ocupado = ref(false);
const erro = ref('');

const cards = computed(() => previa.value?.cards || []);
const total = computed(() => cards.value.length);
const nome = computed(() => props.contato?.name || '');
const linhas = computed(() =>
  cards.value.map(card => ({
    id: card.id,
    ...linhaDoCardDoContato(t, formato, card),
  }))
);

const opcoes = computed(() => [
  {
    valor: 'delete',
    titulo: t(
      'CRM_EXCLUIR.CONTATO.APAGAR',
      { count: total.value },
      total.value
    ),
    texto: t('CRM_EXCLUIR.CONTATO.APAGAR_TEXTO'),
  },
  {
    valor: 'keep',
    titulo: t('CRM_EXCLUIR.CONTATO.MANTER'),
    texto: t('CRM_EXCLUIR.CONTATO.MANTER_TEXTO'),
  },
]);
const pergunta = computed(() =>
  t('CRM_EXCLUIR.CONTATO.PERGUNTA', { count: total.value }, total.value)
);

const vendas = computed(() => cards.value.filter(ehVenda));
const avisoDaVenda = computed(() => {
  if (!escolha.value || !vendas.value.length) return '';
  const chave =
    escolha.value === 'delete'
      ? 'CRM_EXCLUIR.CONTATO.VENDA_SAI'
      : 'CRM_EXCLUIR.CONTATO.VENDA_FICA';
  const quantas = vendas.value.length;
  return t(
    chave,
    { count: quantas, valor: somaDasVendas(formato, vendas.value) },
    quantas
  );
});
// A reunião é cancelada nas duas escolhas: a pessoa sai do sistema (decisão 10).
const avisoDasReunioes = computed(() => {
  if (!escolha.value) return '';
  const reunioes = cards.value
    .filter(card => card.upcoming_meeting)
    .map(card => ({
      quando: dataDaReuniao(
        card.upcoming_meeting.starts_at,
        previa.value?.timezone,
        locale.value
      ),
      provider: card.upcoming_meeting.provider,
    }));
  return avisoDeReunioes(t, reunioes);
});

const pronto = computed(
  () =>
    !ocupado.value &&
    Boolean(previa.value) &&
    (!total.value || Boolean(escolha.value)) &&
    confere(digitado.value, PALAVRA_DE_CONFIRMAR, { ignorarMaiusculas: true })
);

const open = async () => {
  previa.value = null;
  erroPrevia.value = '';
  erro.value = '';
  escolha.value = null;
  digitado.value = '';
  ocupado.value = false;
  await nextTick();
  dialogo.value?.open();
  if (!props.contato?.id) return;
  carregando.value = true;
  try {
    const { data } = await CrmExcluirAPI.previaDoContato(props.contato.id);
    previa.value = data.payload || { cards: [] };
  } catch (error) {
    erroPrevia.value = t('CRM_EXCLUIR.ERROS.PREVIA', {
      motivo: motivoDoExcluir(t, error),
    });
  } finally {
    carregando.value = false;
  }
};
const close = () => dialogo.value?.close();

const excluir = async () => {
  if (!pronto.value) return;
  ocupado.value = true;
  erro.value = '';
  try {
    await CrmExcluirAPI.excluirContato(props.contato.id, {
      confirmation: PALAVRA_DE_CONFIRMAR,
      cards: total.value ? escolha.value : undefined,
    });
    emit('excluido', {
      nome: nome.value,
      cards: total.value,
      modo: total.value ? escolha.value : null,
    });
    close();
  } catch (error) {
    erro.value = t('CRM_EXCLUIR.ERROS.NADA_MUDOU', {
      motivo: motivoDoExcluir(t, error),
    });
  } finally {
    ocupado.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-excluir-contato
    type="alert"
    :title="t('CRM_EXCLUIR.CONTATO.TITULO', { nome })"
    :description="t('CRM_EXCLUIR.CONTATO.TEXTO')"
    width="lg"
    :close-on-outside-click="false"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-3" aria-live="polite">
      <div v-if="carregando" aria-busy="true" class="flex flex-col gap-2">
        <span class="sr-only">{{ t('CRM_EXCLUIR.CARREGANDO') }}</span>
        <div class="h-14 animate-pulse rounded-xl bg-n-alpha-2" />
        <div class="h-14 animate-pulse rounded-xl bg-n-alpha-2" />
      </div>
      <p
        v-else-if="erroPrevia"
        role="alert"
        class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{ erroPrevia }}
      </p>
      <template v-else-if="previa">
        <div v-if="total" data-excluir-contato-cards>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_EXCLUIR.CONTATO.OS_CARDS', { count: total }, total) }}
          </p>
          <ul
            class="m-0 flex max-h-48 list-none flex-col gap-1 overflow-y-auto p-0"
          >
            <li
              v-for="linha in linhas"
              :key="linha.id"
              class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5 rounded-lg bg-n-alpha-1 px-3 py-2 text-sm"
            >
              <span class="min-w-0 text-n-slate-12">{{ linha.onde }}</span>
              <span class="flex items-baseline gap-2 text-n-slate-11">
                <span v-if="linha.valor">{{ linha.valor }}</span>
                <span v-if="linha.situacao">{{ linha.situacao }}</span>
              </span>
            </li>
          </ul>
        </div>
        <template v-if="total">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ pergunta }}
          </p>
          <EscolhaRadio v-model="escolha" :rotulo="pergunta" :opcoes="opcoes" />
          <p
            v-if="avisoDaVenda"
            data-excluir-venda
            class="mb-0 flex items-start gap-2 rounded-xl px-3 py-2 text-sm"
            :class="
              escolha === 'delete'
                ? 'bg-n-amber-2 text-n-amber-11'
                : 'bg-n-blue-2 text-n-blue-11'
            "
          >
            <span
              class="mt-0.5 size-4 shrink-0"
              :class="
                escolha === 'delete'
                  ? 'i-lucide-triangle-alert'
                  : 'i-lucide-chart-column'
              "
              aria-hidden="true"
            />
            {{ avisoDaVenda }}
          </p>
          <p
            v-if="avisoDasReunioes"
            data-excluir-reuniao
            class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
          >
            <span
              class="i-lucide-calendar-x mt-0.5 size-4 shrink-0"
              aria-hidden="true"
            />
            {{ avisoDasReunioes }}
          </p>
        </template>
        <CampoDeConfirmar
          v-model="digitado"
          :rotulo="t('CRM_EXCLUIR.DIGITE_EXCLUIR')"
          :dica="PALAVRA_DE_CONFIRMAR"
          :desabilitado="ocupado"
        />
      </template>
      <p
        v-if="erro"
        role="alert"
        data-excluir-erro
        class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{ erro }}
      </p>
    </div>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          type="button"
          :label="t('CRM_EXCLUIR.CANCELAR')"
          slate
          faded
          class="!min-h-11"
          :disabled="ocupado"
          @click="close"
        />
        <Button
          type="button"
          data-excluir-confirmar
          :label="t('CRM_EXCLUIR.CONTATO.BOTAO')"
          icon="i-lucide-trash-2"
          ruby
          class="!min-h-11"
          :is-loading="ocupado"
          :disabled="!pronto"
          @click="excluir"
        />
      </div>
    </template>
  </Dialog>
</template>
