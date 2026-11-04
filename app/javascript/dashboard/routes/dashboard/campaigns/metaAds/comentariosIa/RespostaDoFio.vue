<script setup>
// #2454: a resposta de outra pessoa dentro de um comentário, no passo 3 do CuidarDono, com o próprio selo. Fica dentro
// do cartão do comentário de cima quando ele é um dos exemplos; senão, num cartão próprio, abaixo do de cima.
// Com `kind: 'recebe'` o selo não promete o privado: a Meta decide se aceita o privado em resposta.
const props = defineProps({
  resposta: { type: Object, required: true },
});

const KEY = 'META_ADS_COMMENTS_AI.DONO';
const handle = comment =>
  comment.network === 'facebook' ? comment.author : `@${comment.author}`;
</script>

<template>
  <div
    data-ia-dono-reply-group
    class="ms-4 flex flex-col gap-2 border-s-2 border-n-weak ps-4"
    :aria-label="$t(`${KEY}.SEE.REPLY`)"
    role="group"
  >
    <p data-ia-dono-reply class="m-0 text-base leading-6 text-n-slate-12">
      <span class="block text-sm font-semibold text-n-slate-11">
        {{ handle(props.resposta) }}
      </span>
      {{ props.resposta.text }}
    </p>
    <span
      data-ia-dono-reply-kind
      class="inline-flex w-fit items-center gap-1.5 rounded-full px-3 py-1 text-sm font-semibold"
      :class="
        props.resposta.kind === 'recebe'
          ? 'bg-n-teal-3 text-n-teal-11'
          : 'bg-n-alpha-2 text-n-slate-11'
      "
    >
      {{
        $t(
          `${KEY}.SEE.${props.resposta.kind === 'recebe' ? 'REPLY_TRIES' : 'SKIPS'}`
        )
      }}
    </span>
  </div>
</template>
