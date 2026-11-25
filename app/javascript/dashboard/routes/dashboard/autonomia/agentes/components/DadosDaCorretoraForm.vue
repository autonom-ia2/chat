<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteErro from './AgenteErro.vue';
import { MAX_NOME, MAX_SOBRE } from '../constants/contratados';

// #3211 — os dados da corretora no agente contratado (mockup aprovado, estados 03, 04 e 15). Um componente só para
// os dois usos:
// - `contratar` (passo 1 da página do modelo): o nome do agente, o nome e a apresentação da corretora;
// - `editar` (gaveta "Corretora" da página do agente): só os dois da corretora; o nome do agente fica na gaveta de
//   foto e nome. `inicial` traz o que está gravado.
// O botão de enviar fica no rodapé da gaveta de quem usa, que chama `enviar()` (exposto). Os obrigatórios vazios
// bloqueiam o envio aqui mesmo; a recusa do servidor chega por `erro` ({ campo, texto }, utils/contratado): com
// `campo`, o campo fica marcado com o texto embaixo; sem `campo`, o texto vai para o topo do formulário.
const props = defineProps({
  modo: {
    type: String,
    default: 'contratar',
    validator: v => ['contratar', 'editar'].includes(v),
  },
  inicial: { type: Object, default: () => ({}) },
  // O nome do agente, para a ajuda da apresentação no `editar`.
  nome: { type: String, default: '' },
  ocupado: { type: Boolean, default: false },
  erro: { type: Object, default: null },
});

const emit = defineEmits(['enviar']);

const { t } = useI18n();
const base = `corretora-${useId()}`;
const contratar = computed(() => props.modo === 'contratar');

const nomeAgente = ref(props.inicial.nomeAgente || '');
const nomeCorretora = ref(props.inicial.nomeCorretora || '');
const sobreCorretora = ref(props.inicial.sobreCorretora || '');
const campoNome = ref(null);
const campoCorretora = ref(null);
const campoSobre = ref(null);

const CAMPOS = {
  nome_agente: { valor: nomeAgente, elemento: campoNome },
  nome_corretora: { valor: nomeCorretora, elemento: campoCorretora },
  sobre_corretora: { valor: sobreCorretora, elemento: campoSobre },
};
const ERRO_LOCAL = {
  nome_agente: () => t('AGENTS.CONTRATADOS.CONTRATAR.NOME.ERRO'),
  nome_corretora: () => t('AGENTS.CONTRATADOS.CONTRATAR.CORRETORA.ERRO'),
};
const obrigatorios = computed(() =>
  contratar.value ? ['nome_agente', 'nome_corretora'] : ['nome_corretora']
);

const rotulos = computed(() =>
  contratar.value
    ? {
        corretora: t('AGENTS.CONTRATADOS.CONTRATAR.CORRETORA.ROTULO'),
        sobre: t('AGENTS.CONTRATADOS.CONTRATAR.SOBRE.ROTULO'),
        sobreAjuda: t('AGENTS.CONTRATADOS.CONTRATAR.SOBRE.AJUDA'),
        exemplo: t('AGENTS.CONTRATADOS.CONTRATAR.SOBRE.EXEMPLO'),
      }
    : {
        corretora: t('AGENTS.CONTRATADOS.CORRETORA.NOME'),
        sobre: t('AGENTS.CONTRATADOS.CORRETORA.SOBRE'),
        sobreAjuda: t('AGENTS.CONTRATADOS.CORRETORA.SOBRE_AJUDA', {
          nome: props.nome,
        }),
        exemplo: undefined,
      }
);

// Os obrigatórios que estavam vazios no último envio; saem quando a pessoa escreve no campo.
const faltando = ref([]);
// A recusa do servidor à vista: sai quando a pessoa mexe no campo que ela marcou.
const doServidor = ref(props.erro);

const focar = campo => CAMPOS[campo]?.elemento.value?.focus();

watch(
  () => props.erro,
  async erro => {
    doServidor.value = erro;
    if (!erro?.campo) return;
    await nextTick();
    focar(erro.campo);
  }
);

const erroDe = campo => {
  if (faltando.value.includes(campo)) return ERRO_LOCAL[campo]();
  if (doServidor.value?.campo === campo) return doServidor.value.texto;
  return '';
};
const erroDoTopo = computed(() =>
  doServidor.value && !doServidor.value.campo ? doServidor.value.texto : ''
);

const anel = campo =>
  erroDe(campo) ? 'ring-2 ring-n-ruby-9' : 'ring-1 ring-n-slate-7';
const descricao = (campo, ...outros) =>
  [erroDe(campo) ? `${base}-${campo}-erro` : '', ...outros]
    .filter(Boolean)
    .join(' ') || undefined;

const mexeu = campo => {
  faltando.value = faltando.value.filter(item => item !== campo);
  if (doServidor.value?.campo === campo) doServidor.value = null;
};

const limpos = () => ({
  nomeAgente: nomeAgente.value.trim(),
  nomeCorretora: nomeCorretora.value.trim(),
  sobreCorretora: sobreCorretora.value.trim(),
});

const enviar = () => {
  if (props.ocupado) return;
  const valores = limpos();
  faltando.value = obrigatorios.value.filter(
    campo => !CAMPOS[campo].valor.value.trim()
  );
  if (faltando.value.length) {
    focar(faltando.value[0]);
    return;
  }
  doServidor.value = null;
  emit(
    'enviar',
    contratar.value
      ? valores
      : {
          nomeCorretora: valores.nomeCorretora,
          sobreCorretora: valores.sobreCorretora,
        }
  );
};

// Para a gaveta não fechar por Esc ou clique fora com o que a pessoa escreveu.
const temMudanca = () => {
  const valores = limpos();
  return Object.keys(valores).some(
    chave => valores[chave] !== (props.inicial[chave] || '').trim()
  );
};

const CAMPO =
  'w-full px-3 text-base rounded-xl min-h-11 !bg-n-solid-1 ring-inset border-0 !mb-0 text-n-slate-12 disabled:opacity-60';

defineExpose({ enviar, temMudanca });
</script>

<template>
  <form
    :id="base"
    novalidate
    class="flex flex-col gap-5"
    :aria-busy="ocupado ? 'true' : undefined"
    @submit.prevent="enviar"
  >
    <p v-if="contratar" class="m-0 text-base font-semibold text-n-blue-11">
      {{ t('AGENTS.CONTRATADOS.CONTRATAR.PASSO') }}
    </p>
    <AgenteErro
      v-if="erroDoTopo"
      data-erro-do-formulario
      :titulo="erroDoTopo"
    />

    <div v-if="contratar" class="flex flex-col gap-1">
      <label :for="`${base}-nome`" class="text-sm font-medium text-n-slate-12">
        {{ t('AGENTS.CONTRATADOS.CONTRATAR.NOME.ROTULO') }}
      </label>
      <input
        :id="`${base}-nome`"
        ref="campoNome"
        v-model="nomeAgente"
        data-campo="nome_agente"
        :maxlength="MAX_NOME"
        autocomplete="off"
        :disabled="ocupado"
        :aria-invalid="erroDe('nome_agente') ? 'true' : 'false'"
        :aria-describedby="descricao('nome_agente', `${base}-nome-ajuda`)"
        :class="[CAMPO, anel('nome_agente')]"
        @input="mexeu('nome_agente')"
      />
      <p
        v-if="erroDe('nome_agente')"
        :id="`${base}-nome_agente-erro`"
        role="alert"
        class="flex items-center gap-1.5 m-0 text-sm text-n-ruby-11"
      >
        <span
          class="i-lucide-circle-alert size-4 shrink-0"
          aria-hidden="true"
        />
        {{ erroDe('nome_agente') }}
      </p>
      <p :id="`${base}-nome-ajuda`" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.CONTRATADOS.CONTRATAR.NOME.AJUDA') }}
      </p>
    </div>

    <div class="flex flex-col gap-1">
      <label
        :for="`${base}-corretora`"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ rotulos.corretora }}
      </label>
      <input
        :id="`${base}-corretora`"
        ref="campoCorretora"
        v-model="nomeCorretora"
        data-campo="nome_corretora"
        :maxlength="MAX_NOME"
        autocomplete="off"
        :disabled="ocupado"
        :aria-invalid="erroDe('nome_corretora') ? 'true' : 'false'"
        :aria-describedby="descricao('nome_corretora')"
        :class="[CAMPO, anel('nome_corretora')]"
        @input="mexeu('nome_corretora')"
      />
      <p
        v-if="erroDe('nome_corretora')"
        :id="`${base}-nome_corretora-erro`"
        role="alert"
        class="flex items-center gap-1.5 m-0 text-sm text-n-ruby-11"
      >
        <span
          class="i-lucide-circle-alert size-4 shrink-0"
          aria-hidden="true"
        />
        {{ erroDe('nome_corretora') }}
      </p>
    </div>

    <div class="flex flex-col gap-1">
      <label :for="`${base}-sobre`" class="text-sm font-medium text-n-slate-12">
        {{ rotulos.sobre }}
      </label>
      <textarea
        :id="`${base}-sobre`"
        ref="campoSobre"
        v-model="sobreCorretora"
        data-campo="sobre_corretora"
        rows="4"
        :maxlength="MAX_SOBRE"
        :placeholder="rotulos.exemplo"
        :disabled="ocupado"
        :aria-invalid="erroDe('sobre_corretora') ? 'true' : 'false'"
        :aria-describedby="
          descricao(
            'sobre_corretora',
            `${base}-sobre-ajuda`,
            `${base}-sobre-contador`
          )
        "
        class="py-2 resize-y min-h-32"
        :class="[CAMPO, anel('sobre_corretora')]"
        @input="mexeu('sobre_corretora')"
      />
      <p
        v-if="erroDe('sobre_corretora')"
        :id="`${base}-sobre_corretora-erro`"
        role="alert"
        class="flex items-center gap-1.5 m-0 text-sm text-n-ruby-11"
      >
        <span
          class="i-lucide-circle-alert size-4 shrink-0"
          aria-hidden="true"
        />
        {{ erroDe('sobre_corretora') }}
      </p>
      <div class="flex items-start justify-between gap-3">
        <p :id="`${base}-sobre-ajuda`" class="m-0 text-sm text-n-slate-11">
          {{ rotulos.sobreAjuda }}
        </p>
        <p
          :id="`${base}-sobre-contador`"
          data-contador
          class="m-0 text-sm text-n-slate-11 shrink-0 tabular-nums"
        >
          {{
            t('AGENTS.CONTRATADOS.CONTRATAR.SOBRE.CONTADOR', {
              atual: sobreCorretora.length,
              maximo: MAX_SOBRE,
            })
          }}
        </p>
      </div>
    </div>
  </form>
</template>
