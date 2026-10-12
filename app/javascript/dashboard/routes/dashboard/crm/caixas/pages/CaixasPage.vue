<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmCaixasAPI from 'dashboard/api/crmCaixas';
import CaixaCartao from '../components/CaixaCartao.vue';

// #1149 — CRM → Caixas no CRM. Cada caixa conectada em frases: o que chega,
// quem cuida e o que o sistema faz sozinho. Alterar abre a caixa nas etapas.
const route = useRoute();
const router = useRouter();

const estado = ref('carregando');
const caixas = ref([]);
const funis = ref([]);

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const dados = await CrmCaixasAPI.listar();
    // Ligadas primeiro; dentro de cada grupo, pelo nome.
    caixas.value = [...dados.caixas].sort(
      (a, b) =>
        Number(b.crm_enabled) - Number(a.crm_enabled) ||
        a.inbox.name.localeCompare(b.inbox.name)
    );
    funis.value = dados.funis;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(carregar);

const ligadas = computed(() => caixas.value.filter(c => c.crm_enabled).length);
const salvaAgora = computed(() => Number(route.query.salva) || null);

const alterar = caixa =>
  router.push({
    name: 'crm_caixa',
    params: { ...route.params, inboxId: caixa.inbox.id },
  });

const conectarCaixa = () =>
  router.push({ name: 'settings_inbox_new', params: route.params });
</script>

<template>
  <section class="flex h-full w-full flex-col overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="mx-auto flex w-full max-w-6xl flex-col gap-8 px-4 pb-28 pt-8 md:px-8 md:py-10"
      >
        <header class="flex flex-col gap-2">
          <h1
            class="mb-0 text-3xl font-bold tracking-tight text-n-slate-12 md:text-4xl"
          >
            {{ $t('CRM_CAIXAS.LISTA.TITULO') }}
          </h1>
          <p class="mb-0 text-base text-n-slate-11 md:text-lg">
            {{ $t('CRM_CAIXAS.LISTA.SUBTITULO') }}
          </p>
        </header>

        <div
          v-if="estado === 'carregando'"
          aria-busy="true"
          class="grid gap-4 md:grid-cols-2"
        >
          <span class="sr-only">{{ $t('CRM_CAIXAS.LISTA.CARREGANDO') }}</span>
          <div
            v-for="indice in 4"
            :key="indice"
            class="h-72 animate-pulse rounded-2xl bg-n-alpha-2"
          />
        </div>

        <div
          v-else-if="estado === 'erro'"
          role="alert"
          class="flex flex-col items-start gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-8"
        >
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('CRM_CAIXAS.LISTA.ERRO') }}
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

        <div
          v-else-if="!caixas.length"
          data-vazio
          class="flex flex-col items-center gap-5 rounded-2xl border border-dashed border-n-weak bg-n-solid-1 px-6 py-14 text-center"
        >
          <span
            class="grid size-14 place-items-center rounded-2xl bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-inbox size-7" aria-hidden="true" />
          </span>
          <p class="mb-0 max-w-md text-lg text-n-slate-12">
            {{ $t('CRM_CAIXAS.LISTA.VAZIO') }}
          </p>
          <Button
            :label="$t('CRM_CAIXAS.LISTA.CONECTAR')"
            icon="i-lucide-plus"
            class="!min-h-11"
            @click="conectarCaixa"
          />
        </div>

        <template v-else>
          <div class="flex flex-wrap gap-3">
            <span
              class="inline-flex items-center gap-2.5 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-2.5 text-[0.9375rem] text-n-slate-12"
            >
              <span
                class="size-2.5 rounded-full bg-n-teal-9"
                aria-hidden="true"
              />
              {{ $t('CRM_CAIXAS.LISTA.LIGADAS', { n: ligadas }, ligadas) }}
            </span>
            <span
              v-if="caixas.length - ligadas"
              class="inline-flex items-center gap-2.5 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-2.5 text-[0.9375rem] text-n-slate-12"
            >
              <span
                class="size-2.5 rounded-full bg-n-slate-8"
                aria-hidden="true"
              />
              {{
                $t(
                  'CRM_CAIXAS.LISTA.FORA',
                  { n: caixas.length - ligadas },
                  caixas.length - ligadas
                )
              }}
            </span>
          </div>
          <div class="grid gap-4 md:grid-cols-2">
            <CaixaCartao
              v-for="caixa in caixas"
              :key="caixa.inbox.id"
              :caixa="caixa"
              :funis="funis"
              :salva-agora="salvaAgora === caixa.inbox.id"
              @alterar="alterar"
            />
          </div>
          <p class="mb-0 text-[0.9375rem] text-n-slate-11">
            {{ $t('CRM_CAIXAS.LISTA.ADMIN') }}
          </p>
        </template>
      </div>
    </main>
  </section>
</template>
