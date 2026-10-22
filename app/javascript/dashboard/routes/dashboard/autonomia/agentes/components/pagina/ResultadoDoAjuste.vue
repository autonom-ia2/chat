<script setup>
import { computed, ref, useId } from 'vue';
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

const { t, locale } = useI18n();
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
// #1428 (entrega B) — as perguntas de prova chegam depois do cartão: "Testando…", depois ✓ ou ⚠ com a lista
// (pergunta do cliente e resposta do agente; nunca trecho da instrução). Indisponível, ou nenhuma pergunta
// que toque a mudança (`total` 0: o placar só conta essas): linha neutra, sem ✓.
const prova = computed(() => props.resultado.prova || null);
// Revisão do t6d: o ✓ só sai quando cada pedido teve uma pergunta que o testou (`completa`).
const provaCompleta = computed(() => prova.value?.completa !== false);
// Prova incompleta (texto aprovado pelo Rodrigo, 22/10): os pedidos que não deu para ver, juntos como o idioma
// junta uma lista ("a, b e c"); sem a lista (prova antiga), o texto geral.
// Sem o Intl.ListFormat (navegador antigo ou idioma que ele não conhece), vírgulas.
const pedidosSemTeste = computed(() => {
  const lista = prova.value?.pedidos_sem_teste || [];
  if (!lista.length) return '';
  try {
    return new Intl.ListFormat(locale.value.replace('_', '-'), {
      type: 'conjunction',
    }).format(lista);
  } catch {
    return lista.join(', ');
  }
});
const textoIncompleta = computed(() =>
  pedidosSemTeste.value
    ? t(`${NS}.PROVA_INCOMPLETA`, { pedidos: pedidosSemTeste.value })
    : t(`${NS}.PROVA_SEM_TESTE`)
);
const contraditas = computed(() => prova.value?.mudancas?.contraditas || 0);
const provaOk = computed(
  () =>
    prova.value?.ok === prova.value?.total &&
    provaCompleta.value &&
    !contraditas.value
);
// Ajuste aprovado pelo Rodrigo (22/10): o título conta mudanças (pedidos), não perguntas, e diz quantas a resposta
// do teste contrariou. Prova antiga, sem `mudancas`, mantém o placar de perguntas.
const contagemDaProva = mudancas => {
  if (mudancas.testadas === mudancas.total) {
    return t(`${NS}.PROVA_TESTEI_TODAS`, { n: mudancas.total }, mudancas.total);
  }
  return t(`${NS}.PROVA_TESTEI_PARTE`, {
    x: mudancas.testadas,
    n: mudancas.total,
  });
};
const contradicao = mudancas => {
  if (!contraditas.value) return '';
  if (mudancas.total === 1) return t(`${NS}.PROVA_CONTRARIO_UMA`);
  return t(
    `${NS}.PROVA_CONTRARIO`,
    { k: contraditas.value },
    contraditas.value
  );
};
const tituloDaProva = computed(() => {
  const mudancas = prova.value?.mudancas;
  if (!mudancas) {
    return t(
      `${NS}.PROVA`,
      { ok: prova.value.ok, total: prova.value.total },
      prova.value.total
    );
  }
  return [contagemDaProva(mudancas), contradicao(mudancas)]
    .filter(Boolean)
    .join(' ');
});
// O que a prova viu de cada linha aplicada: o ✓ de "mudei" não vem junto de "não deu para ver". O ícone nunca é a
// única informação: o leitor de tela ouve o rótulo. A prova antiga fica como antes.
const ROTULO_DA_PROVA = {
  ok: 'APLICADO_TESTADO',
  nao: 'APLICADO_CONTRARIO',
  sem_teste: 'APLICADO_SEM_TESTE',
};
const ICONE_DA_PROVA = {
  nao: 'i-lucide-triangle-alert text-n-amber-11',
  sem_teste: 'i-lucide-circle-dashed text-n-slate-10',
};
const rotuloAplicado = item =>
  t(`${NS}.${ROTULO_DA_PROVA[item.prova] || 'APLICADO'}`);
const verProva = ref(false);
const listaDaProva = useId();

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
        :data-visto="item.prova"
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
            class="size-5 shrink-0"
            :class="
              ICONE_DA_PROVA[item.prova] ||
              'i-lucide-circle-check text-n-teal-11'
            "
            aria-hidden="true"
          />
          <span class="relative">
            <span class="sr-only">{{ rotuloAplicado(item) }}</span>
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
    <div
      v-if="prova"
      data-prova
      :data-status="prova.status"
      class="flex flex-col gap-2 pt-3 border-t border-n-slate-6"
      aria-live="polite"
    >
      <p
        v-if="prova.status === 'pendente'"
        class="flex items-center gap-3 m-0 text-sm text-n-slate-11"
      >
        <span
          class="i-lucide-loader-circle size-5 shrink-0 motion-safe:animate-spin"
          aria-hidden="true"
        />
        {{ t(`${NS}.PROVA_TESTANDO`, { n: prova.total }, prova.total) }}
      </p>
      <p
        v-else-if="prova.status !== 'pronta'"
        class="flex items-center gap-3 m-0 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info size-5 shrink-0" aria-hidden="true" />
        {{ t(`${NS}.PROVA_INDISPONIVEL`) }}
      </p>
      <template v-else>
        <p
          v-if="!prova.total"
          data-sem-teste
          class="flex items-center gap-3 m-0 text-sm text-n-slate-11"
        >
          <span class="i-lucide-info size-5 shrink-0" aria-hidden="true" />
          {{ t(`${NS}.PROVA_SEM_TESTE`) }}
        </p>
        <p
          v-else
          data-titulo-prova
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
          {{ tituloDaProva }}
        </p>
        <p
          v-if="prova.total && !provaCompleta"
          data-prova-incompleta
          class="m-0 text-sm text-n-slate-12 ps-8"
        >
          {{ textoIncompleta }}
        </p>
        <button
          data-ver-prova
          type="button"
          class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          :aria-expanded="verProva ? 'true' : 'false'"
          :aria-controls="listaDaProva"
          @click="verProva = !verProva"
        >
          <span
            class="i-lucide-chevron-right size-4 transition-transform rtl:rotate-180"
            :class="{ 'rotate-90 rtl:rotate-90': verProva }"
            aria-hidden="true"
          />
          {{ verProva ? t(`${NS}.ESCONDER_PROVA`) : t(`${NS}.VER_PROVA`) }}
        </button>
        <ul
          v-if="verProva"
          :id="listaDaProva"
          class="flex flex-col gap-3 p-0 m-0 list-none"
        >
          <li
            v-for="(item, indice) in prova.perguntas"
            :key="indice"
            :data-pergunta-ok="String(item.ok ?? 'sem_teste')"
            class="flex items-start gap-3 p-3 text-sm rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
          >
            <span
              v-if="typeof item.ok === 'boolean'"
              class="size-5 shrink-0"
              :class="
                item.ok
                  ? 'i-lucide-circle-check text-n-teal-11'
                  : 'i-lucide-triangle-alert text-n-amber-11'
              "
              aria-hidden="true"
            />
            <span v-else class="size-5 shrink-0" aria-hidden="true" />
            <span class="flex flex-col gap-1">
              <span class="text-n-slate-11">
                {{ t(`${NS}.CLIENTE`) }} {{ item.pergunta }}
              </span>
              <span class="text-n-slate-12">
                <b class="font-semibold">{{ t(`${NS}.AGENTE`, { nome }) }}</b>
                {{ item.resposta || t(`${NS}.PROVA_EQUIPE`) }}
              </span>
            </span>
          </li>
        </ul>
      </template>
    </div>
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
