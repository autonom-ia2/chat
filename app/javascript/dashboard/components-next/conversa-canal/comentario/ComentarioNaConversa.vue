<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { haQuanto } from 'dashboard/routes/dashboard/seusPosts/seusPostsHelpers';
import { useComentarioDaConversa } from './useComentarioDaConversa';

// Comentários na caixa (#2215): na conversa que nasceu de um comentário do Instagram (#2212), o comentário fica no
// topo, junto dos outros avisos da conversa (topBannerRef), com o que dá para fazer nele sem sair dali: responder em
// público (a resposta sai no post, não no Direct), esconder e mostrar de novo, e apagar (confirma citando o comentário;
// não volta). Os botões vêm do servidor (`pode`): quem só lê não recebe nenhum. Sem a permissão de comentários do
// Instagram, nenhum botão, e a explicação de como liberar.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { locale, t } = useI18n();
const {
  estado,
  comentario,
  pode,
  podeLiberar,
  ocupado,
  carregar,
  responder,
  esconder,
  apagar,
} = useComentarioDaConversa({
  conversationId: computed(() => props.conversationId),
});

// 'responder', 'apagar' (confirmar) ou null.
const abrindo = ref(null);
const texto = ref('');
const cartao = ref(null);

const escondido = computed(() => Boolean(comentario.value?.escondido));
const autor = computed(
  () => comentario.value?.autor || t('CONVERSA_CANAL.COMENTARIO.ALGUEM')
);
const algumBotao = computed(
  () => pode.value.responder || pode.value.esconder || pode.value.apagar
);

// Foco: abrir leva ao campo (ou à confirmação); fechar volta aos botões, que somem enquanto o formulário está aberto.
const focar = seletor =>
  nextTick(() => cartao.value?.querySelector(seletor)?.focus());
const fechar = () => {
  abrindo.value = null;
  texto.value = '';
  focar('[data-comentario-acao]');
};
const abrir = acao => {
  abrindo.value = acao;
  focar('textarea, [data-comentario-confirmar-apagar]');
};
// O texto só some quando a Meta aceitou; uma falha deixa o que foi escrito.
const enviar = async () => {
  if (await responder(texto.value.trim())) fechar();
};
const confirmarApagar = async () => {
  await apagar();
  abrindo.value = null;
};

const ACAO =
  'inline-flex min-h-11 items-center gap-1.5 whitespace-nowrap rounded-lg border-0 bg-transparent px-2 text-sm font-medium hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-50';
</script>

<template>
  <section
    ref="cartao"
    data-comentario-na-conversa
    :data-estado="estado"
    :aria-label="$t('CONVERSA_CANAL.COMENTARIO.ROTULO')"
    class="ms-2 me-16 mt-2 flex flex-col gap-1.5 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2.5 text-sm text-n-slate-12"
  >
    <p class="m-0 flex flex-wrap items-center gap-x-2 gap-y-1 text-n-slate-11">
      <span class="i-ri-instagram-line size-4 shrink-0" aria-hidden="true" />
      <span class="font-medium">
        {{
          comentario?.onde === 'anuncio'
            ? $t('CONVERSA_CANAL.COMENTARIO.NO_ANUNCIO')
            : $t('CONVERSA_CANAL.COMENTARIO.NO_POST')
        }}
      </span>
      <template v-if="estado === 'ok'">
        <span class="font-semibold text-n-slate-12">{{ autor }}</span>
        <span>{{ haQuanto(comentario.quando, locale) }}</span>
        <span
          v-if="escondido"
          data-comentario-selo-escondido
          class="inline-block rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-semibold text-n-slate-11"
        >
          {{ $t('CONVERSA_CANAL.COMENTARIO.ESCONDIDO') }}
        </span>
      </template>
    </p>

    <p v-if="estado === 'carregando'" class="m-0 text-n-slate-11" role="status">
      {{ $t('CONVERSA_CANAL.COMENTARIO.CARREGANDO') }}
    </p>

    <template v-else-if="estado === 'needs_permission'">
      <p class="m-0" data-comentario-sem-permissao>
        {{ $t('CONVERSA_CANAL.COMENTARIO.SEM_PERMISSAO') }}
      </p>
      <p v-if="!podeLiberar" class="m-0 text-n-slate-11">
        {{ $t('CONVERSA_CANAL.COMENTARIO.PECA_AO_ADMIN') }}
      </p>
      <div v-else>
        <Button
          data-comentario-liberar
          icon="i-lucide-key-round"
          :label="$t('CONVERSA_CANAL.COMENTARIO.LIBERAR')"
          class="!min-h-11 !rounded-xl"
        />
      </div>
    </template>

    <p
      v-else-if="estado === 'apagado'"
      data-comentario-apagado
      class="m-0 text-n-slate-11"
    >
      {{ $t('CONVERSA_CANAL.COMENTARIO.APAGADO') }}
    </p>

    <template v-else-if="estado === 'meta_unavailable'">
      <p class="m-0 text-n-slate-11">
        {{ $t('CONVERSA_CANAL.COMENTARIO.INDISPONIVEL') }}
      </p>
      <div class="-ms-2">
        <button
          type="button"
          :class="ACAO"
          class="text-n-slate-11"
          @click="carregar"
        >
          <span class="i-lucide-rotate-cw size-4" aria-hidden="true" />
          {{ $t('CONVERSA_CANAL.COMENTARIO.TENTAR_DE_NOVO') }}
        </button>
      </div>
    </template>

    <template v-else-if="estado === 'ok'">
      <p
        data-comentario-texto
        class="m-0 line-clamp-3 whitespace-pre-line break-words text-base"
        :class="escondido ? 'text-n-slate-10 line-through' : 'text-n-slate-12'"
      >
        {{ comentario.texto }}
      </p>
      <p v-if="escondido" class="m-0 text-n-slate-11">
        {{ $t('CONVERSA_CANAL.COMENTARIO.POR_QUE_ESCONDIDO') }}
      </p>

      <ul
        v-if="comentario.respostas?.length"
        class="m-0 flex list-none flex-col gap-1.5 p-0"
      >
        <li
          v-for="resposta in comentario.respostas"
          :key="resposta.id"
          data-comentario-resposta
          class="flex items-start gap-1.5 rounded-lg bg-n-alpha-1 px-3 py-2"
        >
          <span
            class="i-lucide-corner-down-right mt-0.5 size-4 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <span class="break-words">
            <span class="font-semibold">
              {{ $t('CONVERSA_CANAL.COMENTARIO.SUA_RESPOSTA') }}
            </span>
            {{ resposta.texto }}
          </span>
        </li>
      </ul>

      <form
        v-if="abrindo === 'responder'"
        data-comentario-escrever
        class="mt-1 flex flex-col gap-2"
        @submit.prevent="enviar"
      >
        <label
          class="text-sm font-medium text-n-slate-12"
          :for="`comentario-resposta-${conversationId}`"
        >
          {{ $t('CONVERSA_CANAL.COMENTARIO.RESPONDER_ROTULO', { autor }) }}
        </label>
        <textarea
          :id="`comentario-resposta-${conversationId}`"
          v-model="texto"
          rows="2"
          class="w-full rounded-xl border border-n-weak bg-n-solid-1 p-3 text-base text-n-slate-12 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        />
        <p class="m-0 text-n-slate-11">
          {{ $t('CONVERSA_CANAL.COMENTARIO.RESPONDER_NOTA') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            type="submit"
            data-comentario-enviar
            icon="i-lucide-reply"
            :disabled="!texto.trim() || ocupado"
            :label="$t('CONVERSA_CANAL.COMENTARIO.PUBLICAR')"
            class="!min-h-11 !rounded-xl"
          />
          <Button
            type="button"
            variant="ghost"
            color="slate"
            :label="$t('CONVERSA_CANAL.COMENTARIO.CANCELAR')"
            class="!min-h-11 !rounded-xl"
            @click="fechar"
          />
        </div>
      </form>

      <!-- Apagar não volta: a pessoa confirma vendo qual comentário some do post para todo mundo. -->
      <div
        v-else-if="abrindo === 'apagar'"
        data-comentario-confirmar-apagar
        tabindex="-1"
        class="mt-1 flex flex-col gap-3 rounded-xl bg-n-ruby-2 p-3 outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      >
        <p class="m-0 break-words text-n-slate-12">
          {{
            $t('CONVERSA_CANAL.COMENTARIO.APAGAR_CONFIRMA', {
              autor,
              texto: comentario.texto,
            })
          }}
        </p>
        <p class="m-0 text-n-slate-11">
          {{ $t('CONVERSA_CANAL.COMENTARIO.APAGAR_NOTA') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            data-comentario-apagar
            color="ruby"
            icon="i-lucide-trash-2"
            :disabled="ocupado"
            :label="$t('CONVERSA_CANAL.COMENTARIO.APAGAR_SIM')"
            class="!min-h-11 !rounded-xl"
            @click="confirmarApagar"
          />
          <Button
            variant="ghost"
            color="slate"
            :label="$t('CONVERSA_CANAL.COMENTARIO.CANCELAR')"
            class="!min-h-11 !rounded-xl"
            @click="fechar"
          />
        </div>
      </div>

      <div v-else-if="algumBotao" class="-ms-2 flex flex-wrap items-center">
        <button
          v-if="pode.responder && !escondido"
          type="button"
          data-comentario-acao="responder"
          :disabled="ocupado"
          :class="ACAO"
          class="text-n-blue-11"
          @click="abrir('responder')"
        >
          <span class="i-lucide-reply size-4" aria-hidden="true" />
          {{ $t('CONVERSA_CANAL.COMENTARIO.RESPONDER') }}
        </button>
        <button
          v-if="pode.esconder"
          type="button"
          :data-comentario-acao="escondido ? 'mostrar' : 'esconder'"
          :disabled="ocupado"
          :class="ACAO"
          class="text-n-slate-11"
          @click="esconder(!escondido)"
        >
          <span
            :class="escondido ? 'i-lucide-eye' : 'i-lucide-eye-off'"
            class="size-4"
            aria-hidden="true"
          />
          {{
            escondido
              ? $t('CONVERSA_CANAL.COMENTARIO.MOSTRAR')
              : $t('CONVERSA_CANAL.COMENTARIO.ESCONDER')
          }}
        </button>
        <button
          v-if="pode.apagar"
          type="button"
          data-comentario-acao="apagar"
          :disabled="ocupado"
          :class="ACAO"
          class="text-n-ruby-11"
          @click="abrir('apagar')"
        >
          <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
          {{ $t('CONVERSA_CANAL.COMENTARIO.APAGAR') }}
        </button>
      </div>
    </template>
  </section>
</template>
