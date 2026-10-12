<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import api from '../api/modelosWhatsapp';
import { ORDEM_DAS_SITUACOES } from '../constants';
import {
  usePodeCriarModelo,
  usePodeUsarEmCampanha,
} from '../helpers/usePodeCriarModelo';
import { rotuloDoCampo } from '../helpers/campos';
import ModeloLinha from '../components/ModeloLinha.vue';
import FranquiaDoMes from '../components/FranquiaDoMes.vue';

// Modelos de mensagem do WhatsApp (jornada 1): a lista com a situação de cada
// um em palavras simples, a busca e o filtro por número. Sem número oficial ou
// sem modelos: uma frase e um botão.
const { t } = useI18n();
const router = useRouter();
const podeCriar = usePodeCriarModelo();
const podeUsar = usePodeUsarEmCampanha();

const estado = ref('carregando');
const numeros = ref([]);
const modelos = ref([]);
const busca = ref('');
const numeroEscolhido = ref('todos');

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const [listaDeNumeros, listaDeModelos] = await Promise.all([
      api.listarNumeros(),
      api.listarModelos({ atualizar: true }),
    ]);
    numeros.value = listaDeNumeros;
    modelos.value = listaDeModelos;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(carregar);

const nomeDoNumero = computed(() =>
  Object.fromEntries(numeros.value.map(item => [item.id, item.nome]))
);

// Com mais de uma conta do WhatsApp, cada modelo diz de qual conta é: cada conta
// tem a sua análise e a sua situação.
const nomeDaConta = computed(() =>
  Object.fromEntries(
    numeros.value.map(item => [item.conta.id, item.conta.nome])
  )
);
const variasContas = computed(() => Object.keys(nomeDaConta.value).length > 1);

const opcoesDeNumero = computed(() => [
  { value: 'todos', label: t('MODELOS_WHATSAPP.LISTA.TODOS_OS_NUMEROS') },
  ...numeros.value.map(item => ({ value: item.id, label: item.nome })),
]);

const textoDoModelo = modelo =>
  modelo.conteudo.texto
    .map(pedaco =>
      pedaco.t === 'campo' ? rotuloDoCampo(t, pedaco.v) : pedaco.v
    )
    .join('');

const visiveis = computed(() => {
  const termo = busca.value.trim().toLocaleLowerCase();
  return modelos.value
    .filter(
      modelo =>
        numeroEscolhido.value === 'todos' ||
        modelo.numeros.includes(numeroEscolhido.value)
    )
    .filter(
      modelo =>
        !termo ||
        `${modelo.nome} ${textoDoModelo(modelo)}`
          .toLocaleLowerCase()
          .includes(termo)
    )
    .sort(
      (a, b) =>
        ORDEM_DAS_SITUACOES.indexOf(a.situacao) -
        ORDEM_DAS_SITUACOES.indexOf(b.situacao)
    );
});

const filtrando = computed(
  () => Boolean(busca.value.trim()) || numeroEscolhido.value !== 'todos'
);

const limparFiltros = () => {
  busca.value = '';
  numeroEscolhido.value = 'todos';
};

const ir = (name, params = {}) => router.push({ name, params });
const conectarHref = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-8 px-5 pt-8 pb-24 mx-auto max-w-6xl md:px-8 md:py-10"
      >
        <div
          v-if="estado === 'carregando'"
          aria-busy="true"
          class="flex flex-col gap-4"
        >
          <span class="sr-only">{{ $t('MODELOS_WHATSAPP.CARREGANDO') }}</span>
          <div class="h-24 rounded-2xl bg-n-alpha-2 animate-pulse" />
          <div
            v-for="indice in 3"
            :key="indice"
            class="h-28 rounded-2xl bg-n-alpha-2 animate-pulse"
          />
        </div>

        <div
          v-else-if="estado === 'erro'"
          role="alert"
          class="flex flex-col items-start gap-4 p-8 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('MODELOS_WHATSAPP.ERRO') }}
          </p>
          <Button
            :label="$t('MODELOS_WHATSAPP.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="faded"
            class="min-h-11"
            @click="carregar"
          />
        </div>

        <section
          v-else-if="!numeros.length || !modelos.length"
          data-vazio
          class="relative overflow-hidden rounded-3xl bg-woot-800 px-6 py-12 text-white md:px-12 md:py-16"
        >
          <span
            aria-hidden="true"
            class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
          />
          <div class="relative flex flex-col items-start max-w-2xl gap-6">
            <span
              class="grid place-items-center size-14 rounded-2xl bg-white/10"
            >
              <span
                class="i-lucide-message-square-text size-7"
                aria-hidden="true"
              />
            </span>
            <h1
              class="m-0 text-3xl font-bold leading-tight tracking-tight text-white md:text-[2.5rem]"
            >
              {{
                numeros.length
                  ? $t('MODELOS_WHATSAPP.VAZIO.TITULO')
                  : $t('MODELOS_WHATSAPP.SEM_NUMERO.TITULO')
              }}
            </h1>
            <template v-if="podeCriar">
              <Button
                v-if="numeros.length"
                data-criar
                :label="$t('MODELOS_WHATSAPP.ACOES.CRIAR')"
                icon="i-lucide-plus"
                size="lg"
                class="!min-h-12 !rounded-xl"
                @click="ir('modelos_whatsapp_novo')"
              />
              <a
                v-else
                data-conectar
                :href="conectarHref"
                class="inline-flex items-center gap-2 px-5 text-base font-semibold text-white min-h-12 rounded-xl bg-n-brand hover:brightness-110"
              >
                <span class="i-lucide-plug size-5" aria-hidden="true" />
                {{ $t('MODELOS_WHATSAPP.SEM_NUMERO.CONECTAR') }}
              </a>
            </template>
            <p v-else class="mb-0 text-base text-white/75">
              {{ $t('MODELOS_WHATSAPP.SO_VER') }}
            </p>
          </div>
        </section>

        <template v-else>
          <header class="flex flex-wrap items-end justify-between gap-5">
            <div class="min-w-0">
              <h1
                class="m-0 text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
              >
                {{ $t('MODELOS_WHATSAPP.LISTA.TITULO') }}
              </h1>
              <p class="mb-0 mt-2 text-base md:text-lg text-n-slate-11">
                {{ $t('MODELOS_WHATSAPP.LISTA.SUBTITULO') }}
              </p>
            </div>
            <Button
              v-if="podeCriar"
              data-criar
              :label="$t('MODELOS_WHATSAPP.ACOES.CRIAR')"
              icon="i-lucide-plus"
              size="lg"
              class="!min-h-12 !rounded-xl"
              @click="ir('modelos_whatsapp_novo')"
            />
          </header>

          <p
            v-if="!podeCriar"
            data-so-ver
            class="flex items-center gap-3 px-4 py-3 mb-0 text-[0.9375rem] rounded-xl bg-n-slate-2 text-n-slate-11"
          >
            <span class="i-lucide-eye size-5 shrink-0" aria-hidden="true" />
            {{ $t('MODELOS_WHATSAPP.SO_VER') }}
          </p>

          <!-- #1382: o "Atualizar" falhou numa conta; a lista é a última guardada. -->
          <p
            v-for="falha in modelos.naoAtualizou || []"
            :key="falha.conta"
            data-nao-atualizou
            role="status"
            class="flex items-start gap-3 px-4 py-3 mb-0 text-[0.9375rem] rounded-xl bg-n-amber-2 text-n-slate-12"
          >
            <span
              class="i-lucide-triangle-alert size-5 mt-0.5 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            {{
              falha.motivo === 'permission_denied'
                ? $t('MODELOS_WHATSAPP.LISTA.NAO_ATUALIZOU_PERMISSAO', {
                    conta: falha.conta,
                  })
                : $t('MODELOS_WHATSAPP.LISTA.NAO_ATUALIZOU', {
                    conta: falha.conta,
                  })
            }}
          </p>
          <p
            v-if="modelos.parcial"
            data-lista-parcial
            role="status"
            class="flex items-center gap-3 px-4 py-3 mb-0 text-[0.9375rem] rounded-xl bg-n-amber-2 text-n-slate-12"
          >
            <span
              class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            {{ $t('MODELOS_WHATSAPP.LISTA.PARCIAL') }}
          </p>

          <div class="flex flex-wrap items-center gap-3">
            <label class="relative flex-1 min-w-[min(100%,16rem)]">
              <span class="sr-only">{{
                $t('MODELOS_WHATSAPP.LISTA.BUSCAR')
              }}</span>
              <span
                class="absolute -translate-y-1/2 i-lucide-search size-5 start-3.5 top-1/2 text-n-slate-10"
                aria-hidden="true"
              />
              <input
                v-model="busca"
                data-busca
                type="search"
                :placeholder="$t('MODELOS_WHATSAPP.LISTA.BUSCAR')"
                class="w-full !mb-0 !h-12 !ps-11 !rounded-xl !text-base !bg-n-solid-1 !border-0 outline outline-1 outline-n-weak focus:outline-2 focus:outline-n-brand text-n-slate-12"
              />
            </label>
            <ChoiceSelect
              v-model="numeroEscolhido"
              data-filtro-numero
              :options="opcoesDeNumero"
              :aria-label="$t('MODELOS_WHATSAPP.LISTA.FILTRO_NUMERO')"
            />
          </div>

          <ul
            v-if="visiveis.length"
            class="flex flex-col gap-3.5 p-0 m-0 list-none"
          >
            <ModeloLinha
              v-for="modelo in visiveis"
              :key="modelo.id"
              :modelo="modelo"
              :nomes-dos-numeros="
                modelo.numeros.map(id => nomeDoNumero[id]).filter(Boolean)
              "
              :nome-da-conta="
                variasContas ? nomeDaConta[modelo.conta] || '' : ''
              "
              :pode-criar="podeCriar"
              :pode-usar="podeUsar"
              @abrir="ir('modelos_whatsapp_modelo', { id: modelo.id })"
              @corrigir="ir('modelos_whatsapp_alterar', { id: modelo.id })"
              @usar="ir('modelos_whatsapp_usar', { id: modelo.id })"
            />
          </ul>
          <div
            v-else-if="filtrando"
            data-sem-resultado
            class="flex flex-col items-center gap-4 p-10 text-center rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
          >
            <p class="mb-0 text-base text-n-slate-11">
              {{ $t('MODELOS_WHATSAPP.LISTA.SEM_RESULTADO') }}
            </p>
            <Button
              :label="$t('MODELOS_WHATSAPP.LISTA.LIMPAR')"
              color="slate"
              variant="faded"
              class="min-h-11"
              @click="limparFiltros"
            />
          </div>
          <FranquiaDoMes />
        </template>
      </div>
    </main>
  </section>
</template>
