<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import MenuDeAcoes from './MenuDeAcoes.vue';
import { TONS, grupoDoCard } from './grupos';
import { situacaoDoCard } from './situacao';

// #2283 — uma linha da Lista nova. Tabela quando a lista é larga (`larga`),
// cartão abaixo. Três vagas fixas: ação principal · "Ver conversa" ·
// "Alterar"; vaga sem botão fica vazia, para os botões não andarem.
const props = defineProps({
  card: { type: Object, required: true },
  acao: { type: String, default: '' },
  cheio: { type: Boolean, default: false },
  larga: { type: Boolean, default: false },
  colunas: { type: Object, default: () => ({ linha: '', botoes: '' }) },
  quem: { type: String, default: 'todos' },
  meuId: { type: [Number, String], default: null },
  contexto: { type: Object, required: true },
  pessoas: { type: Array, default: () => [] },
  itensAlterar: { type: Array, default: () => [] },
  faixa: { type: Object, default: null },
  marcado: { type: Boolean, default: false },
  marcavel: { type: Boolean, default: false },
  // No cartão (celular), as caixas só aparecem com "Mais → Marcar vários".
  marcando: { type: Boolean, default: false },
});
const emit = defineEmits([
  'acao',
  'alterar',
  'passar',
  'desfazer',
  'marcar',
  'pausar',
  'seguir',
]);

const { t, locale } = useI18n();
const L = 'CRM_LISTA_ACAO';
const A = `${L}.ACOES`;

const nome = computed(() => props.card.contact?.name || props.card.title || '');
const sobre = computed(() => {
  const assunto = props.card.contact?.name ? props.card.title : '';
  const empresa = props.card.company?.name;
  return [assunto, empresa].filter(Boolean).join(' · ');
});
const oculta = computed(() => Boolean(props.card.conversation_hidden));
const temConversa = computed(
  () =>
    Boolean(props.card.conversation?.display_id) && props.acao !== 'responder'
);

const situacao = computed(() => situacaoDoCard(props.card, props.contexto));
const tom = computed(() => TONS[situacao.value.tom] || TONS.cinza);
// O número escolhe singular ou plural ("há 1 hora", "há 2 horas").
const textoDaSituacao = computed(() => {
  const { chave, valores = {} } = situacao.value;
  return typeof valores.n === 'number'
    ? t(`${L}.${chave}`, valores, valores.n)
    : t(`${L}.${chave}`, valores);
});

const etapa = computed(() => props.card.stage || null);
// Sem "quem cuida": conversa escondida (não sugere nome), "Ninguém cuidando"
// e "Só meus" (o título e a chave já dizem).
const mostraQuem = computed(
  () =>
    !oculta.value &&
    grupoDoCard(props.card) !== 'ninguem' &&
    props.quem !== 'meus'
);
const quemCuida = computed(() => {
  const quem = props.card.current_responsible;
  if (!quem) return t(`${L}.QUEM_CUIDA.NINGUEM`);
  if (quem.type !== 'bot' && String(quem.id) === String(props.meuId))
    return t(`${L}.QUEM_CUIDA.VOCE`);
  return t(`${L}.QUEM_CUIDA.PESSOA`, { nome: quem.name });
});
const robo = computed(() => props.card.current_responsible?.type === 'bot');
const valor = computed(() => {
  const centavos = Number(props.card.value_cents);
  if (!centavos) return '';
  try {
    return new Intl.NumberFormat(locale.value.replace('_', '-'), {
      style: 'currency',
      currency: props.card.currency || 'BRL',
    }).format(centavos / 100);
  } catch {
    return '';
  }
});

// Azul cheio só no primeiro cliente meu com ação; contorno no resto.
const BASE_SEM_TEXTO = 'w-full !h-11 !rounded-xl !px-3 whitespace-nowrap';
const BASE = `${BASE_SEM_TEXTO} !text-base !font-semibold`;
const NEUTRO_COR =
  '!text-n-slate-12 !outline-n-weak bg-n-solid-1 hover:enabled:!bg-n-alpha-2';
const CHEIO = `${BASE} !bg-n-blue-10 !text-white dark:!bg-n-blue-8 hover:enabled:!bg-n-blue-11 dark:hover:enabled:!bg-n-blue-7`;
const CONTORNO = `${BASE} !outline-2 -outline-offset-2 hover:enabled:!bg-n-alpha-2`;
const NEUTRO = `${BASE} ${NEUTRO_COR}`;
const CONVERSA = `${BASE_SEM_TEXTO} ${NEUTRO_COR} !gap-1.5 !px-2.5 !text-[15px] !font-medium`;
const estilo = computed(() => (props.cheio ? CHEIO : CONTORNO));
const variante = computed(() => (props.cheio ? 'solid' : 'outline'));
const ROTULO = {
  responder: 'RESPONDER',
  combinar: 'COMBINAR_RETORNO',
  ficar: 'FICAR',
};
const ariaDaAcao = tipo => {
  if (tipo === 'combinar')
    return t(`${A}.ROTULO_COMBINAR`, { nome: nome.value });
  return t(`${A}.ROTULO_ACAO`, {
    acao: t(`${A}.${ROTULO[tipo]}`),
    nome: nome.value,
  });
};
const passarPara = pessoaId => {
  const pessoa = props.pessoas.find(
    item => String(item.value) === String(pessoaId)
  );
  if (pessoa) emit('passar', pessoa);
};
</script>

<template>
  <div
    v-if="faixa"
    data-lista-acao-faixa
    class="flex min-h-[76px] items-center gap-3 border-b border-n-weak bg-n-teal-3 px-4 py-3 last:border-b-0"
    @mouseenter="emit('pausar')"
    @mouseleave="emit('seguir')"
    @focusin="emit('pausar')"
    @focusout="emit('seguir')"
  >
    <span class="i-lucide-check size-5 text-n-teal-11" aria-hidden="true" />
    <p class="mb-0 flex-1 text-base font-medium text-n-slate-12">
      {{ faixa.texto }}
    </p>
    <Button
      v-if="faixa.desfazivel"
      :label="t(`${L}.FAIXA.DESFAZER`)"
      slate
      outline
      data-lista-acao-desfazer
      class="!h-11 !rounded-xl !px-4 !text-base !font-semibold !text-n-slate-12 !outline-n-weak bg-n-solid-1 hover:enabled:!bg-n-alpha-2"
      @click="emit('desfazer')"
    />
  </div>
  <div
    v-else
    data-lista-acao-linha
    class="grid items-center gap-x-3 gap-y-2 border-b border-n-weak px-4 py-3 last:border-b-0 hover:bg-n-slate-2"
    :class="larga ? colunas.linha : 'grid-cols-1'"
  >
    <label
      v-if="marcavel && (larga || marcando)"
      class="grid size-11 cursor-pointer place-items-center"
      :class="{ '-mb-2 -ms-3': !larga }"
    >
      <Checkbox
        :model-value="marcado"
        @update:model-value="emit('marcar', $event)"
      />
      <span class="sr-only">{{ t(`${L}.LISTA.MARCAR`, { nome }) }}</span>
    </label>
    <span v-else-if="larga" aria-hidden="true" />

    <button
      type="button"
      data-lista-acao-abrir
      class="group flex min-h-11 min-w-0 flex-col justify-center rounded-lg text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
      :aria-label="t(`${L}.LISTA.VER_CLIENTE`, { nome, sobre })"
      @click="emit('acao', 'abrir')"
    >
      <span
        class="truncate text-base font-semibold text-n-slate-12 decoration-2 underline-offset-4 group-hover:underline group-focus-visible:underline"
      >
        {{ nome }}
      </span>
      <span
        v-if="sobre"
        class="text-sm text-n-slate-11"
        :class="larga ? 'line-clamp-1' : 'line-clamp-2'"
        :title="sobre"
      >
        {{ sobre }}
      </span>
    </button>

    <span class="flex min-w-0 flex-col items-start gap-1">
      <span
        data-lista-acao-situacao
        :data-tom="situacao.tom"
        class="inline-flex max-w-full items-center gap-1.5 rounded-lg px-2.5 py-1 text-sm font-medium text-n-slate-12"
        :class="tom.fundo"
      >
        <span
          :class="[situacao.icone, tom.icone]"
          class="size-4 shrink-0"
          aria-hidden="true"
        />
        <span>{{ textoDaSituacao }}</span>
      </span>
      <!-- Etapa, quem cuida e valor, cada um na sua linha: sem "·" solto, sem
           corte e sem duas coisas lidas como uma (revisão leiga do #2324). -->
      <span class="flex flex-col gap-0.5 text-sm text-n-slate-11">
        <span v-if="etapa || mostraQuem" class="flex flex-col items-start">
          <span
            v-if="etapa"
            class="inline-flex items-center gap-1.5 whitespace-nowrap"
          >
            <span
              v-if="etapa.color"
              class="size-2.5 rounded-full ring-1 ring-black/10 dark:ring-white/40"
              :style="{ backgroundColor: etapa.color }"
              aria-hidden="true"
            />{{ etapa.name }}
          </span>
          <span v-if="mostraQuem" class="whitespace-nowrap">
            <span
              v-if="robo"
              class="i-lucide-bot me-1 inline-block size-4 align-[-3px] text-n-slate-11"
              aria-hidden="true"
            />{{ quemCuida }}
          </span>
        </span>
        <span v-if="valor" class="tabular-nums text-n-slate-12">
          {{ valor }}
        </span>
      </span>
    </span>

    <span
      class="items-center gap-2"
      :class="
        larga ? ['grid', colunas.botoes] : 'flex w-full flex-wrap sm:max-w-lg'
      "
    >
      <span
        v-if="acao === 'feito'"
        class="grid basis-full gap-2"
        :class="larga ? 'grid-cols-1' : 'grid-cols-2'"
      >
        <Button
          :label="t(`${A}.FEITO`)"
          :variant="variante"
          :class="estilo"
          :aria-label="t(`${A}.ROTULO_FEITO`, { nome })"
          data-lista-acao-feito
          @click="emit('acao', 'feito')"
        />
        <Button
          :label="t(`${A}.COMBINAR_OUTRO`)"
          slate
          outline
          :class="NEUTRO"
          :aria-label="t(`${A}.ROTULO_COMBINAR_OUTRO`, { nome })"
          data-lista-acao-combinar-outro
          @click="emit('acao', 'combinar')"
        />
      </span>
      <span
        v-else-if="acao === 'passar'"
        class="flex"
        :class="temConversa ? 'basis-full' : 'flex-1'"
      >
        <ChoiceSelect
          model-value=""
          :options="pessoas"
          :placeholder="t(`${A}.PASSAR`)"
          :aria-label="t(`${A}.ROTULO_PASSAR`, { nome })"
          data-lista-acao-passar
          class="w-full [&>button>span]:!text-n-blue-11 [&>button]:!h-11 [&>button]:!justify-center [&>button]:!rounded-xl [&>button]:!bg-transparent [&>button]:!text-base [&>button]:!font-semibold [&>button]:!outline-2 [&>button]:!outline-n-brand hover:[&>button]:!bg-n-alpha-2"
          @update:model-value="passarPara"
        />
      </span>
      <span
        v-else-if="acao"
        class="flex"
        :class="temConversa ? 'basis-full' : 'flex-1'"
      >
        <Button
          :label="t(`${A}.${ROTULO[acao]}`)"
          :variant="variante"
          :class="estilo"
          :aria-label="ariaDaAcao(acao)"
          :data-lista-acao-principal="acao"
          @click="emit('acao', acao)"
        />
      </span>
      <span v-else-if="larga" aria-hidden="true" />

      <span v-if="temConversa" class="flex flex-1">
        <Button
          :label="t(`${A}.VER_CONVERSA`)"
          icon="i-lucide-message-square"
          slate
          outline
          :class="CONVERSA"
          class="[&>span:first-child]:text-n-blue-11"
          :aria-label="t(`${A}.ROTULO_VER_CONVERSA`, { nome })"
          data-lista-acao-ver-conversa
          @click="emit('acao', 'ver-conversa')"
        />
      </span>
      <span v-else-if="larga" aria-hidden="true" />

      <span
        v-if="itensAlterar.length"
        class="grid"
        :class="temConversa ? 'flex-1' : ''"
        data-lista-acao-alterar
      >
        <MenuDeAcoes
          :rotulo-do-botao="t(`${A}.ALTERAR`)"
          :aria-label="t(`${A}.ROTULO_ALTERAR`, { nome })"
          :titulo="nome"
          :itens="itensAlterar"
          :classe-do-botao="temConversa || larga ? 'w-full px-3' : 'px-4'"
          @escolher="emit('alterar', $event)"
        />
      </span>
    </span>
  </div>
</template>
