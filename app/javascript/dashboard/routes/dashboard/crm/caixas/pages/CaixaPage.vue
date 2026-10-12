<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmCaixasAPI from 'dashboard/api/crmCaixas';
import CaixaEtapas from '../components/CaixaEtapas.vue';
import CaixaIcone from '../components/CaixaIcone.vue';
import EtapaFunis from '../components/EtapaFunis.vue';
import EtapaPessoas from '../components/EtapaPessoas.vue';
import EtapaSozinho from '../components/EtapaSozinho.vue';
import EtapaConfira from '../components/EtapaConfira.vue';
import {
  faltaTriagem,
  funisDaCaixa,
  legadoPendente,
  paraFormulario,
  paraSalvar,
  primeiroNome,
  quemCuida,
} from '../helpers/caixa';

// #1149 — uma caixa em quatro etapas e um Salvar só (R16): o que chega, quem
// cuida do quê, o que o sistema faz sozinho e a conferência em frases.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const ULTIMA = 4;
const CHAVES = ['CHEGA', 'CUIDAM', 'SOZINHO', 'CONFIRA'];

const estado = ref('carregando');
const funis = ref([]);
const original = ref(null);
const form = ref(null);
const etapa = ref(1);
const alcancada = ref(1);
const salvando = ref(false);

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const dados = await CrmCaixasAPI.buscar(route.params.inboxId);
    funis.value = dados.funis;
    original.value = paraFormulario(dados.caixa);
    form.value = paraFormulario(dados.caixa);
    // Caixa já no CRM: todas as etapas abertas para ir direto ao que mudar.
    alcancada.value = dados.caixa.crm_enabled ? ULTIMA : 1;
    etapa.value = Number(route.query.etapa) || 1;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(carregar);

const funisMarcados = computed(() =>
  form.value ? funisDaCaixa(form.value, funis.value) : []
);
const umFunil = computed(() => funisMarcados.value.length === 1);
const semTriagem = computed(() =>
  form.value ? faltaTriagem(form.value) : false
);

// O modo precisa existir na quantidade de funis atual: "assim que chega" é só
// de caixa com um funil; sugerir e criar ao entender, de caixa com vários.
watch(umFunil, unico => {
  if (!form.value) return;
  const { modo } = form.value;
  if (unico && modo !== 'off') form.value.modo = 'chegou';
  if (!unico && modo === 'chegou') form.value.modo = 'auto';
  if (unico && !form.value.default_stage_id) {
    form.value.default_stage_id = funisMarcados.value[0].stages[0]?.id || null;
  }
});

// Funil novo na caixa entra para quem já cuidava de todos os funis dela (o
// "Todos os funis" de hoje, que também é o padrão de quem nunca foi mexido).
watch(
  () => form.value?.pipeline_ids,
  (atuais, anteriores) => {
    if (!atuais || !anteriores) return;
    const novos = atuais.filter(id => !anteriores.includes(id));
    if (!novos.length) return;
    form.value.people = form.value.people.map(pessoa => {
      const cuidavaDeTodos = anteriores.every(id =>
        pessoa.pipeline_ids.includes(id)
      );
      if (pessoa.administrator || !cuidavaDeTodos) return pessoa;
      return { ...pessoa, pipeline_ids: [...pessoa.pipeline_ids, ...novos] };
    });
  }
);

const exemplo = computed(() => {
  const funil = funisMarcados.value[0];
  if (!funil) return {};
  const etapaInicial =
    funil.stages.find(item => item.id === form.value.default_stage_id) ||
    funil.stages[0];
  const proxima = quemCuida(form.value, funil.id)[0];
  return {
    funil: funil.name,
    etapa: etapaInicial?.name || '',
    pessoa: proxima ? primeiroNome(proxima) : t('CRM_CAIXAS.SOZINHO.ALGUEM'),
  };
});

const bloqueio = computed(() => {
  if (etapa.value === 2 && semTriagem.value) {
    return t('CRM_CAIXAS.PESSOAS.FALTA_TRIAGEM_CURTO');
  }
  return '';
});

const ir = numero => {
  etapa.value = numero;
  alcancada.value = Math.max(alcancada.value, numero);
  document.querySelector('[data-caixa-editor]')?.scrollTo({ top: 0 });
};

const continuar = () => {
  if (bloqueio.value) return;
  // Sem funil nenhum, não há quem cuida nem o que fazer: vai direto conferir.
  ir(funisMarcados.value.length ? etapa.value + 1 : ULTIMA);
};

const voltarParaLista = (query = {}) =>
  router.push({ name: 'crm_caixas', params: route.params, query });

const manterLegado = () => {
  form.value.people = form.value.people.map(pessoa =>
    pessoa.administrator ? pessoa : { ...pessoa, only_own: true }
  );
  form.value.visibility_mode = 'all_inbox_cards';
};

const salvar = async () => {
  if (semTriagem.value) {
    ir(2);
    return;
  }
  salvando.value = true;
  try {
    await CrmCaixasAPI.salvar(route.params.inboxId, paraSalvar(form.value));
    useAlert(t('CRM_CAIXAS.EDITOR.SALVOU'));
    voltarParaLista({ salva: route.params.inboxId });
  } catch {
    useAlert(t('CRM_CAIXAS.EDITOR.FALHOU'));
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <section class="flex h-full w-full flex-col overflow-hidden bg-n-surface-1">
    <main data-caixa-editor class="flex-1 overflow-y-auto">
      <div
        class="mx-auto flex w-full max-w-4xl flex-col gap-6 px-4 pb-32 pt-6 md:px-8 md:pt-8"
      >
        <button
          type="button"
          class="-ms-2 inline-flex min-h-11 items-center gap-1.5 self-start rounded-lg px-2 text-[0.9375rem] font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="voltarParaLista()"
        >
          <span
            class="i-lucide-arrow-left size-4 rtl:rotate-180"
            aria-hidden="true"
          />
          {{ $t('CRM_CAIXAS.LISTA.TITULO') }}
        </button>

        <div
          v-if="estado === 'carregando'"
          aria-busy="true"
          class="flex flex-col gap-4"
        >
          <span class="sr-only">{{ $t('CRM_CAIXAS.LISTA.CARREGANDO') }}</span>
          <div class="h-12 w-72 animate-pulse rounded-xl bg-n-alpha-2" />
          <div class="h-80 animate-pulse rounded-2xl bg-n-alpha-2" />
        </div>

        <div
          v-else-if="estado === 'erro'"
          role="alert"
          class="flex flex-col items-start gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-8"
        >
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('CRM_CAIXAS.EDITOR.ERRO') }}
          </p>
          <Button
            :label="$t('CRM_CAIXAS.LISTA.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="!min-h-11"
            @click="carregar"
          />
        </div>

        <template v-else>
          <header class="flex items-center gap-3">
            <CaixaIcone :canal="form.inbox.channel_type" grande />
            <h1
              class="mb-0 min-w-0 truncate text-2xl font-bold tracking-tight text-n-slate-12 md:text-3xl"
            >
              {{ form.inbox.name }}
            </h1>
          </header>

          <CaixaEtapas :atual="etapa" :alcancada="alcancada" @ir="ir" />

          <div class="flex flex-col gap-1">
            <h2 class="mb-0 text-xl font-semibold text-n-slate-12 md:text-2xl">
              {{ $t(`CRM_CAIXAS.${CHAVES[etapa - 1]}.TITULO`) }}
            </h2>
            <p class="mb-0 text-base text-n-slate-11">
              {{ $t(`CRM_CAIXAS.${CHAVES[etapa - 1]}.SUBTITULO`) }}
            </p>
          </div>

          <EtapaFunis
            v-if="etapa === 1"
            v-model:pipeline-ids="form.pipeline_ids"
            v-model:etapa-inicial="form.default_stage_id"
            :funis="funis"
          />
          <EtapaPessoas
            v-else-if="etapa === 2"
            v-model:pessoas="form.people"
            :funis="funisMarcados"
            :todos-os-funis="funis"
            :falta-triagem="semTriagem"
            :legado="legadoPendente(form)"
            @manter-legado="manterLegado"
          />
          <EtapaSozinho
            v-else-if="etapa === 3"
            v-model:modo="form.modo"
            :um-funil="umFunil"
            v-bind="exemplo"
          />
          <EtapaConfira
            v-else
            :form="form"
            :original="original"
            :funis="funis"
          />
        </template>
      </div>
    </main>

    <footer
      v-if="estado === 'pronto'"
      class="border-t border-n-weak bg-n-solid-1 px-4 py-3 md:px-8"
    >
      <div
        class="mx-auto flex w-full max-w-4xl flex-wrap items-center justify-end gap-3"
      >
        <p
          v-if="bloqueio"
          role="status"
          class="mb-0 me-auto text-[0.9375rem] text-n-ruby-11"
        >
          {{ bloqueio }}
        </p>
        <Button
          v-if="etapa > 1"
          :label="$t('CRM_CAIXAS.EDITOR.VOLTAR')"
          slate
          ghost
          class="!min-h-11"
          @click="ir(etapa - 1)"
        />
        <Button
          v-if="etapa < 4"
          data-continuar
          :label="$t('CRM_CAIXAS.EDITOR.CONTINUAR')"
          icon="i-lucide-arrow-right"
          trailing-icon
          :disabled="Boolean(bloqueio)"
          class="!min-h-11"
          @click="continuar"
        />
        <Button
          v-else
          data-salvar
          :label="$t('CRM_CAIXAS.EDITOR.SALVAR')"
          icon="i-lucide-check"
          :is-loading="salvando"
          class="!min-h-11"
          @click="salvar"
        />
      </div>
    </footer>
  </section>
</template>
