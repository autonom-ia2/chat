<script setup>
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import { MAX_INSTRUCAO, ehManual, idiomaDoNavegador } from '../../utils/pagina';

// #1181 PR3 (protótipo T14) — "Instruções de {nome}": o editor do agente escrito à mão.
// Modo manual e instrução vão juntos, num PATCH só, e só quando a pessoa salva um texto não vazio
// (DECISOES.md item 7): mandar o modo sozinho apagaria a instrução gerada e deixaria o agente sem
// responder. Fechar sem salvar não grava nada. O aviso de que não dá para voltar atrás fica com quem
// abre a gaveta (a página), antes de entrar aqui pela primeira vez. O campo tem altura própria
// (h-auto min-h-[22rem]): a regra global de textarea (h-16) venceria o rows.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
});

const emit = defineEmits(['fechar']);

const { t, locale } = useI18n();
const store = useStore();
const NS = 'AGENTS.JORNADA.PAGINA.INSTRUCOES';
const base = `instrucoes-${useId()}`;

const texto = ref(ehManual(props.agente) ? props.agente.instruction || '' : '');
const vazio = ref(false);
const falhou = ref(false);
const salvando = ref(false);
const campo = ref(null);

onMounted(() => campo.value?.focus());

const idioma = computed(() => idiomaDoNavegador(locale.value));
const contador = computed(() =>
  t(`${NS}.CONTADOR`, {
    n: texto.value.length.toLocaleString(idioma.value),
    max: MAX_INSTRUCAO.toLocaleString(idioma.value),
  })
);
const descricao = computed(() =>
  [`${base}-dica`, `${base}-contador`, vazio.value ? `${base}-erro` : '']
    .filter(Boolean)
    .join(' ')
);

const aoDigitar = () => {
  if (vazio.value && texto.value.trim()) vazio.value = false;
};

const salvar = async () => {
  if (salvando.value) return;
  if (!texto.value.trim()) {
    vazio.value = true;
    campo.value?.focus();
    return;
  }
  falhou.value = false;
  salvando.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: props.agente.id,
      mode: 'manual',
      instruction: texto.value,
    });
    useAlert(t(`${NS}.SALVO`));
    emit('fechar');
  } catch {
    falhou.value = true;
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <AgenteGaveta
    larga
    :titulo="t(`${NS}.TITULO`, { nome })"
    @fechar="emit('fechar')"
  >
    <p :id="`${base}-dica`" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.DICA`, { nome }) }}
    </p>
    <div class="flex flex-col gap-1">
      <label :for="`${base}-campo`" class="sr-only">
        {{ t(`${NS}.TITULO`, { nome }) }}
      </label>
      <textarea
        :id="`${base}-campo`"
        ref="campo"
        v-model="texto"
        data-instrucao
        rows="16"
        :maxlength="MAX_INSTRUCAO"
        :readonly="salvando"
        :aria-invalid="vazio ? 'true' : undefined"
        :aria-describedby="descricao"
        class="w-full h-auto min-h-[22rem] px-3 py-2 text-base leading-relaxed rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 border-0 !mb-0 text-n-slate-12 resize-y"
        @input="aoDigitar"
      />
      <span
        :id="`${base}-contador`"
        class="self-end text-xs tabular-nums text-n-slate-11"
      >
        {{ contador }}
      </span>
      <p
        v-if="vazio"
        :id="`${base}-erro`"
        role="alert"
        data-vazio
        class="m-0 text-sm text-n-ruby-11"
      >
        {{ t(`${NS}.VAZIO`) }}
      </p>
    </div>
    <template #rodape>
      <AgenteErro
        v-if="falhou"
        data-erro
        :titulo="t(`${NS}.ERRO`)"
        :garantia="t(`${NS}.ERRO_GARANTIA`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        :carregando="salvando"
        @acao="salvar"
      />
      <div class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          variante="contorno"
          tamanho="lg"
          :desabilitado="salvando"
          @click="emit('fechar')"
        >
          {{ t('AGENTS.JORNADA.COMUM.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          v-if="!falhou"
          data-salvar
          tamanho="lg"
          :carregando="salvando"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          @click="salvar"
        >
          {{ t(`${NS}.SALVAR`) }}
        </AgenteBotao>
      </div>
    </template>
  </AgenteGaveta>
</template>
