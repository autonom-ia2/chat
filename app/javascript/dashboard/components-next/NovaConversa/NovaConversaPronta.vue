<script setup>
import { computed, ref, watchEffect } from 'vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import NovaConversaCartao from './NovaConversaCartao.vue';
import NovaConversaOpcao from './NovaConversaOpcao.vue';
import NovaConversaProntaCampos from './NovaConversaProntaCampos.vue';
import NovaConversaTextoComCampos from './NovaConversaTextoComCampos.vue';
import { nomeLegivel } from './novaConversa';
import { preenchedorProprioCobre, textoDoCorpo } from './modeloPronto';

// #1459 — escolher uma mensagem pronta (modelo aprovado pelo WhatsApp) e
// completar os campos dela. A lista são cartões-opção; escolhida, vira frase
// com "Alterar" e os campos aparecem logo abaixo.
const props = defineProps({
  modelos: { type: Array, default: () => [] },
  // Só quem pode gerenciar modelos vê o botão de criar.
  podeCriar: { type: Boolean, default: false },
});

const emit = defineEmits(['update:camposProntos', 'update:texto', 'criar']);

const modelo = defineModel({ type: Object, default: null });

const P = 'NOVA_CONVERSA.MENSAGEM';
const MUITOS = 6;

const busca = ref('');
const preenchedor = ref(null);
const montada = ref(null);

const chaveDe = item => `${item.id ?? item.name}-${item.language ?? ''}`;
const escolhida = computed({
  get: () => (modelo.value ? chaveDe(modelo.value) : null),
  set: chave => {
    modelo.value = props.modelos.find(item => chaveDe(item) === chave) || null;
  },
});

// Cabeçalho com mídia e botão com variável ainda são do preenchedor antigo.
const comPreenchedorProprio = computed(
  () => !modelo.value || preenchedorProprioCobre(modelo.value)
);

const visiveis = computed(() => {
  const termo = busca.value.trim().toLowerCase();
  if (!termo) return props.modelos;
  return props.modelos.filter(
    item =>
      nomeLegivel(item.name).toLowerCase().includes(termo) ||
      textoDoCorpo(item).toLowerCase().includes(termo)
  );
});

// O preenchedor diz, a cada tecla, se falta campo e como o texto fica.
watchEffect(() => {
  const aberto = modelo.value && preenchedor.value;
  emit('update:camposProntos', Boolean(aberto && !aberto.isFormInvalid));
  emit(
    'update:texto',
    aberto
      ? [aberto.renderedHeader, aberto.renderedTemplate]
          .filter(Boolean)
          .join('\n\n')
      : ''
  );
});

// Devolve { message, templateParams } pronto para enviar, ou null se faltar.
const montar = () => {
  montada.value = null;
  preenchedor.value?.sendMessage();
  return montada.value;
};

defineExpose({ montar });
</script>

<template>
  <div
    v-if="!modelos.length"
    data-nova-conversa-sem-pronta
    class="flex flex-col items-start gap-3 rounded-2xl border border-dashed border-n-slate-6 bg-n-alpha-1 p-4 sm:flex-row sm:items-center"
  >
    <span class="min-w-0 flex-1 text-[0.9375rem] text-n-slate-12">
      {{ $t(`${P}.SEM_PRONTA`) }}
      <template v-if="!podeCriar">{{ $t(`${P}.SEM_PRONTA_PECA`) }}</template>
    </span>
    <Button
      v-if="podeCriar"
      :label="$t(`${P}.CRIAR_PRONTA`)"
      icon="i-lucide-plus"
      slate
      faded
      class="!min-h-11 shrink-0"
      @click="$emit('criar')"
    />
  </div>

  <div v-else-if="modelo" class="flex flex-col gap-5">
    <NovaConversaCartao
      icone="i-lucide-message-square-text"
      tom="bg-n-teal-3 text-n-teal-11"
      :titulo="$t(`${P}.ESCOLHIDA`)"
      @alterar="modelo = null"
    >
      <strong class="font-semibold">{{ nomeLegivel(modelo.name) }}</strong>
    </NovaConversaCartao>
    <NovaConversaProntaCampos
      v-if="comPreenchedorProprio"
      ref="preenchedor"
      :template="modelo"
      @send-message="montada = $event"
    />
    <!-- Só para modelo com mídia no cabeçalho ou botão com variável: o
         preenchedor antigo, com o resumo dele (nome, idioma, categoria)
         escondido, porque a prévia ao lado já mostra a mensagem. -->
    <WhatsAppTemplateParser
      v-else
      ref="preenchedor"
      :template="modelo"
      class="[&>div:first-child]:hidden [&_input]:min-h-11"
      @send-message="montada = $event"
    />
  </div>

  <div v-else class="flex flex-col gap-3">
    <span v-if="modelos.length > MUITOS" class="relative flex items-center">
      <span
        class="i-lucide-search pointer-events-none absolute start-4 size-4 text-n-slate-10"
        aria-hidden="true"
      />
      <input
        v-model="busca"
        type="search"
        :aria-label="$t(`${P}.PROCURAR`)"
        :placeholder="$t(`${P}.PROCURAR`)"
        class="reset-base !mb-0 min-h-11 w-full rounded-xl border border-n-weak bg-n-solid-1 pe-4 ps-11 text-[0.9375rem] text-n-slate-12 outline-none transition placeholder:text-n-slate-10 hover:border-n-slate-7 focus:border-n-blue-8"
      />
    </span>
    <div
      role="radiogroup"
      :aria-label="$t(`${P}.SO_PRONTA_TITULO`)"
      class="flex max-h-96 flex-col gap-3 overflow-y-auto p-0.5"
    >
      <NovaConversaOpcao
        v-for="(item, indice) in visiveis"
        :key="chaveDe(item)"
        v-model="escolhida"
        name="nova-conversa-pronta"
        :value="chaveDe(item)"
        :titulo="nomeLegivel(item.name)"
        :foco="indice === 0"
        duas-linhas
      >
        <template #descricao>
          <NovaConversaTextoComCampos :texto="textoDoCorpo(item)" />
        </template>
      </NovaConversaOpcao>
    </div>
    <p
      v-if="!visiveis.length"
      class="mb-0 px-1 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t(`${P}.NENHUMA_BUSCA`) }}
    </p>
  </div>
</template>
