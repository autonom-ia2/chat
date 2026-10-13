<script setup>
import { computed, h } from 'vue';
import { useI18n } from 'vue-i18n';

// #1301 (protótipo F07-ok) — o teste deu certo: um bloco só com o estado e "O que o agente recebe".
// O /test devolve o texto que o agente lê: já mapeado e, se passar de 8.000, cortado com o aviso
// (#1425); JSON inteiro vira
// linhas indentadas (a linha que quebra continua no próprio recuo), cortado ou texto vai como veio.
// Cresce dentro da gaveta, sem segunda rolagem. Linhas montadas por funções (h): o espaço da
// formatação do template não entra no texto.
const props = defineProps({
  resposta: { type: Object, required: true },
  mapeada: { type: Boolean, default: false },
});

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.TESTE';
const { t } = useI18n();

// Recuo por nível do JSON (2 espaços cada); acima do último, fica no último.
const RECUOS = [
  'ps-0',
  'ps-[2ch]',
  'ps-[4ch]',
  'ps-[6ch]',
  'ps-[8ch]',
  'ps-[10ch]',
  'ps-[12ch]',
  'ps-[14ch]',
  'ps-[16ch]',
];

const Linhas = ({ linhas: lista }) =>
  lista.map(linha =>
    h('span', { class: ['block break-words', linha.recuo] }, linha.texto)
  );
Linhas.props = ['linhas'];

const TextoCru = ({ texto }) =>
  h(
    'p',
    {
      'data-resposta-texto': '',
      class:
        'm-0 font-mono text-xs whitespace-pre-wrap break-words text-n-slate-12 [overflow-wrap:anywhere]',
    },
    texto
  );
TextoCru.props = ['texto'];

const linhas = computed(() =>
  (props.resposta.json || '').split('\n').map(linha => {
    const texto = linha.trimStart();
    const nivel = (linha.length - texto.length) / 2;
    return { texto, recuo: RECUOS[Math.min(nivel, RECUOS.length - 1)] };
  })
);
</script>

<template>
  <section
    data-deu-certo
    class="flex flex-col overflow-hidden rounded-2xl ring-1 ring-inset ring-n-teal-6"
  >
    <div class="flex items-center gap-2 px-4 py-3 bg-n-teal-2">
      <span
        aria-hidden="true"
        class="i-lucide-circle-check size-5 shrink-0 text-n-teal-11"
      />
      <p class="m-0 text-sm text-n-slate-12">
        <b class="font-semibold">{{ t(`${NS}.DEU_CERTO`) }}</b>
        {{ t(`${NS}.DEU_CERTO_TEXTO`) }}
      </p>
    </div>
    <div class="flex flex-col gap-2 px-4 py-3 bg-n-solid-1">
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.RECEBE`) }}
      </h3>
      <p v-if="mapeada" class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.MAPEADA`) }}
      </p>
      <div
        v-if="resposta.json"
        data-resposta-json
        class="font-mono text-xs leading-relaxed text-n-slate-12"
      >
        <Linhas :linhas="linhas" />
      </div>
      <TextoCru v-else :texto="resposta.texto" />
      <p v-if="resposta.cortada" class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.CORTADA`) }}
      </p>
    </div>
  </section>
</template>
