<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';

// #1428 (parte 3, piloto) — o que o "Mudar conversando" fez, pedido por pedido (visual do protótipo
// ResultadoDaMudanca): ✓ aplicado ou ⚠ "Não consegui aplicar" com o pedido; o que o dono não pediu
// fica numa linha neutra à parte e não conta no "Mudei X de Y". Sem conferência, o cartão é neutro
// (nunca ✓). Desfazer até a próxima mudança no agente; depois, o caminho é Versões. A pergunta do
// Construtor segue na conversa, logo abaixo. O texto de cada linha vem pronto do servidor.
const props = defineProps({
  resultado: { type: Object, required: true },
  nome: { type: String, required: true },
  desfazendo: { type: Boolean, default: false },
  // '' | 'mudou' (409: o agente mudou depois) | 'falhou'
  erro: { type: String, default: '' },
});

const emit = defineEmits(['desfazer']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CONFERIDO';

const pedidos = computed(() =>
  (props.resultado.itens || []).filter(item => item.estado !== 'sem_pedido')
);
const semPedido = computed(() =>
  (props.resultado.itens || [])
    .filter(item => item.estado === 'sem_pedido')
    .map(item => item.texto)
);
const aplicados = computed(
  () => pedidos.value.filter(item => item.estado === 'aplicado').length
);
const tudoAplicado = computed(
  () => pedidos.value.length > 0 && aplicados.value === pedidos.value.length
);
const conferido = computed(() => props.resultado.conferido === true);
const titulo = computed(() => {
  if (!conferido.value) return t(`${NS}.NAO_CONFERIDO`, { nome: props.nome });
  if (!tudoAplicado.value) {
    return t(`${NS}.TITULO_PARTE`, {
      ok: aplicados.value,
      total: pedidos.value.length,
      nome: props.nome,
    });
  }
  const chave = props.resultado.faltou_fora
    ? `${NS}.TITULO_MUDEI`
    : `${NS}.TITULO_TUDO`;
  return t(chave, { n: aplicados.value, nome: props.nome }, aplicados.value);
});
const cor = computed(() => {
  if (!conferido.value) return 'bg-n-slate-2 ring-n-slate-6';
  return tudoAplicado.value && !props.resultado.faltou_fora
    ? 'bg-n-teal-2 ring-n-teal-6'
    : 'bg-n-amber-2 ring-n-amber-6';
});
const podeDesfazer = computed(
  () => props.resultado.pode_desfazer === true && props.erro !== 'mudou'
);
</script>

<template>
  <p
    v-if="resultado.desfeito || resultado.desfeito_sozinho"
    data-desfeito
    class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-slate-2 ring-1 ring-inset ring-n-slate-6 text-n-slate-12"
  >
    <span
      class="i-lucide-undo-2 size-5 shrink-0 text-n-slate-11"
      aria-hidden="true"
    />
    {{
      resultado.desfeito
        ? t(`${NS}.DESFEITO`, { nome })
        : t(`${NS}.DESFEITO_SOZINHO`, { nome })
    }}
  </p>
  <section
    v-else
    data-conferido
    :data-tom="conferido ? 'conferido' : 'neutro'"
    :aria-label="titulo"
    class="flex flex-col gap-4 p-4 rounded-2xl ring-1 ring-inset"
    :class="cor"
  >
    <p class="m-0 text-base font-semibold text-n-slate-12">{{ titulo }}</p>
    <ul v-if="pedidos.length" class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="(item, indice) in pedidos"
        :key="indice"
        :data-item="item.estado"
        class="flex items-start gap-3 text-sm text-n-slate-12"
      >
        <template v-if="!conferido">
          <span
            class="i-lucide-dot size-5 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          <span>{{ item.texto }}</span>
        </template>
        <template v-else-if="item.estado === 'aplicado'">
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
          <span>{{ t(`${NS}.DUVIDA`, { pedido: item.texto }) }}</span>
        </template>
      </li>
    </ul>
    <p
      v-if="semPedido.length"
      data-sem-pedido
      class="flex items-start gap-3 m-0 text-sm text-n-slate-12"
    >
      <span
        class="i-lucide-info size-5 shrink-0 text-n-slate-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.SEM_PEDIDO`, { lista: semPedido.join('; ') }) }}
    </p>
    <p
      v-if="resultado.faltou_fora"
      data-faltou-fora
      class="flex items-start gap-3 m-0 text-sm text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ t(`${NS}.FALTOU_FORA`) }}
    </p>
    <slot />
    <AgenteBotao
      v-if="podeDesfazer"
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
    <p
      v-if="erro"
      data-erro-desfazer
      role="alert"
      class="m-0 text-sm text-n-slate-12"
    >
      {{
        erro === 'mudou'
          ? t(`${NS}.MUDOU_DEPOIS`, { nome })
          : t(`${NS}.ERRO`, { nome })
      }}
    </p>
  </section>
</template>
