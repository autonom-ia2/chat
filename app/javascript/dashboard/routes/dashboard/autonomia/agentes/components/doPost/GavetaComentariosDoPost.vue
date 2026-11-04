<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';

// #2469 (PR 3a do #2436) — "Comentários" do cartão do post, em três grupos: no privado (#2481: quem recebeu da IA no
// privado, com o comentário que abriu a conversa e o "Ver conversa", só as conversas que a pessoa vê), esperando você e
// não respondo (o que a IA leu e não era o caso, e o que ela escondeu). Os grupos vêm prontos do servidor: a mesma
// conta do cartão e da página. Cada comentário diz por quê, com
// os textos da tela do cuidado, e leva à conversa (quando há uma que a pessoa vê) ou ao post para responder.
const props = defineProps({
  detalhe: { type: Object, required: true },
  grupo: { type: String, required: true },
  // A tela com todos os comentários do post ou do anúncio, para responder.
  rotaDoAlvo: { type: Object, required: true },
});

const emit = defineEmits(['fechar', 'update:grupo']);

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST.COMENTARIOS';
const GRUPOS = ['respondidos', 'esperando', 'nao_respondo'];

const comentarios = computed(() => props.detalhe.comentarios || {});
const enviados = computed(() => comentarios.value.results?.sent || 0);
// A Meta não deixou ler (sem permissão, fora do ar): esperando e não respondo ficam sem número, nunca zero.
const leu = computed(() => comentarios.value.status === 'ready');
const numero = chave => {
  if (chave === 'respondidos') return enviados.value;
  return leu.value ? (comentarios.value[chave] || []).length : '–';
};
const lista = computed(() => comentarios.value[props.grupo] || []);
const noPrivado = computed(() => comentarios.value.no_privado || []);
const alvo = computed(() =>
  t(`AGENTS.AGENTE_DO_POST.PAGINA.ALVO.${props.detalhe.kind.toUpperCase()}`)
);
</script>

<template>
  <AgenteGaveta :titulo="t(`${KEY}.TITULO`)" @fechar="emit('fechar')">
    <div data-gaveta-comentarios class="flex flex-col gap-4">
      <div
        role="group"
        :aria-label="t(`${KEY}.TITULO`)"
        class="grid grid-cols-3 gap-2"
      >
        <button
          v-for="chave in GRUPOS"
          :key="chave"
          type="button"
          :data-grupo="chave"
          :aria-pressed="grupo === chave"
          class="flex flex-col items-center gap-0.5 px-2 py-2 border-0 rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          :class="
            grupo === chave
              ? 'bg-n-slate-12 text-n-solid-1'
              : 'bg-n-alpha-2 text-n-slate-12'
          "
          @click="emit('update:grupo', chave)"
        >
          <span class="text-lg font-semibold">{{ numero(chave) }}</span>
          <span class="text-xs font-medium">
            {{ t(`${KEY}.${chave.toUpperCase()}`) }}
          </span>
        </button>
      </div>

      <div
        v-if="grupo === 'respondidos'"
        data-respondidos
        class="flex flex-col gap-3"
      >
        <p class="m-0 text-sm leading-6 text-n-slate-11">
          {{ t(`${KEY}.RESPONDIDOS_TEXTO`) }}
        </p>
        <p
          v-if="!noPrivado.length"
          data-nenhum
          class="m-0 text-sm leading-6 text-n-slate-11"
        >
          {{ t(`${KEY}.NENHUM`) }}
        </p>
        <ol
          v-else
          data-no-privado
          class="flex flex-col gap-3 p-0 m-0 list-none"
        >
          <li
            v-for="item in noPrivado"
            :key="item.id"
            :data-no-privado-conversa="item.id"
            class="flex flex-col gap-2 p-4 rounded-2xl ring-1 ring-inset ring-n-weak"
          >
            <p class="m-0 text-sm leading-6 text-n-slate-12">
              <span class="block text-xs font-semibold text-n-slate-11">
                {{ item.contato }}
              </span>
              {{ item.comentario }}
            </p>
            <p
              v-if="item.respondeu"
              data-respondeu
              class="inline-flex items-center gap-1.5 m-0 text-xs font-semibold leading-5 text-n-teal-11"
            >
              <span class="i-lucide-reply size-4" aria-hidden="true" />
              {{ t(`${KEY}.RESPONDEU`) }}
            </p>
            <a
              v-if="item.conversation_path"
              data-ver-conversa
              :href="item.conversation_path"
              :aria-label="
                t(`${KEY}.VER_CONVERSA_DE`, { contato: item.contato })
              "
              class="inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 w-fit text-n-blue-11"
            >
              {{ t(`${KEY}.VER_CONVERSA`) }}
            </a>
          </li>
        </ol>
      </div>
      <p
        v-else-if="!leu"
        data-sem-leitura
        role="alert"
        class="m-0 text-sm leading-6 text-n-slate-12"
      >
        {{ t(`${KEY}.SEM_LEITURA`) }}
      </p>
      <p
        v-else-if="!lista.length"
        data-nenhum
        class="m-0 text-sm leading-6 text-n-slate-11"
      >
        {{ t(`${KEY}.NENHUM`) }}
      </p>
      <ol v-else data-lista class="flex flex-col gap-3 p-0 m-0 list-none">
        <li
          v-for="item in lista"
          :key="item.id"
          :data-comentario="item.id"
          class="flex flex-col gap-2 p-4 rounded-2xl ring-1 ring-inset ring-n-weak"
        >
          <p class="m-0 text-sm leading-6 text-n-slate-12">
            <span class="block text-xs font-semibold text-n-slate-11">
              {{ item.author ? `@${item.author}` : '' }}
            </span>
            {{ item.text }}
          </p>
          <p class="m-0 text-xs leading-5 text-n-slate-11">
            {{ t(`META_ADS_COMMENTS_AI.ON.KIND.${item.kind}`) }}
          </p>
          <a
            v-if="item.conversation_path"
            data-ver-conversa
            :href="item.conversation_path"
            class="inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 w-fit text-n-blue-11"
          >
            {{ t(`${KEY}.VER_CONVERSA`) }}
          </a>
        </li>
      </ol>
      <router-link
        data-ver-todos
        :to="rotaDoAlvo"
        class="inline-flex items-center justify-center gap-2 px-4 text-sm font-semibold no-underline rounded-xl min-h-11 w-fit bg-n-blue-11 text-white dark:text-n-slate-1 hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      >
        <span class="i-lucide-reply size-4" aria-hidden="true" />
        {{ t(`${KEY}.VER_TODOS`, { alvo }) }}
      </router-link>
    </div>
  </AgenteGaveta>
</template>
