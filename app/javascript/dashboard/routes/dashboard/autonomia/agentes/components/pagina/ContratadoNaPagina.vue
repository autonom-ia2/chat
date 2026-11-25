<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';

// #3211 (Tarefa 28) — o que só o agente contratado tem na página (mockup aprovado, estados 13, 14 e 16):
// - o aviso de que começou a atender, logo depois do último passo (`atendendoNo`: o nome da caixa, ou vazio);
// - o aviso da Universal que recusou o acesso depois (a senha mudou), com "Cadastrar a senha nova";
// - "Corretora e acesso": o nome da corretora e o estado do acesso ao portal, cada um com "Alterar";
// - "O que {nome} faz", com o aviso no item da proposta quando o login só cota.
// Quem só vê lê tudo, sem os botões.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  atendendoNo: { type: String, default: '' },
});

const emit = defineEmits(['alterarCorretora', 'alterarAcesso']);

const { t } = useI18n();

const dados = computed(() => props.agente.contratado || {});
const acesso = computed(() => dados.value.acesso || null);
const recusado = computed(() => acesso.value?.estado === 'recusado');
const conferido = computed(() => acesso.value?.estado === 'ok');
const soCota = computed(
  () => conferido.value && acesso.value?.so_cotacao === true
);

const itensFaz = computed(() => [
  { chave: 'duvidas', texto: t('AGENTS.CONTRATADOS.MODELO.FAZ.DUVIDAS') },
  { chave: 'cota', texto: t('AGENTS.CONTRATADOS.MODELO.FAZ.COTA') },
  { chave: 'escolhe', texto: t('AGENTS.CONTRATADOS.MODELO.FAZ.ESCOLHE') },
  {
    chave: 'proposta',
    texto: t('AGENTS.CONTRATADOS.MODELO.FAZ.PROPOSTA'),
    soCota: soCota.value,
  },
]);
</script>

<template>
  <p
    v-if="atendendoNo"
    data-contratado-atendendo
    role="status"
    class="flex items-start gap-3 p-4 m-0 text-base rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6 text-n-slate-12"
  >
    <span
      class="i-lucide-circle-check mt-0.5 size-5 shrink-0 text-n-teal-11"
      aria-hidden="true"
    />
    {{ t('AGENTS.CONTRATADOS.PAGINA.ATENDENDO', { nome, canal: atendendoNo }) }}
  </p>
  <AgenteErro
    v-if="recusado"
    data-aviso-recusado
    :titulo="t('AGENTS.CONTRATADOS.PAGINA.AVISO_RECUSADO.TITULO', { nome })"
    :garantia="t('AGENTS.CONTRATADOS.PAGINA.AVISO_RECUSADO.GARANTIA')"
    :acao="
      podeGerenciar ? t('AGENTS.CONTRATADOS.PAGINA.AVISO_RECUSADO.ACAO') : ''
    "
    icone-acao="i-lucide-key-round"
    @acao="emit('alterarAcesso')"
  />

  <section
    data-corretora-e-acesso
    aria-labelledby="corretora-e-acesso-titulo"
    class="flex flex-col gap-1 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
  >
    <h2
      id="corretora-e-acesso-titulo"
      class="m-0 text-lg font-semibold text-n-slate-12"
    >
      {{ t('AGENTS.CONTRATADOS.PAGINA.CORRETORA_E_ACESSO') }}
    </h2>
    <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
      <li class="flex items-center justify-between gap-3 py-3">
        <span class="flex flex-col min-w-0 gap-0.5">
          <span class="text-sm text-n-slate-11">
            {{ t('AGENTS.CONTRATADOS.PAGINA.CORRETORA') }}
          </span>
          <span class="text-base font-medium truncate text-n-slate-12">
            {{ dados.nome_corretora }}
          </span>
        </span>
        <AgenteBotao
          v-if="podeGerenciar"
          data-alterar-corretora
          variante="contorno"
          :aria-label="t('AGENTS.CONTRATADOS.PAGINA.ALTERAR_CORRETORA_ARIA')"
          @click="emit('alterarCorretora')"
        >
          {{ t('AGENTS.CONTRATADOS.PAGINA.ALTERAR') }}
        </AgenteBotao>
      </li>
      <li class="flex items-center justify-between gap-3 py-3">
        <span class="flex flex-col min-w-0 gap-0.5">
          <span class="text-sm text-n-slate-11">
            {{ t('AGENTS.CONTRATADOS.PAGINA.PORTAL') }}
          </span>
          <span
            v-if="recusado"
            class="flex items-center gap-1.5 text-base font-medium text-n-ruby-11"
          >
            <span
              class="i-lucide-circle-alert size-4 shrink-0"
              aria-hidden="true"
            />
            {{ t('AGENTS.CONTRATADOS.PAGINA.RECUSADO') }}
          </span>
          <span
            v-else-if="conferido"
            class="flex items-center gap-1.5 text-base font-medium text-n-slate-12"
          >
            <span
              class="i-lucide-circle-check size-4 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            {{ t('AGENTS.CONTRATADOS.PAGINA.CONFERIDO') }}
          </span>
          <span
            v-else
            class="flex items-center gap-1.5 text-base font-medium text-n-slate-12"
          >
            <span
              class="i-lucide-circle-dashed size-4 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            {{ t('AGENTS.CONTRATADOS.PAGINA.NAO_CONFERIDO') }}
          </span>
        </span>
        <AgenteBotao
          v-if="podeGerenciar"
          data-alterar-acesso-pagina
          variante="contorno"
          :aria-label="t('AGENTS.CONTRATADOS.PAGINA.ALTERAR_ACESSO_ARIA')"
          @click="emit('alterarAcesso')"
        >
          {{ t('AGENTS.CONTRATADOS.PAGINA.ALTERAR') }}
        </AgenteBotao>
      </li>
    </ul>
  </section>

  <section
    aria-labelledby="contratado-faz-titulo"
    class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
  >
    <h2
      id="contratado-faz-titulo"
      class="m-0 text-lg font-semibold text-n-slate-12"
    >
      {{ t('AGENTS.CONTRATADOS.PAGINA.FAZ_TITULO', { nome }) }}
    </h2>
    <ul data-faz class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="item in itensFaz"
        :key="item.chave"
        class="flex items-start gap-3 text-base text-n-slate-12"
      >
        <span
          class="mt-0.5 size-5 shrink-0"
          :class="
            item.soCota
              ? 'i-lucide-triangle-alert text-n-amber-11'
              : 'i-lucide-circle-check text-n-teal-11'
          "
          aria-hidden="true"
        />
        <span class="flex flex-col gap-0.5">
          {{ item.texto }}
          <span v-if="item.soCota" class="text-sm text-n-slate-11">
            {{ t('AGENTS.CONTRATADOS.ACESSO.SO_COTA.ITEM') }}
          </span>
        </span>
      </li>
    </ul>
  </section>
</template>
