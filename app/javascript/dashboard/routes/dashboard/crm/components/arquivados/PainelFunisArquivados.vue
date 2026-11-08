<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmArquivadosAPI from 'dashboard/api/crmArquivados';
import PainelLateral from './PainelLateral.vue';
import { useFormato } from '../card/useFormato';
import { motivoDoErro } from './motivoDoErro';

// Funis arquivados (#2095): restaurar traz o funil de volta ao quadro, com os cards guardados nele, e as caixas
// ligadas a ele voltam a criar card. Quem não gerencia funis só lê. O slot `acoes` deixa outra parte acrescentar
// um botão (ex.: Excluir de vez).
const props = defineProps({
  show: { type: Boolean, default: false },
  podeGerenciar: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'restaurado']);

const { t, locale } = useI18n();
const formato = useFormato({ t, locale });
const funis = ref([]);
const carregando = ref(false);
const erroCarga = ref('');
const ocupados = ref({});
const erros = ref({});

const carregar = async () => {
  carregando.value = true;
  erroCarga.value = '';
  try {
    const { data } = await CrmArquivadosAPI.funisArquivados();
    funis.value = data.payload || [];
  } catch (error) {
    erroCarga.value = t('CRM_ARQUIVADOS.FUNIS.ERRO_CARREGAR', {
      motivo: motivoDoErro(t, error),
    });
  } finally {
    carregando.value = false;
  }
};

watch(
  () => props.show,
  aberto => {
    if (!aberto) return;
    erros.value = {};
    carregar();
  },
  { immediate: true }
);

const cardsDe = funil => {
  const total = Number(funil.cards_count || 0);
  const abertos = Number(funil.open_cards_count || 0);
  if (!total) return t('CRM_ARQUIVADOS.FUNIS.SEM_CARDS');
  const guardados = t(
    'CRM_ARQUIVADOS.FUNIS.GUARDADOS',
    { count: total },
    total
  );
  if (!abertos) return guardados;
  return `${guardados}, ${t('CRM_ARQUIVADOS.FUNIS.ABERTOS', { count: abertos }, abertos)}`;
};
const caixasDe = funil =>
  (funil.inboxes || [])
    .filter(caixa => caixa.auto_create_card !== false)
    .map(caixa => caixa.name)
    .filter(Boolean);

const restaurar = async funil => {
  ocupados.value = { ...ocupados.value, [funil.id]: true };
  erros.value = { ...erros.value, [funil.id]: '' };
  try {
    const { data } = await CrmArquivadosAPI.restaurarFunil(funil.id);
    funis.value = funis.value.filter(item => item.id !== funil.id);
    emit('restaurado', {
      funil: data.payload || data,
      abertos: Number(funil.open_cards_count || 0),
      caixas: caixasDe(funil),
    });
  } catch (error) {
    erros.value = {
      ...erros.value,
      [funil.id]: t('CRM_ARQUIVADOS.FUNIS.ERRO_RESTAURAR', {
        motivo: motivoDoErro(t, error),
      }),
    };
  } finally {
    ocupados.value = { ...ocupados.value, [funil.id]: false };
  }
};

const vazio = computed(
  () => !carregando.value && !erroCarga.value && !funis.value.length
);
defineExpose({ recarregar: carregar });
</script>

<template>
  <PainelLateral
    :show="show"
    :titulo="t('CRM_ARQUIVADOS.FUNIS.TITULO')"
    :subtitulo="t('CRM_ARQUIVADOS.FUNIS.SUB')"
    data-painel-funis-arquivados
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4" aria-live="polite">
      <p
        v-if="!podeGerenciar && funis.length"
        data-so-leitura
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
      >
        <span class="i-lucide-lock mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ t('CRM_ARQUIVADOS.FUNIS.SEM_PERMISSAO') }}
      </p>
      <div v-if="carregando" aria-busy="true" class="flex flex-col gap-3">
        <span class="sr-only">{{ t('CRM_ARQUIVADOS.CARREGANDO') }}</span>
        <div
          v-for="n in 2"
          :key="n"
          class="h-16 animate-pulse rounded-xl bg-n-alpha-2"
        />
      </div>
      <div
        v-else-if="erroCarga"
        role="alert"
        class="flex flex-col items-start gap-2 rounded-xl bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
      >
        <p class="mb-0">{{ erroCarga }}</p>
        <Button
          :label="t('CRM_ARQUIVADOS.TENTAR_DE_NOVO')"
          slate
          faded
          class="!min-h-11"
          @click="carregar"
        />
      </div>
      <div
        v-else-if="vazio"
        data-funis-vazio
        class="flex flex-col items-center gap-3 py-8 text-center"
      >
        <span
          class="i-lucide-archive size-8 text-n-slate-9"
          aria-hidden="true"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CRM_ARQUIVADOS.FUNIS.VAZIO') }}
        </p>
        <Button
          :label="t('CRM_ARQUIVADOS.FECHAR')"
          slate
          faded
          class="!min-h-11"
          @click="emit('close')"
        />
      </div>
      <ul v-else class="m-0 list-none p-0">
        <li
          v-for="funil in funis"
          :key="funil.id"
          data-funil-arquivado
          :data-funil-id="funil.id"
          class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-n-weak py-3 last:border-b-0"
        >
          <div class="flex min-w-0 flex-1 basis-56 items-start gap-3">
            <span
              aria-hidden="true"
              class="grid size-10 shrink-0 place-items-center rounded-xl bg-n-alpha-2 text-n-slate-11"
            >
              <span class="i-lucide-kanban size-5" />
            </span>
            <span class="min-w-0">
              <span class="block font-medium text-n-slate-12">{{
                funil.name
              }}</span>
              <span class="block text-sm text-n-slate-11">{{
                cardsDe(funil)
              }}</span>
              <span
                v-if="caixasDe(funil).length"
                data-funil-caixas
                class="block text-xs text-n-slate-11"
              >
                {{
                  t('CRM_ARQUIVADOS.FUNIS.CAIXAS_VOLTAM', {
                    caixas: formato.juntar(caixasDe(funil)),
                  })
                }}
              </span>
            </span>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button
              v-if="podeGerenciar"
              data-funil-restaurar
              :label="t('CRM_ARQUIVADOS.RESTAURAR')"
              icon="i-lucide-rotate-ccw"
              slate
              faded
              class="!min-h-11"
              :is-loading="Boolean(ocupados[funil.id])"
              :disabled="Boolean(ocupados[funil.id])"
              @click="restaurar(funil)"
            />
            <slot name="acoes" :funil="funil" />
          </div>
          <p
            v-if="erros[funil.id]"
            role="alert"
            class="mb-0 basis-full rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
          >
            {{ erros[funil.id] }}
          </p>
        </li>
      </ul>
    </div>
  </PainelLateral>
</template>
