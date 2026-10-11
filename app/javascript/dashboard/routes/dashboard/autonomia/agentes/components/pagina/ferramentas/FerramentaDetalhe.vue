<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import FerramentaInterruptor from './FerramentaInterruptor.vue';
import { hostDoEndereco, paraRascunho } from '../../../utils/ferramentas';

// #1301 (protótipo F09) — a ferramenta em frases, como a página do agente (T07): o interruptor é a
// primeira linha e cada parte tem "Alterar", que abre só aquele passo. "Últimas chamadas" (F14)
// exige backend (a ferramenta HTTP não grava as chamadas) e fica de fora.
const props = defineProps({
  ferramenta: { type: Object, required: true },
  nome: { type: String, required: true },
  salvo: { type: Boolean, default: false },
  rodape: { type: String, required: true },
});

const emit = defineEmits(['alternar', 'alterar', 'testar', 'excluir']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS';
const { t } = useI18n();

const rascunho = computed(() => paraRascunho(props.ferramenta));

const textoPreenche = computed(() => {
  const lista = rascunho.value.informacoes;
  if (!lista.length) return t(`${NS}.DETALHE.NENHUMA`);
  const itens = lista
    .map(i =>
      t(
        i.podeFaltar
          ? `${NS}.DETALHE.INFORMACAO_FALTA`
          : `${NS}.DETALHE.INFORMACAO`,
        { nome: i.nome, tipo: t(`${NS}.DETALHE.TIPOS.${i.tipo}`) }
      )
    )
    .join(', ');
  return t(
    `${NS}.DETALHE.INFORMACOES`,
    { n: lista.length, lista: itens },
    lista.length
  );
});

const textoComoEntra = computed(() => {
  const cabecalhos = rascunho.value.cabecalhos;
  if (!cabecalhos.length) return t(`${NS}.DETALHE.SEM_CHAVE`);
  const grupo = (chave, lista) =>
    lista.length
      ? t(
          `${NS}.DETALHE.${chave}`,
          { n: lista.length, lista: lista.map(c => c.chave).join(', ') },
          lista.length
        )
      : '';
  const [a, b] = [
    grupo(
      'SECRETAS',
      cabecalhos.filter(c => c.segredo)
    ),
    grupo(
      'CABECALHOS',
      cabecalhos.filter(c => !c.segredo)
    ),
  ].filter(Boolean);
  return b
    ? t(`${NS}.DETALHE.COM_DOIS`, { a, b })
    : t(`${NS}.DETALHE.COM_UM`, { a });
});

const linhas = computed(() => [
  {
    passo: 1,
    chave: 'O_QUE_FAZ',
    icone: 'i-lucide-message-square',
    texto: props.ferramenta.description || t(`${NS}.LISTA.SEM_QUANDO`),
  },
  {
    passo: 2,
    chave: 'PARA_ONDE',
    icone:
      props.ferramenta.http_method === 'POST'
        ? 'i-lucide-send'
        : 'i-lucide-search',
    texto: t(
      props.ferramenta.http_method === 'POST'
        ? `${NS}.DETALHE.ENVIA_PARA`
        : `${NS}.DETALHE.BUSCA_EM`,
      { host: hostDoEndereco(props.ferramenta.endpoint_url) }
    ),
    codigo: props.ferramenta.endpoint_url,
  },
  {
    passo: 3,
    chave: 'PREENCHE',
    icone: 'i-lucide-pencil',
    texto: textoPreenche.value,
  },
  {
    passo: 4,
    chave: 'COMO_ENTRA',
    icone: 'i-lucide-key-round',
    texto: textoComoEntra.value,
  },
]);

const titulo = chave => t(`${NS}.DETALHE.${chave}`);
</script>

<template>
  <div data-detalhe class="flex flex-col gap-4">
    <p
      v-if="salvo"
      data-salvo
      role="status"
      class="flex items-center gap-2 px-3 py-2 m-0 text-sm rounded-xl bg-n-teal-2 text-n-slate-12"
    >
      <span
        aria-hidden="true"
        class="i-lucide-circle-check size-4 shrink-0 text-n-teal-11"
      />
      {{
        ferramenta.enabled
          ? t(`${NS}.DETALHE.SALVO_LIGADA`)
          : t(`${NS}.DETALHE.SALVO_DESLIGADA`)
      }}
    </p>
    <section
      :aria-label="t(`${NS}.DETALHE.RESUMO`, { ferramenta: ferramenta.name })"
      class="flex flex-col divide-y shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak divide-n-weak"
    >
      <div data-linha="usar" class="flex items-start gap-3 p-4">
        <span
          aria-hidden="true"
          class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
        >
          <span class="i-lucide-power size-5 text-n-slate-11" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <h3 class="m-0 text-sm font-semibold text-n-slate-11">
            {{ t(`${NS}.DETALHE.USAR`) }}
          </h3>
          <p class="m-0 text-sm text-n-slate-12">
            {{
              ferramenta.enabled
                ? t(`${NS}.DETALHE.USA`, { nome })
                : t(`${NS}.DETALHE.DESLIGADA`)
            }}
          </p>
        </div>
        <FerramentaInterruptor
          :id="`ferramenta-interruptor-${ferramenta.id}`"
          :ligado="ferramenta.enabled"
          :rotulo="t(`${NS}.USAR`, { ferramenta: ferramenta.name })"
          :texto-ligado="t(`${NS}.LIGADA`)"
          :texto-desligado="t(`${NS}.DESLIGADA`)"
          @alternar="emit('alternar', ferramenta, $event)"
        />
      </div>
      <div
        v-for="linha in linhas"
        :key="linha.chave"
        :data-linha="linha.passo"
        class="flex items-start gap-3 p-4"
      >
        <span
          aria-hidden="true"
          class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
        >
          <span :class="linha.icone" class="size-5 text-n-slate-11" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <h3 class="m-0 text-sm font-semibold text-n-slate-11">
            {{ titulo(linha.chave) }}
          </h3>
          <p class="m-0 text-sm break-words text-n-slate-12">
            {{ linha.texto }}
          </p>
          <p
            v-if="linha.codigo"
            data-endereco
            class="px-2 py-1.5 m-0 font-mono text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 break-all"
          >
            {{ linha.codigo }}
          </p>
        </div>
        <AgenteBotao
          data-alterar
          variante="fantasma"
          class="shrink-0"
          :aria-label="
            t(`${NS}.DETALHE.ALTERAR_SR`, {
              parte: titulo(linha.chave).toLowerCase(),
            })
          "
          @click="emit('alterar', linha.passo)"
        >
          {{ t(`${NS}.DETALHE.ALTERAR`) }}
        </AgenteBotao>
      </div>
    </section>
    <p class="m-0">
      <button
        id="ferramenta-excluir"
        type="button"
        data-excluir
        class="inline-flex items-center gap-2 px-1 -mx-1 text-sm font-semibold underline rounded-lg min-h-11 text-n-ruby-11 underline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-ruby-11"
        @click="emit('excluir', ferramenta)"
      >
        <span aria-hidden="true" class="i-lucide-trash-2 size-4" />
        {{ t(`${NS}.DETALHE.EXCLUIR`) }}
      </button>
    </p>

    <Teleport defer :to="`#${rodape}`">
      <AgenteBotao
        data-testar
        tamanho="lg"
        icone="i-lucide-flask-conical"
        class="w-full sm:w-auto"
        @click="emit('testar')"
      >
        {{ t(`${NS}.DETALHE.TESTAR`) }}
      </AgenteBotao>
    </Teleport>
  </div>
</template>
