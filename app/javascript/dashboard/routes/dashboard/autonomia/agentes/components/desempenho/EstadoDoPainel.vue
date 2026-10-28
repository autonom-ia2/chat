<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import { VARIANTES } from '../../utils/desempenhoEstados';

// #2226 (ESPEC 2.11) — o componente único dos estados vazios e intermediários do painel: uma frase e
// um botão. Nunca mostra zero no lugar de "não sei". Quando o botão exige quem gerencia (ligar a
// leitura, conectar a chave, dizer o resultado), quem só vê recebe a frase própria e, se houver, um
// botão que não muda nada. "Conferência abaixo do aceitável" é uma faixa, sem botão.
// Decisão 2 do Rodrigo: sem a chave de IA do cliente, o estado pede para conectar a chave.
const props = defineProps({
  variante: {
    type: String,
    required: true,
    validator: v => Object.keys(VARIANTES).includes(v),
  },
  nome: { type: String, default: '' },
  podeGerenciar: { type: Boolean, default: false },
  // #2301 — painel sem números: só fica o botão que faz algo fora dele (`acao`).
  vazio: { type: Boolean, default: false },
  tom: {
    type: String,
    default: 'claro',
    validator: v => ['claro', 'escuro'].includes(v),
  },
});

const emit = defineEmits(['acao']);

const { t } = useI18n();
const NS = 'AGENTS.DESEMPENHO.ESTADO';

const config = computed(() => VARIANTES[props.variante]);
const semAcesso = computed(
  () => config.value.soQuemGerencia && !props.podeGerenciar
);
const frase = computed(() => {
  const chave = semAcesso.value
    ? `${config.value.chave}_SEM_ACESSO`
    : config.value.chave;
  return t(`${NS}.${chave}`, { nome: props.nome });
});
const botao = computed(() => {
  if (config.value.faixa || config.value.semBotao) return '';
  if (props.vazio && !(config.value.acao && !semAcesso.value)) return '';
  if (!semAcesso.value) return t(`${NS}.${config.value.chave}_BOTAO`);
  return config.value.botaoSemAcesso
    ? t(`${NS}.${config.value.chave}_SEM_ACESSO_BOTAO`)
    : '';
});
const escuro = computed(() => props.tom === 'escuro');
</script>

<template>
  <p
    v-if="config.faixa"
    :data-estado="variante"
    role="status"
    class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
  >
    <span
      class="size-5 shrink-0 text-n-amber-11"
      :class="config.icone"
      aria-hidden="true"
    />
    {{ frase }}
  </p>
  <div
    v-else
    :data-estado="variante"
    class="flex flex-col items-start gap-4 sm:flex-row sm:items-center"
    :class="
      escuro
        ? 'p-4 rounded-2xl bg-white/10 ring-1 ring-inset ring-white/20'
        : 'p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6'
    "
  >
    <span
      aria-hidden="true"
      class="grid rounded-full place-items-center size-11 shrink-0"
      :class="escuro ? 'bg-white/15' : 'bg-n-blue-2'"
    >
      <span
        class="size-5"
        :class="[config.icone, escuro ? 'text-white' : 'text-n-blue-11']"
      />
    </span>
    <p
      data-frase
      class="m-0 text-base font-medium grow"
      :class="escuro ? 'text-white' : 'text-n-slate-12'"
    >
      {{ frase }}
    </p>
    <AgenteBotao
      v-if="botao"
      data-acao-estado
      :variante="escuro ? 'branco' : 'primario'"
      class="w-full sm:w-auto shrink-0"
      @click="emit('acao', variante)"
    >
      {{ botao }}
    </AgenteBotao>
  </div>
</template>
