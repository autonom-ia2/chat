<script setup>
// #2894 — o título dos diálogos da frente, com peso de título. O `Dialog` da casa
// põe o título em `text-base font-medium`, fraco para a primeira coisa que a
// pessoa lê; aqui o título e o aviso abrem o conteúdo do diálogo.
// #3057 — `avisoForte`: quando o aviso é o que a pessoa precisa ler para
// decidir (para quem vai a proposta), ele sobe para o tamanho e a tinta do
// texto principal.
defineProps({
  titulo: { type: String, required: true },
  aviso: { type: String, default: '' },
  avisoForte: { type: Boolean, default: false },
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <h3
      data-relacionamentos="titulo-do-dialogo"
      class="m-0 text-lg font-semibold leading-7 text-n-slate-12"
    >
      {{ titulo }}
    </h3>
    <p
      v-if="aviso"
      class="m-0"
      :class="
        avisoForte ? 'text-base text-n-slate-12' : 'text-sm text-n-slate-11'
      "
    >
      {{ aviso }}
    </p>
  </div>
</template>
