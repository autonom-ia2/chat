<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmExcluirAPI from 'dashboard/api/crmExcluir';
import { dataDaReuniao } from '../../composables/useAvisoDeReuniao';
import { useFormato } from '../card/useFormato';
import CampoDeConfirmar from './CampoDeConfirmar.vue';
import {
  PALAVRA_DE_CONFIRMAR,
  avisoDeReunioes,
  confere,
  ehVenda,
  motivoDoExcluir,
  somaDasVendas,
} from './textosDoExcluir';

// Excluir de vez um ou vários cards arquivados (#2096, passos 2 e 7 do protótipo; decisões 3 e 10). Só o
// administrador chega aqui. Diz o que some e o que fica, a venda que sai dos Números, a reunião que é cancelada antes
// e o dado já enviado ao anúncio, e pede EXCLUIR digitado. `antes` (opcional): o que precisa acontecer primeiro, como
// arquivar o card aberto que veio da janela de arquivar; se ele falhar, nada muda.
const props = defineProps({
  // [{ id, title, contact?: { name }, status, desfecho?, value_cents, currency, pipeline?, campaigns? }]
  cards: { type: Array, required: true },
  antes: { type: Function, default: null },
  // Veio da janela de arquivar: o botão de sair é "Voltar", e volta para ela.
  voltar: { type: Boolean, default: false },
});
const emit = defineEmits(['excluidos', 'voltar', 'close']);

const { t, locale } = useI18n();
const formato = useFormato({ t, locale });
const dialogo = ref(null);
const digitado = ref('');
const ocupado = ref(false);
const erro = ref('');
const reunioes = ref([]);
const reunioesIncertas = ref(false);

const MOSTRAR = 6;
const um = computed(() => props.cards.length === 1);
const nomeDe = card => card.contact?.name || card.title || `#${card.id}`;
const vendas = computed(() => props.cards.filter(ehVenda));
const avisoDeVenda = computed(() => {
  if (!vendas.value.length) return '';
  const valor = somaDasVendas(formato, vendas.value);
  if (um.value) return t('CRM_EXCLUIR.CARD.VENDA', { valor });
  return t(
    'CRM_EXCLUIR.VARIOS.VENDAS',
    { count: vendas.value.length, valor },
    vendas.value.length
  );
});
const veioDeAnuncio = computed(() =>
  props.cards.some(card => card.campaigns?.length)
);
const avisoDasReunioes = computed(() => {
  if (reunioesIncertas.value) return t('CRM_EXCLUIR.REUNIAO.INCERTA');
  return avisoDeReunioes(t, reunioes.value);
});
const nomes = computed(() =>
  props.cards.slice(0, MOSTRAR).map(card => ({
    id: card.id,
    texto: ehVenda(card)
      ? `${nomeDe(card)} · ${formato.dinheiro(card.value_cents, card.currency)}`
      : nomeDe(card),
  }))
);
const mais = computed(() => Math.max(props.cards.length - MOSTRAR, 0));
const pronto = computed(
  () =>
    !ocupado.value &&
    confere(digitado.value, PALAVRA_DE_CONFIRMAR, { ignorarMaiusculas: true })
);
const titulo = computed(() =>
  um.value
    ? t('CRM_EXCLUIR.CARD.TITULO', { nome: nomeDe(props.cards[0]) })
    : t(
        'CRM_EXCLUIR.VARIOS.TITULO',
        { count: props.cards.length },
        props.cards.length
      )
);

// A próxima reunião de cada card (a mesma consulta do aviso ao arquivar, Parte A). Se a consulta falhar, a janela diz
// que a reunião que houver é cancelada, sem data, em vez de calar.
const buscarReunioes = async () => {
  reunioes.value = [];
  reunioesIncertas.value = false;
  try {
    const { data } = await CrmKanbanAPI.upcomingMeetings(
      props.cards.map(card => card.id)
    );
    const { timezone, cards = [] } = data.payload || {};
    reunioes.value = cards.map(item => ({
      quando: dataDaReuniao(item.starts_at, timezone, locale.value),
    }));
  } catch {
    reunioesIncertas.value = true;
  }
};

const open = async () => {
  digitado.value = '';
  erro.value = '';
  ocupado.value = false;
  await nextTick();
  dialogo.value?.open();
  buscarReunioes();
};
const close = () => dialogo.value?.close();

const excluir = async () => {
  if (!pronto.value) return;
  ocupado.value = true;
  erro.value = '';
  try {
    if (props.antes) await props.antes();
  } catch (error) {
    erro.value = t('CRM_EXCLUIR.ERROS.NADA_MUDOU', {
      motivo: motivoDoExcluir(t, error),
    });
    ocupado.value = false;
    return;
  }
  try {
    const ids = props.cards.map(card => card.id);
    const { data } = await CrmExcluirAPI.excluirCards(
      ids,
      PALAVRA_DE_CONFIRMAR
    );
    emit('excluidos', data.payload?.deleted_ids || ids);
    close();
  } catch (error) {
    const motivo = motivoDoExcluir(t, error);
    erro.value = props.antes
      ? t('CRM_EXCLUIR.ERROS.ARQUIVOU_SEM_EXCLUIR', { motivo })
      : t('CRM_EXCLUIR.ERROS.NADA_MUDOU', { motivo });
  } finally {
    ocupado.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-excluir-cards
    type="alert"
    :title="titulo"
    :description="
      um ? t('CRM_EXCLUIR.CARD.TEXTO') : t('CRM_EXCLUIR.VARIOS.TEXTO')
    "
    width="lg"
    :close-on-outside-click="false"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-3">
      <div v-if="um" data-excluir-some-fica class="grid gap-3 sm:grid-cols-2">
        <div>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_EXCLUIR.CARD.SOME') }}
          </p>
          <ul class="m-0 flex list-none flex-col gap-1 p-0">
            <li
              v-for="chave in ['ETAPAS', 'ANOTACOES', 'RETORNOS', 'IA']"
              :key="chave"
              class="flex items-start gap-2 text-sm text-n-slate-11"
            >
              <span
                class="i-lucide-minus mt-0.5 size-4 shrink-0 text-n-ruby-11"
                aria-hidden="true"
              />
              {{ t(`CRM_EXCLUIR.CARD.SOME_${chave}`) }}
            </li>
          </ul>
        </div>
        <div>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_EXCLUIR.CARD.FICA') }}
          </p>
          <ul class="m-0 flex list-none flex-col gap-1 p-0">
            <li
              v-for="chave in ['CONVERSA', 'CONTATO']"
              :key="chave"
              class="flex items-start gap-2 text-sm text-n-slate-11"
            >
              <span
                class="i-lucide-check mt-0.5 size-4 shrink-0 text-n-teal-11"
                aria-hidden="true"
              />
              {{ t(`CRM_EXCLUIR.CARD.FICA_${chave}`) }}
            </li>
          </ul>
        </div>
      </div>
      <ul
        v-else
        data-excluir-lista
        class="m-0 flex list-none flex-col gap-1 p-0"
      >
        <li
          v-for="item in nomes"
          :key="item.id"
          class="flex items-start gap-2 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-minus mt-0.5 size-4 shrink-0 text-n-ruby-11"
            aria-hidden="true"
          />
          {{ item.texto }}
        </li>
        <li v-if="mais" class="text-sm text-n-slate-11">
          {{ t('CRM_EXCLUIR.VARIOS.E_MAIS', { count: mais }, mais) }}
        </li>
      </ul>
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
      <p
        v-if="avisoDeVenda"
        data-excluir-venda
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
      >
        <span
          class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ avisoDeVenda }}
      </p>
      <p
        v-if="veioDeAnuncio"
        data-excluir-anuncio
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('CRM_EXCLUIR.ANUNCIO', { count: cards.length }, cards.length) }}
      </p>
      <CampoDeConfirmar
        v-model="digitado"
        :rotulo="t('CRM_EXCLUIR.DIGITE_EXCLUIR')"
        :dica="PALAVRA_DE_CONFIRMAR"
        :desabilitado="ocupado"
      />
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
          :label="voltar ? t('CRM_EXCLUIR.VOLTAR') : t('CRM_EXCLUIR.CANCELAR')"
          slate
          faded
          class="!min-h-11"
          :disabled="ocupado"
          @click="voltar ? emit('voltar') : close()"
        />
        <Button
          type="button"
          data-excluir-confirmar
          :label="
            um
              ? t('CRM_EXCLUIR.BOTAO')
              : t('CRM_EXCLUIR.BOTAO_N', { count: cards.length })
          "
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
