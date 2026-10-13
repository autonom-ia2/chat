<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import PassagemHeroi from './PassagemHeroi.vue';
import PassagemFunilCartao from './PassagemFunilCartao.vue';
import { situacaoDoFunil } from './passagem';
import { usePassagemVolta } from './usePassagemVolta';

// #1385 — a lista de funis da passagem, na mesma família da tela de um funil: herói escuro, um cartão-frase por funil
// com o estado em palavras e "Abrir". A seta e o X voltam para o mesmo lugar (usePassagemVolta).
const { t } = useI18n();
const router = useRouter();
const { daLista } = usePassagemVolta();
const L = 'CRM_KANBAN.PASSAGEM.LISTA';

const carregando = ref(true);
const falhou = ref(false);
const funis = ref([]);
// A situação de cada funil sai do ai_settings, que traz as etapas. Sem resposta para um funil, o cartão diz que não
// deu para ver, em vez de um estado errado.
const situacoes = ref({});

const situacoesDe = async lista => {
  const respostas = await Promise.allSettled(
    lista.map(funil => CrmKanbanAPI.getAiSettings(funil.id))
  );
  return Object.fromEntries(
    respostas.flatMap((resposta, indice) => {
      const ajustes =
        resposta.status === 'fulfilled' ? resposta.value.data?.payload : null;
      return ajustes ? [[lista[indice].id, situacaoDoFunil(ajustes)]] : [];
    })
  );
};

// Só a última carga vale: dois toques em "Tentar de novo" não deixam a resposta velha por cima da nova.
let cargaAtual = 0;
const carregar = async () => {
  cargaAtual += 1;
  const esta = cargaAtual;
  carregando.value = true;
  falhou.value = false;
  try {
    const resposta = await CrmKanbanAPI.getPipelines();
    const lista = resposta.data?.payload || [];
    const novas = await situacoesDe(lista);
    if (esta !== cargaAtual) return;
    funis.value = lista;
    situacoes.value = novas;
  } catch {
    if (esta === cargaAtual) falhou.value = true;
  } finally {
    if (esta === cargaAtual) carregando.value = false;
  }
};

const vazio = computed(
  () => !carregando.value && !falhou.value && !funis.value.length
);

const sair = () => router.push(daLista.value.destino);
const abrir = funil =>
  router.push({
    name: 'crm_handoff_settings_edit',
    params: { pipelineId: funil.id },
  });

onMounted(carregar);
</script>

<template>
  <section
    data-passagem-lista
    class="flex h-full w-full flex-col overflow-hidden bg-n-solid-1 font-inter"
  >
    <PassagemHeroi
      :voltar="daLista.rotulo"
      :rotulo="t(`${L}.ROTULO`)"
      :titulo="t(`${L}.TITULO`)"
      :texto="t(`${L}.TEXTO`)"
      @voltar="sair"
      @fechar="sair"
    />

    <div class="min-h-0 flex-1 overflow-y-auto">
      <div class="flex max-w-3xl flex-col gap-3 px-5 py-7 max-md:pb-24 sm:px-8">
        <div v-if="carregando" aria-busy="true" class="flex flex-col gap-3">
          <span class="sr-only">{{ t(`${L}.CARREGANDO`) }}</span>
          <div
            v-for="n in 3"
            :key="n"
            class="h-[5.5rem] animate-pulse rounded-2xl bg-n-alpha-2"
          />
        </div>

        <div
          v-else-if="falhou"
          role="alert"
          class="flex flex-wrap items-center gap-3 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-[0.9375rem] text-n-ruby-11"
        >
          <span class="min-w-0 flex-1">{{ t(`${L}.ERRO`) }}</span>
          <Button
            :label="t('CRM_KANBAN.PASSAGEM.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="!min-h-11"
            @click="carregar"
          />
        </div>

        <div
          v-else-if="vazio"
          data-lista-vazia
          class="flex flex-col items-start gap-3 rounded-2xl border border-dashed border-n-weak p-5"
        >
          <span
            class="grid size-12 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
            aria-hidden="true"
          >
            <span class="i-lucide-kanban size-6" />
          </span>
          <h2 class="mb-0 text-base font-semibold text-n-slate-12">
            {{ t(`${L}.VAZIO_TITULO`) }}
          </h2>
          <p class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-11">
            {{ t(`${L}.VAZIO_TEXTO`) }}
          </p>
          <Button
            :label="t(`${L}.VAZIO_BOTAO`)"
            icon="i-lucide-plus"
            class="!min-h-11"
            @click="router.push({ name: 'crm_kanban_index' })"
          />
        </div>

        <template v-else>
          <h2 class="mb-0 text-sm font-medium text-n-slate-11">
            {{ t(`${L}.LISTA_ROTULO`) }}
          </h2>
          <ul class="m-0 flex list-none flex-col gap-3 p-0">
            <li v-for="funil in funis" :key="funil.id">
              <PassagemFunilCartao
                :funil="funil"
                :situacao="situacoes[funil.id]"
                @abrir="abrir"
              />
            </li>
          </ul>
        </template>
      </div>
    </div>
  </section>
</template>
