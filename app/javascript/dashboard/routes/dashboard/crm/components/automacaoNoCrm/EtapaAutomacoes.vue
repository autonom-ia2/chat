<script setup>
import { ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePodeMontarAutomacao } from 'dashboard/composables/usePodeMontarAutomacao';
import { useFonteDasAutomacoes } from './useAutomacaoNoCrm';

// #2414 F6.5 — "Automações desta etapa", na etapa aberta do funil: as regras
// da etapa e as automações novas numa lista só, cada uma como frase (Quando o
// card entra → o que faz), com "Alterar". A ação principal é "Nova automação
// para esta etapa", que abre o editor com o gatilho da etapa já escolhido. O
// aviso da F6.4 fica embaixo: arquivar em lote não conta como "saiu da etapa".
// "Alterar" de uma regra da etapa abre a tela dela (evento `antigas`).
const props = defineProps({
  etapaId: { type: [Number, String], required: true },
});

const emit = defineEmits(['antigas']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const fonte = useFonteDasAutomacoes();
const podeMontar = usePodeMontarAutomacao();
const tituloId = `etapa-automacoes-${useId()}`;

const E = 'AUTOMACAO_NO_CRM.ETAPA';
const itens = ref([]);
const estado = ref('carregando');

const carregar = async () => {
  estado.value = 'carregando';
  try {
    itens.value = await fonte.automacoesDaEtapa(props.etapaId);
    estado.value = 'pronto';
  } catch {
    itens.value = [];
    estado.value = 'erro';
  }
};
watch(() => props.etapaId, carregar, { immediate: true });

const conta = () => ({ accountId: route.params.accountId });

const alterar = item => {
  if (item.origem === 'etapa') {
    emit('antigas');
    return;
  }
  router.push({ ...item.rota, params: { ...conta(), ...item.rota.params } });
};

const nova = () =>
  router.push({
    name: 'automacoes_livre_nova',
    params: conta(),
    query: { gatilho: 'card.entrou_na_etapa', etapa: String(props.etapaId) },
  });
</script>

<template>
  <section
    data-etapa-automacoes
    class="flex flex-col gap-4"
    :aria-labelledby="tituloId"
  >
    <div class="flex flex-col gap-1">
      <h4 :id="tituloId" class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${E}.TITULO`) }}
      </h4>
      <p class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-11">
        {{ t(`${E}.AJUDA`) }}
      </p>
    </div>

    <p
      v-if="estado === 'carregando'"
      class="mb-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ t(`${E}.CARREGANDO`) }}
    </p>
    <div
      v-else-if="estado === 'erro'"
      data-etapa-automacoes-erro
      class="flex flex-wrap items-center gap-2"
    >
      <p class="mb-0 text-base text-n-slate-12">{{ t(`${E}.ERRO_LISTA`) }}</p>
      <Button
        :label="t(`${E}.TENTAR`)"
        slate
        faded
        class="!min-h-11"
        @click="carregar"
      />
    </div>
    <p
      v-else-if="!itens.length"
      data-etapa-automacoes-vazio
      class="mb-0 rounded-2xl border border-dashed border-n-weak px-4 py-6 text-center text-base text-n-slate-12"
    >
      {{ t(`${E}.VAZIO`) }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col gap-3 p-0">
      <li
        v-for="item in itens"
        :key="item.id"
        :data-automacao-da-etapa="item.id"
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:flex-row sm:items-center"
      >
        <div class="flex min-w-0 flex-1 flex-col gap-2">
          <span class="flex flex-wrap items-center gap-2">
            <span class="break-words text-base font-semibold text-n-slate-12">
              {{ item.nome }}
            </span>
            <span
              v-if="!item.ligada"
              data-desligada
              class="rounded-full bg-n-alpha-2 px-2.5 py-0.5 text-xs font-medium text-n-slate-11"
            >
              {{ t(`${E}.DESLIGADA`) }}
            </span>
          </span>
          <span
            data-frase
            class="flex flex-wrap items-center gap-2 text-[0.9375rem]"
          >
            <span
              class="rounded-lg bg-n-blue-2 px-2.5 py-1 font-medium text-n-blue-11"
            >
              {{
                t(
                  item.quando === 'sai'
                    ? `${E}.QUANDO_SAI`
                    : `${E}.QUANDO_ENTRA`
                )
              }}
            </span>
            <span
              class="i-lucide-arrow-right size-4 text-n-slate-9 rtl:rotate-180"
              aria-hidden="true"
            />
            <span
              class="break-words rounded-lg bg-n-teal-2 px-2.5 py-1 font-medium text-n-teal-11"
            >
              {{ item.faz }}
            </span>
          </span>
        </div>
        <Button
          v-if="podeMontar"
          data-alterar-automacao
          :label="t(`${E}.ALTERAR`)"
          :aria-label="t(`${E}.ALTERAR_ROTULO`, { nome: item.nome })"
          icon="i-lucide-pencil"
          slate
          faded
          class="!min-h-11 shrink-0 self-start sm:self-center"
          @click="alterar(item)"
        />
      </li>
    </ul>

    <Button
      v-if="estado === 'pronto' && podeMontar"
      data-nova-automacao
      :label="t(`${E}.NOVA`)"
      icon="i-lucide-plus"
      blue
      class="!min-h-11 w-full sm:w-auto sm:self-start"
      @click="nova"
    />
    <p v-else-if="!podeMontar" class="mb-0 text-sm text-n-amber-11">
      {{ t(`${E}.SO_VER`) }}
    </p>

    <p
      data-aviso-arquivar
      class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-2 px-4 py-3 text-sm text-n-amber-11"
    >
      <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ t(`${E}.AVISO_ARQUIVAR`) }}
    </p>
  </section>
</template>
