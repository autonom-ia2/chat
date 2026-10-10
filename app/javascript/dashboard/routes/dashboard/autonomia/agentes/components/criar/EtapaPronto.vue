<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import AgentesEtapas from '../AgentesEtapas.vue';
import CelularConversa from '../CelularConversa.vue';

// #1181 PR2 (protótipo T06) — o momento de sucesso: o agente já atende no canal escolhido. O herói
// navy diz onde e quando, o que acontece quando não souber e, se houve troca, quem saiu do canal.
// O celular repete a última pergunta e resposta do teste. "Ver {nome}" abre a página do agente; no
// celular as ações ficam fixas embaixo.
const props = defineProps({
  nome: { type: String, required: true },
  canal: { type: String, default: '' },
  quando: { type: String, default: 'always' },
  saiu: { type: String, default: '' },
  ultimo: { type: Object, default: null },
  empresa: { type: String, default: '' },
  celular: { type: Boolean, default: false },
});

const emit = defineEmits(['ver', 'voltar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR.PRONTO';

const valores = computed(() => ({ nome: props.nome, canal: props.canal }));

const titulo = computed(() =>
  props.canal
    ? t(`${NS}.TITULO`, valores.value)
    : t(`${NS}.TITULO_SEM_CANAL`, valores.value)
);

const QUANDO = {
  business_hours: 'DENTRO',
  outside_business_hours: 'FORA',
};
const agora = computed(() => {
  if (!props.canal) return '';
  const chave = QUANDO[props.quando] || 'AGORA';
  return t(`${NS}.${chave}`, valores.value);
});

const conversa = computed(() =>
  props.ultimo
    ? [
        { de: 'cliente', texto: props.ultimo.pergunta },
        { de: 'agente', texto: props.ultimo.resposta },
      ]
    : []
);
</script>

<template>
  <div
    class="flex flex-col w-full max-w-4xl gap-6 px-4 py-6 mx-auto md:px-6"
    :class="celular ? 'pb-48' : ''"
  >
    <AgentesEtapas :atual="4" />
    <section
      data-heroi
      aria-labelledby="pronto-titulo"
      class="relative overflow-hidden rounded-3xl bg-[#0D2344] dark:bg-[#12305E] text-white px-6 py-8 md:px-10 md:py-10"
    >
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
      />
      <div
        class="relative grid items-center gap-8"
        :class="ultimo ? 'md:grid-cols-[1fr_18rem]' : ''"
      >
        <div class="flex flex-col gap-4">
          <span
            aria-hidden="true"
            class="grid rounded-full place-items-center size-12 bg-n-teal-9 text-white dark:text-n-slate-1"
          >
            <span class="i-lucide-check size-6" />
          </span>
          <h1
            id="pronto-titulo"
            tabindex="-1"
            class="m-0 text-3xl font-bold leading-tight tracking-tight text-white outline-none"
          >
            {{ titulo }}
          </h1>
          <div class="flex flex-col gap-2 text-base leading-relaxed">
            <p v-if="agora" data-agora class="m-0 text-white/90">
              {{ agora }}
            </p>
            <p class="m-0 text-white/90">{{ t(`${NS}.EQUIPE`, { nome }) }}</p>
            <p v-if="saiu && canal" data-saiu class="m-0 text-white/80">
              {{ t(`${NS}.TROCA`, { outro: saiu, canal }) }}
            </p>
          </div>
          <div
            data-acoes
            class="flex flex-wrap items-center gap-4"
            :class="
              celular
                ? 'fixed inset-x-0 bottom-0 z-20 flex-col items-stretch p-4 border-t bg-n-solid-1 border-n-weak'
                : ''
            "
          >
            <AgenteBotao
              data-ver
              :variante="celular ? 'primario' : 'branco'"
              tamanho="xl"
              :bloco="celular"
              icone-direita="i-lucide-arrow-right"
              @click="emit('ver')"
            >
              {{ t(`${NS}.VER`, { nome }) }}
            </AgenteBotao>
            <button
              type="button"
              data-voltar
              class="font-semibold underline min-h-11 focus-visible:outline focus-visible:outline-2"
              :class="
                celular
                  ? 'text-n-blue-11 focus-visible:outline-n-blue-11'
                  : 'text-white focus-visible:outline-white'
              "
              @click="emit('voltar')"
            >
              {{ t('AGENTS.JORNADA.CRIAR.VOLTAR') }}
            </button>
          </div>
        </div>
        <CelularConversa
          v-if="ultimo"
          data-celular
          :mensagens="conversa"
          :nome="empresa || nome"
          :estado="t('AGENTS.JORNADA.CRIAR.CONFIRA.ATENDIDO_POR', { nome })"
        />
      </div>
    </section>
  </div>
</template>
