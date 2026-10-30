<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import EscolhaRadio from 'dashboard/routes/dashboard/autonomia/agentes/components/EscolhaRadio.vue';
import CrmExcluirAPI from 'dashboard/api/crmExcluir';
import { countsAsSale } from '../../helpers/cardOutcome';
import { dataDaReuniao } from '../../composables/useAvisoDeReuniao';
import { useFormato } from '../card/useFormato';
import CampoDeConfirmar from './CampoDeConfirmar.vue';
import {
  avisoDeReunioes,
  confere,
  motivoDoExcluir,
  somaDasVendas,
} from './textosDoExcluir';

// Excluir de vez um funil arquivado (#2096, passo 10 do protótipo; decisão 4). Só o administrador. Com cards, a
// escolha: mover para outro funil (já marcado; a etapa vale só para os abertos, os fechados e arquivados vão para a
// primeira) ou excluir os cards junto (a venda sai e a reunião é cancelada). Para confirmar, o nome do funil. Com
// cards, o servidor faz em segundo plano e avisa na auditoria se desistir.
const props = defineProps({
  // Os funis ativos, destino possível dos cards.
  ativos: { type: Array, default: () => [] },
  carregarEtapas: { type: Function, required: true },
});
const emit = defineEmits(['excluido', 'close']);

const { t, locale } = useI18n();
const formato = useFormato({ t, locale });
const dialogo = ref(null);
const funil = ref(null);
const previa = ref(null);
const carregando = ref(false);
const erroPrevia = ref('');
const destino = ref('move');
const funilDestino = ref(null);
const etapaDestino = ref(null);
const etapas = ref([]);
const digitado = ref('');
const ocupado = ref(false);
const erro = ref('');

const total = computed(() => Number(previa.value?.cards_count || 0));
const abertos = computed(() => Number(previa.value?.open_cards_count || 0));
const outros = computed(() =>
  Number(previa.value?.closed_or_archived_count || 0)
);
const vendas = computed(() =>
  (previa.value?.won_values || []).filter(item => Number(item.value_cents))
);
const valorDasVendas = computed(() => somaDasVendas(formato, vendas.value));
const destinoEscolhido = computed(() =>
  props.ativos.find(item => item.id === funilDestino.value)
);

const opcoesDosCards = computed(() => [
  {
    valor: 'move',
    titulo: t('CRM_EXCLUIR.FUNIL.MOVER'),
    texto: t('CRM_EXCLUIR.FUNIL.MOVER_TEXTO'),
    desabilitada: !props.ativos.length,
  },
  {
    valor: 'delete',
    titulo: t('CRM_EXCLUIR.FUNIL.JUNTO'),
    texto: t('CRM_EXCLUIR.FUNIL.JUNTO_TEXTO'),
  },
]);
const opcoesDosFunis = computed(() =>
  props.ativos.map(item => ({ value: item.id, label: item.name }))
);
const opcoesDasEtapas = computed(() =>
  etapas.value.map(item => ({ value: item.id, label: item.name }))
);
const rotuloDosCards = computed(() =>
  t('CRM_EXCLUIR.FUNIL.CARDS_ROTULO', {
    cards: t('CRM_EXCLUIR.FUNIL.N_CARDS', { count: total.value }, total.value),
    abertos: t(
      'CRM_EXCLUIR.FUNIL.N_ABERTOS',
      { count: abertos.value },
      abertos.value
    ),
    outros: t(
      'CRM_EXCLUIR.FUNIL.N_OUTROS',
      { count: outros.value },
      outros.value
    ),
  })
);

const avisoDosFechados = computed(() => {
  if (!outros.value || !destinoEscolhido.value) return '';
  return t(
    'CRM_EXCLUIR.FUNIL.FECHADOS_VAO',
    { count: outros.value, funil: destinoEscolhido.value.name },
    outros.value
  );
});
const avisoDasVendasNoDestino = computed(() => {
  if (!vendas.value.length || !destinoEscolhido.value) return '';
  const chave = countsAsSale(destinoEscolhido.value)
    ? 'CRM_EXCLUIR.FUNIL.VENDAS_SOBEM'
    : 'CRM_EXCLUIR.FUNIL.VENDAS_NAO_ENTRAM';
  return t(chave, {
    valor: valorDasVendas.value,
    funil: destinoEscolhido.value.name,
  });
});
const avisoDasVendasJunto = computed(() =>
  vendas.value.length
    ? t('CRM_EXCLUIR.FUNIL.VENDAS_JUNTO', { valor: valorDasVendas.value })
    : ''
);
const avisoDasReunioes = computed(() => {
  const lista = previa.value?.upcoming_meetings || [];
  const quantas = Number(previa.value?.upcoming_meetings_count || 0);
  if (!quantas) return '';
  // A lista vem com até 100; o total diz quantas são.
  const reunioes = Array.from({ length: quantas }, (_, indice) => {
    const item = lista[indice];
    return {
      quando: item
        ? dataDaReuniao(item.starts_at, previa.value?.timezone, locale.value)
        : '',
      provider: item?.provider,
    };
  });
  return avisoDeReunioes(t, reunioes);
});

const pronto = computed(() => {
  if (ocupado.value || !previa.value || !funil.value) return false;
  if (!confere(digitado.value, funil.value.name)) return false;
  if (!total.value || destino.value === 'delete') return true;
  return Boolean(funilDestino.value && (!abertos.value || etapaDestino.value));
});

const escolherFunilDestino = async id => {
  funilDestino.value = id;
  etapaDestino.value = null;
  etapas.value = [];
  if (!id) return;
  const lista = await props.carregarEtapas(id);
  if (funilDestino.value !== id) return;
  etapas.value = lista || [];
  etapaDestino.value = etapas.value[0]?.id ?? null;
};

const open = async alvo => {
  funil.value = alvo;
  previa.value = null;
  erroPrevia.value = '';
  erro.value = '';
  digitado.value = '';
  ocupado.value = false;
  destino.value = props.ativos.length ? 'move' : 'delete';
  await nextTick();
  dialogo.value?.open();
  carregando.value = true;
  try {
    const { data } = await CrmExcluirAPI.previaDoFunil(alvo.id);
    previa.value = data.payload || {};
    if (props.ativos.length) await escolherFunilDestino(props.ativos[0].id);
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
  const comCards = total.value > 0;
  try {
    const { data } = await CrmExcluirAPI.excluirFunil(funil.value.id, {
      confirmation: digitado.value.trim(),
      cards: comCards ? destino.value : undefined,
      targetStageId:
        comCards && destino.value === 'move' ? etapaDestino.value : undefined,
    });
    emit('excluido', {
      funil: funil.value,
      status: data.payload?.status,
      destino: comCards ? destino.value : null,
      funilDestino: destinoEscolhido.value || null,
      cards: total.value,
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
    data-excluir-funil
    type="alert"
    :title="t('CRM_EXCLUIR.FUNIL.TITULO', { funil: funil?.name || '' })"
    :description="t('CRM_EXCLUIR.FUNIL.TEXTO')"
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
        <template v-if="total">
          <p class="mb-0 text-sm font-medium text-n-slate-12">
            {{ rotuloDosCards }}
          </p>
          <EscolhaRadio
            v-model="destino"
            :rotulo="rotuloDosCards"
            :opcoes="opcoesDosCards"
          />
          <template v-if="destino === 'move'">
            <div
              data-excluir-funil-destino
              class="grid gap-3 rounded-xl bg-n-alpha-1 p-3 sm:grid-cols-2"
            >
              <label
                class="mb-0 flex flex-col gap-1 text-sm font-medium text-n-slate-12"
              >
                {{ t('CRM_EXCLUIR.FUNIL.FUNIL_DESTINO') }}
                <ChoiceSelect
                  :model-value="funilDestino"
                  :options="opcoesDosFunis"
                  :placeholder="t('CRM_EXCLUIR.ESCOLHA')"
                  @update:model-value="escolherFunilDestino"
                />
              </label>
              <label
                v-if="abertos"
                class="mb-0 flex flex-col gap-1 text-sm font-medium text-n-slate-12"
              >
                {{
                  t(
                    'CRM_EXCLUIR.FUNIL.ETAPA_DOS_ABERTOS',
                    { count: abertos },
                    abertos
                  )
                }}
                <ChoiceSelect
                  v-model="etapaDestino"
                  :options="opcoesDasEtapas"
                  :placeholder="t('CRM_EXCLUIR.ESCOLHA')"
                />
              </label>
            </div>
            <p
              v-if="avisoDosFechados"
              data-excluir-funil-fechados
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ avisoDosFechados }}
            </p>
            <p
              v-if="avisoDasVendasNoDestino"
              data-excluir-funil-vendas
              class="mb-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
            >
              <span
                class="i-lucide-chart-column mt-0.5 size-4 shrink-0"
                aria-hidden="true"
              />
              {{ avisoDasVendasNoDestino }}
            </p>
          </template>
          <template v-else>
            <p
              v-if="avisoDasVendasJunto"
              data-excluir-funil-vendas
              class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
            >
              <span
                class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0"
                aria-hidden="true"
              />
              {{ avisoDasVendasJunto }}
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
          <p v-if="total" class="mb-0 text-xs text-n-slate-11">
            {{ t('CRM_EXCLUIR.FUNIL.SEGUNDO_PLANO') }}
          </p>
        </template>
        <CampoDeConfirmar
          v-model="digitado"
          :rotulo="t('CRM_EXCLUIR.FUNIL.DIGITE_NOME', { funil: funil?.name })"
          :dica="funil?.name"
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
          :label="t('CRM_EXCLUIR.BOTAO')"
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
