<script setup>
// #1809 — contato novo dentro da gaveta, quando a busca não acha ninguém: Nome
// (obrigatório), E-mail (obrigatório quando a gaveta abriu do "Escrever" da caixa de
// e-mail, que só envia para e-mail) e Telefone (opcional; já serve para o WhatsApp).
// O que a pessoa digitou na busca entra no campo certo.
import { computed, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { podeCriarContato } from './novaConversa';

const props = defineProps({
  termo: { type: String, default: '' },
  criando: { type: Boolean, default: false },
  erroAoCriar: { type: Boolean, default: false },
  exigeEmail: { type: Boolean, default: false },
});
const emit = defineEmits(['criar']);

const P = 'NOVA_CONVERSA.CONTATO_NOVO';
const nome = ref('');
const email = ref('');
const telefone = ref('');

watch(
  () => props.termo,
  termo => {
    const valor = termo.trim();
    const ehEmail = valor.includes('@');
    const ehTelefone =
      !ehEmail && [...valor].some(letra => letra >= '0' && letra <= '9');
    nome.value = ehEmail || ehTelefone ? '' : valor;
    email.value = ehEmail ? valor : '';
    telefone.value = ehTelefone ? valor : '';
  },
  { immediate: true }
);

// Telefone como a pessoa escreve: "(11) 98765-0001" vira "+5511987650001" (DDD do
// Brasil, sem o +55); com "+" na frente, vale o país digitado.
const SO_DIGITOS = texto => [...texto].filter(c => c >= '0' && c <= '9').join('');
const DIGITOS_COM_DDD = [10, 11];
const telefoneE164 = computed(() => {
  const valor = telefone.value.trim();
  if (!valor) return '';
  const digitos = SO_DIGITOS(valor);
  if (valor.startsWith('+')) return `+${digitos}`;
  return DIGITOS_COM_DDD.includes(digitos.length) ? `+55${digitos}` : `+${digitos}`;
});

const emailValido = computed(() => podeCriarContato(email.value));
const telefoneValido = computed(
  () => !telefone.value.trim() || podeCriarContato(telefoneE164.value)
);
const erros = computed(() => ({
  nome: !nome.value.trim(),
  email: email.value.trim() ? !emailValido.value : props.exigeEmail,
  telefone: !telefoneValido.value,
  contato: !email.value.trim() && !telefone.value.trim(),
}));
const pronto = computed(
  () =>
    !erros.value.nome &&
    !erros.value.email &&
    !erros.value.telefone &&
    !erros.value.contato
);
const tentou = ref(false);

const criar = () => {
  tentou.value = true;
  if (!pronto.value || props.criando) return;
  emit('criar', {
    nome: nome.value.trim(),
    email: email.value.trim(),
    telefone: telefoneE164.value,
  });
};

const CAMPO =
  'reset-base !mb-0 min-h-12 w-full rounded-2xl border bg-n-solid-1 px-4 text-base text-n-slate-12 outline-none transition placeholder:text-n-slate-10 hover:border-n-slate-7 focus:border-n-blue-8';
</script>

<template>
  <form
    class="flex w-full flex-col gap-4 rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
    data-contato-novo
    novalidate
    @submit.prevent="criar"
  >
    <p class="mb-0 text-[0.9375rem] font-semibold text-n-slate-12">
      {{ $t(`${P}.TITULO`) }}
    </p>
    <label class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${P}.NOME`) }}
        <span class="text-n-ruby-11" aria-hidden="true">*</span>
      </span>
      <input
        v-model="nome"
        type="text"
        autocomplete="off"
        required
        :placeholder="$t(`${P}.NOME_EXEMPLO`)"
        :class="[CAMPO, tentou && erros.nome ? 'border-n-ruby-8' : 'border-n-weak']"
        :aria-invalid="tentou && erros.nome"
        data-campo-nome
      />
    </label>
    <label class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${P}.EMAIL`) }}
        <span v-if="exigeEmail" class="text-n-ruby-11" aria-hidden="true">*</span>
      </span>
      <input
        v-model="email"
        type="email"
        autocomplete="off"
        :required="exigeEmail"
        :placeholder="$t(`${P}.EMAIL_EXEMPLO`)"
        :class="[CAMPO, tentou && erros.email ? 'border-n-ruby-8' : 'border-n-weak']"
        :aria-invalid="tentou && erros.email"
        data-campo-email
      />
    </label>
    <label class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${P}.TELEFONE`) }}
        <span class="font-normal text-n-slate-11">{{ $t(`${P}.OPCIONAL`) }}</span>
      </span>
      <input
        v-model="telefone"
        type="tel"
        autocomplete="off"
        :placeholder="$t(`${P}.TELEFONE_EXEMPLO`)"
        :class="[CAMPO, tentou && erros.telefone ? 'border-n-ruby-8' : 'border-n-weak']"
        :aria-invalid="tentou && erros.telefone"
        data-campo-telefone
      />
    </label>
    <p
      v-if="tentou && !pronto"
      role="alert"
      class="mb-0 text-[0.9375rem] text-n-amber-11"
    >
      {{
        erros.nome
          ? $t(`${P}.FALTA_NOME`)
          : erros.email
            ? $t(exigeEmail && !email.trim() ? `${P}.FALTA_EMAIL` : `${P}.EMAIL_INVALIDO`)
            : erros.telefone
              ? $t(`${P}.TELEFONE_INVALIDO`)
              : $t(`${P}.FALTA_CONTATO`)
      }}
    </p>
    <p v-if="erroAoCriar" role="alert" class="mb-0 text-[0.9375rem] text-n-amber-11">
      {{ $t('NOVA_CONVERSA.PARA_QUEM.ERRO_CRIAR') }}
    </p>
    <Button
      type="submit"
      :label="$t(`${P}.CRIAR`)"
      icon="i-lucide-user-round-plus"
      class="!min-h-11 self-start"
      :is-loading="criando"
      :disabled="criando"
    />
  </form>
</template>
