<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { haQuanto } from '../seusPostsHelpers';

// Seus posts F2 (#2305): um comentário do post, com o que aconteceu com ele e o que dá para fazer. Os botões vêm do
// servidor (`pode`): quem só vê não recebe nenhum, e a Meta diz o que o token alcança. Uma ação principal por linha
// (responder; mostrar de novo, quando escondido) e as outras no "Mais". Mandar no privado é só no Instagram, uma vez
// e até 7 dias depois do comentário (regra da Meta): a pessoa escreve a mensagem e manda. Apagar pede confirmação.
const props = defineProps({
  comentario: { type: Object, required: true },
  // Uma ação deste comentário está indo para a Meta: os botões esperam.
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits([
  'responder',
  'privado',
  'esconder',
  'apagar',
  'liberar',
]);

const { locale, t } = useI18n();
// 'responder', 'privado', 'apagar' (confirmar) ou null.
const abrindo = ref(null);
const texto = ref('');
const maisAberto = ref(false);

const autor = computed(
  () => props.comentario.autor || t('SEUS_POSTS.POST.COMMENTS.SOMEONE')
);
const ESTADOS = {
  esperando: 'bg-n-amber-3 text-n-amber-11',
  respondido: 'bg-n-teal-3 text-n-teal-11',
  privado: 'bg-n-blue-3 text-n-blue-11',
  escondido: 'bg-n-alpha-2 text-n-slate-11',
};
const escondido = computed(() => props.comentario.estado === 'escondido');
const pode = computed(() => props.comentario.pode);

const ACOES = {
  responder: { icone: 'i-lucide-reply', texto: 'REPLY' },
  privado: { icone: 'i-lucide-send', texto: 'PRIVATE' },
  esconder: { icone: 'i-lucide-eye-off', texto: 'HIDE' },
  mostrar: { icone: 'i-lucide-eye', texto: 'SHOW' },
  apagar: { icone: 'i-lucide-trash-2', texto: 'DELETE' },
};
const principal = computed(() => {
  if (escondido.value) return pode.value.esconder ? 'mostrar' : null;
  return pode.value.responder ? 'responder' : null;
});
const mais = computed(() =>
  [
    !escondido.value && pode.value.responder && 'responder',
    !escondido.value && pode.value.privado && 'privado',
    !escondido.value && pode.value.esconder && 'esconder',
    pode.value.apagar && 'apagar',
  ].filter(acao => acao && acao !== principal.value)
);
const itensDoMais = computed(() =>
  mais.value.map(acao => ({
    action: acao,
    value: acao,
    icon: ACOES[acao].icone,
    label: t(`SEUS_POSTS.POST.COMMENTS.${ACOES[acao].texto}`),
  }))
);

// Foco de teclado e de leitor de tela: abrir leva ao campo (ou à confirmação de apagar); fechar volta aos botões da
// linha, que somem enquanto o formulário está aberto.
const linha = ref(null);
const focar = seletor =>
  nextTick(() => linha.value?.querySelector(seletor)?.focus());
const fechar = () => {
  abrindo.value = null;
  texto.value = '';
  focar('[data-seus-posts-acao], [data-seus-posts-mais]');
};
const fazer = acao => {
  maisAberto.value = false;
  if (acao === 'esconder') emit('esconder', true);
  else if (acao === 'mostrar') emit('esconder', false);
  else {
    abrindo.value = acao;
    focar('textarea, [data-seus-posts-confirmar-apagar]');
  }
};
const enviar = () => {
  // O texto só some quando a Meta aceitou: quem chama roda `fechar` no sucesso, e uma falha deixa o que foi escrito.
  const mensagem = texto.value.trim();
  if (abrindo.value === 'privado') emit('privado', mensagem, fechar);
  else emit('responder', mensagem, fechar);
};
const apagar = () => {
  emit('apagar');
  fechar();
};

const ACAO =
  'inline-flex min-h-11 items-center gap-1.5 whitespace-nowrap rounded-lg border-0 bg-transparent px-2 text-sm font-medium hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-50';
</script>

<template>
  <li
    ref="linha"
    :data-seus-posts-comentario="comentario.id"
    :data-estado="comentario.estado"
    class="flex gap-3 py-4 first:pt-1 last:pb-1"
  >
    <span
      class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-sm font-semibold text-n-slate-12"
      aria-hidden="true"
    >
      {{ autor.replace('@', '').charAt(0).toUpperCase() }}
    </span>
    <div class="flex min-w-0 flex-1 flex-col gap-1.5">
      <p class="m-0 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
        <span class="font-semibold text-n-slate-12">{{
          comentario.estado === 'meu'
            ? $t('SEUS_POSTS.POST.COMMENTS.YOU')
            : autor
        }}</span>
        <span class="text-n-slate-11">{{
          haQuanto(comentario.quando, locale)
        }}</span>
        <span v-if="ESTADOS[comentario.estado]" class="max-sm:basis-full">
          <span
            class="inline-block rounded-full px-2 py-0.5 text-xs font-semibold"
            :class="ESTADOS[comentario.estado]"
          >
            {{ $t(`SEUS_POSTS.POST.COMMENTS.STATE.${comentario.estado}`) }}
          </span>
        </span>
      </p>
      <p
        class="m-0 whitespace-pre-line break-words text-base"
        :class="escondido ? 'text-n-slate-10 line-through' : 'text-n-slate-12'"
      >
        {{
          comentario.texto ||
          (comentario.anexo ? $t('SEUS_POSTS.POST.COMMENTS.ATTACHMENT') : '')
        }}
      </p>
      <p v-if="escondido" class="m-0 text-sm text-n-slate-11">
        {{ $t('SEUS_POSTS.POST.COMMENTS.WHY.escondido') }}
      </p>
      <p
        v-else-if="comentario.privadoExpirado"
        data-seus-posts-privado-expirado
        class="m-0 text-sm text-n-slate-11"
      >
        {{ $t('SEUS_POSTS.POST.COMMENTS.WHY.velho') }}
      </p>

      <!-- As respostas, embaixo do comentário, como a pessoa vê no post. -->
      <ul
        v-if="comentario.respostas.length"
        class="m-0 flex max-w-prose list-none flex-col gap-1.5 p-0"
      >
        <li
          v-for="resposta in comentario.respostas"
          :key="resposta.id"
          :data-seus-posts-resposta-do-dono="resposta.daConta || undefined"
          class="flex items-start gap-1.5 rounded-lg bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-corner-down-right mt-0.5 size-4 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <span class="break-words">
            <span class="font-semibold">{{
              resposta.daConta
                ? $t('SEUS_POSTS.POST.COMMENTS.YOUR_REPLY')
                : resposta.autor || $t('SEUS_POSTS.POST.COMMENTS.SOMEONE')
            }}</span>
            {{ resposta.texto }}
          </span>
        </li>
      </ul>

      <!-- O privado que foi: confirmado pela Meta, ou sem confirmação (a pessoa confere no Direct). -->
      <div
        v-if="comentario.privado"
        data-seus-posts-privado-mandado
        class="flex max-w-prose flex-col gap-1 rounded-lg bg-n-blue-2 px-3 py-2 text-sm"
      >
        <span class="flex items-center gap-1.5 font-semibold text-n-blue-11">
          <span class="i-lucide-send size-3.5" aria-hidden="true" />
          {{
            comentario.privado.confirmado
              ? $t('SEUS_POSTS.POST.COMMENTS.SENT_PRIVATE')
              : $t('SEUS_POSTS.POST.COMMENTS.SENT_UNCONFIRMED')
          }}
        </span>
        <div class="-ms-2 flex flex-wrap items-center gap-x-1">
          <router-link
            v-if="comentario.privado.conversa"
            :to="comentario.privado.conversa"
            data-seus-posts-ver-conversa
            :class="ACAO"
            class="text-n-blue-11 no-underline"
          >
            <span class="i-lucide-messages-square size-4" aria-hidden="true" />
            {{ $t('SEUS_POSTS.POST.COMMENTS.OPEN_CONVERSATION') }}
          </router-link>
          <button
            v-if="comentario.privado.podeLiberar"
            type="button"
            data-seus-posts-liberar-privado
            :disabled="ocupado"
            :class="ACAO"
            class="text-n-slate-11"
            @click="emit('liberar')"
          >
            <span class="i-lucide-rotate-ccw size-4" aria-hidden="true" />
            {{ $t('SEUS_POSTS.POST.COMMENTS.NOT_SENT') }}
          </button>
        </div>
      </div>

      <form
        v-if="abrindo === 'responder' || abrindo === 'privado'"
        :data-seus-posts-escrever="abrindo"
        class="mt-1 flex flex-col gap-2"
        @submit.prevent="enviar"
      >
        <label
          class="text-sm font-medium text-n-slate-12"
          :for="`texto-${comentario.id}`"
        >
          {{
            abrindo === 'privado'
              ? $t('SEUS_POSTS.POST.COMMENTS.PRIVATE_LABEL', { name: autor })
              : $t('SEUS_POSTS.POST.COMMENTS.REPLY_LABEL', { name: autor })
          }}
        </label>
        <textarea
          :id="`texto-${comentario.id}`"
          v-model="texto"
          rows="2"
          class="w-full rounded-xl border border-n-weak bg-n-solid-1 p-3 text-base text-n-slate-12 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        />
        <p v-if="abrindo === 'privado'" class="m-0 text-sm text-n-slate-11">
          {{ $t('SEUS_POSTS.POST.COMMENTS.PRIVATE_NOTE') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            type="submit"
            :data-seus-posts-enviar="abrindo"
            :icon="abrindo === 'privado' ? 'i-lucide-send' : 'i-lucide-reply'"
            :disabled="!texto.trim() || ocupado"
            :label="
              abrindo === 'privado'
                ? $t('SEUS_POSTS.POST.COMMENTS.PRIVATE_SEND')
                : $t('SEUS_POSTS.POST.COMMENTS.SEND')
            "
            class="!min-h-11 !rounded-xl"
          />
          <Button
            type="button"
            variant="ghost"
            color="slate"
            :label="$t('SEUS_POSTS.POST.COMMENTS.CANCEL')"
            class="!min-h-11 !rounded-xl"
            @click="fechar"
          />
        </div>
      </form>

      <!-- Apagar não volta: a pessoa confirma, sabendo que some do post para todo mundo. -->
      <div
        v-else-if="abrindo === 'apagar'"
        data-seus-posts-confirmar-apagar
        tabindex="-1"
        class="mt-1 flex flex-col gap-3 rounded-xl bg-n-ruby-2 p-3 outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      >
        <p class="m-0 text-sm text-n-slate-12">
          {{ $t('SEUS_POSTS.POST.COMMENTS.DELETE_CONFIRM', { name: autor }) }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            data-seus-posts-apagar
            color="ruby"
            icon="i-lucide-trash-2"
            :disabled="ocupado"
            :label="$t('SEUS_POSTS.POST.COMMENTS.DELETE_SEND')"
            class="!min-h-11 !rounded-xl"
            @click="apagar"
          />
          <Button
            variant="ghost"
            color="slate"
            :label="$t('SEUS_POSTS.POST.COMMENTS.CANCEL')"
            class="!min-h-11 !rounded-xl"
            @click="fechar"
          />
        </div>
      </div>

      <div
        v-else-if="principal || mais.length"
        class="-ms-2 flex flex-wrap items-center gap-x-1"
      >
        <button
          v-if="principal"
          type="button"
          :data-seus-posts-acao="principal"
          :disabled="ocupado"
          :class="[
            ACAO,
            comentario.estado === 'esperando'
              ? 'font-semibold text-n-blue-11'
              : 'text-n-slate-11',
          ]"
          @click="fazer(principal)"
        >
          <span
            :class="ACOES[principal].icone"
            class="size-4"
            aria-hidden="true"
          />
          {{ $t(`SEUS_POSTS.POST.COMMENTS.${ACOES[principal].texto}`) }}
        </button>
        <div
          v-if="mais.length"
          v-on-click-outside="() => (maisAberto = false)"
          class="relative"
        >
          <button
            type="button"
            data-seus-posts-mais
            :aria-expanded="maisAberto"
            :disabled="ocupado"
            :class="ACAO"
            class="text-n-slate-11"
            @click="maisAberto = !maisAberto"
          >
            <span class="i-lucide-ellipsis size-4" aria-hidden="true" />
            {{ $t('SEUS_POSTS.POST.COMMENTS.MORE') }}
          </button>
          <DropdownMenu
            v-if="maisAberto"
            class="top-full mt-1 ltr:right-0 rtl:left-0"
            :menu-items="itensDoMais"
            @action="fazer($event.action)"
          />
        </div>
      </div>
    </div>
  </li>
</template>
