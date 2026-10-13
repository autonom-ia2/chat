<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import RespostasRapidas from '../RespostasRapidas.vue';

// #1428 (protótipo da Fase 2) — o que o "Mudar conversando" fez, pedido por pedido: ✓ aplicado ou
// ⚠ "Não consegui aplicar" com a pergunta e as respostas rápidas. Embaixo, as perguntas de prova
// (pergunta do cliente e resposta do agente; nunca trecho da instrução) e o Desfazer. Nunca diz
// "Pronto" quando sobrou dúvida.
const props = defineProps({
  resultado: { type: Object, required: true },
  nome: { type: String, required: true },
  desfeito: { type: Boolean, default: false },
  desfazendo: { type: Boolean, default: false },
  pensando: { type: Boolean, default: false },
});

const emit = defineEmits(['responder', 'desfazer']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CONFERIDO';
const verProva = ref(false);

const itens = computed(() => props.resultado.itens || []);
const aplicados = computed(
  () => itens.value.filter(item => item.estado === 'aplicado').length
);
const tudo = computed(() => aplicados.value === itens.value.length);
const titulo = computed(() =>
  tudo.value
    ? t(
        `${NS}.TITULO_TUDO`,
        { n: aplicados.value, nome: props.nome },
        aplicados.value
      )
    : t(`${NS}.TITULO_PARTE`, {
        ok: aplicados.value,
        total: itens.value.length,
        nome: props.nome,
      })
);
const prova = computed(() => props.resultado.prova);
const provaOk = computed(() => prova.value?.ok === prova.value?.total);

const escolher = (item, texto) => {
  const opcao = item.opcoes.find(op => op.texto === texto);
  if (opcao) emit('responder', item, opcao);
};
</script>

<template>
  <p
    v-if="desfeito"
    data-desfeito
    class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-slate-2 ring-1 ring-inset ring-n-slate-6 text-n-slate-12"
  >
    <span
      class="i-lucide-undo-2 size-5 shrink-0 text-n-slate-11"
      aria-hidden="true"
    />
    {{ t(`${NS}.DESFEITO`, { nome }) }}
  </p>
  <section
    v-else
    data-conferido
    :aria-label="titulo"
    class="flex flex-col gap-4 p-4 rounded-2xl ring-1 ring-inset"
    :class="tudo ? 'bg-n-teal-2 ring-n-teal-6' : 'bg-n-amber-2 ring-n-amber-6'"
  >
    <p class="m-0 text-base font-semibold text-n-slate-12">{{ titulo }}</p>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="item in itens"
        :key="item.id"
        :data-item="item.estado"
        class="flex items-start gap-3 text-sm text-n-slate-12"
      >
        <template v-if="item.estado === 'aplicado'">
          <span
            class="i-lucide-circle-check size-5 shrink-0 text-n-teal-11"
            aria-hidden="true"
          />
          <span class="relative">
            <span class="sr-only">{{ t(`${NS}.APLICADO`) }}</span>
            {{ item.texto }}
          </span>
        </template>
        <template v-else>
          <span
            class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          <span class="flex flex-col gap-2 grow">
            <span>
              {{ t(`${NS}.DUVIDA`, { pedido: item.pedido }) }}
              <b class="font-semibold">{{ t(`${NS}.PERGUNTA`) }}</b>
            </span>
            <RespostasRapidas
              :opcoes="item.opcoes.map(opcao => opcao.texto)"
              :rotulo="t(`${NS}.PERGUNTA`)"
              :desabilitado="pensando"
              @escolher="escolher(item, $event)"
            />
          </span>
        </template>
      </li>
    </ul>
    <div
      v-if="prova"
      data-prova
      class="flex flex-col gap-2 pt-3 border-t border-n-slate-6"
    >
      <p
        class="flex items-center gap-3 m-0 text-sm font-semibold text-n-slate-12"
      >
        <span
          class="size-5 shrink-0"
          :class="
            provaOk
              ? 'i-lucide-circle-check text-n-teal-11'
              : 'i-lucide-triangle-alert text-n-amber-11'
          "
          aria-hidden="true"
        />
        {{ t(`${NS}.PROVA`, { ok: prova.ok, total: prova.total }) }}
      </p>
      <button
        data-ver-prova
        type="button"
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        :aria-expanded="verProva ? 'true' : 'false'"
        @click="verProva = !verProva"
      >
        <span
          class="i-lucide-chevron-right size-4 transition-transform rtl:rotate-180"
          :class="{ 'rotate-90 rtl:rotate-90': verProva }"
          aria-hidden="true"
        />
        {{ verProva ? t(`${NS}.ESCONDER_PROVA`) : t(`${NS}.VER_PROVA`) }}
      </button>
      <ul v-if="verProva" class="flex flex-col gap-3 p-0 m-0 list-none">
        <li
          v-for="(item, indice) in prova.perguntas"
          :key="indice"
          class="flex flex-col gap-1 p-3 text-sm rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
        >
          <span class="text-n-slate-11">
            {{ t(`${NS}.CLIENTE`) }} {{ item.pergunta }}
          </span>
          <span class="text-n-slate-12">
            <b class="font-semibold">{{ nome }}:</b> {{ item.resposta }}
          </span>
        </li>
      </ul>
    </div>
    <AgenteBotao
      data-desfazer
      variante="contorno"
      icone="i-lucide-undo-2"
      class="self-start"
      :carregando="desfazendo"
      :rotulo-carregando="t(`${NS}.DESFAZENDO`)"
      @click="emit('desfazer')"
    >
      {{ t(`${NS}.DESFAZER`) }}
    </AgenteBotao>
  </section>
</template>
