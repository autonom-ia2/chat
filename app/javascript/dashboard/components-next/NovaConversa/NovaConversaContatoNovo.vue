<script setup>
// #1809 — contato novo dentro da gaveta, quando a busca não acha ninguém. Um cartão
// com a foto (as iniciais aparecem enquanto o nome é digitado), Nome (obrigatório),
// E-mail (obrigatório quando a gaveta abriu do "Escrever" da caixa de e-mail, que só
// envia para e-mail) e Telefone (opcional; já serve para o WhatsApp). O telefone usa
// o campo padrão do painel (CampoDeTelefone: bandeira, DDI, Brasil por padrão, regra
// do CLAUDE.md). O que a pessoa digitou na busca entra no campo certo.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import Input from 'next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import {
  PAIS_PADRAO,
  soDigitosDoTelefone,
  telefoneCompleto,
} from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';
import { podeCriarContato } from './novaConversa';

const props = defineProps({
  termo: { type: String, default: '' },
  criando: { type: Boolean, default: false },
  erroAoCriar: { type: Boolean, default: false },
  exigeEmail: { type: Boolean, default: false },
});
const emit = defineEmits(['criar']);

const { t } = useI18n();
const P = 'NOVA_CONVERSA.CONTATO_NOVO';
const nome = ref('');
const email = ref('');
// E.164 (+5511987654321) quando o número está completo; vazio enquanto não está.
const telefone = ref('');
// Algo foi digitado no telefone (mesmo incompleto): para avisar, em vez de sumir calado.
const digitouTelefone = ref(false);

watch(
  () => props.termo,
  termo => {
    const valor = termo.trim();
    const ehEmail = valor.includes('@');
    const ehTelefone =
      !ehEmail && [...valor].some(letra => letra >= '0' && letra <= '9');
    nome.value = ehEmail || ehTelefone ? '' : valor;
    email.value = ehEmail ? valor : '';
    // O campo de telefone recebe o número completo; sem "+", vale o país padrão.
    let completo = '';
    if (ehTelefone) {
      completo = valor.startsWith('+')
        ? `+${soDigitosDoTelefone(valor)}`
        : telefoneCompleto(soDigitosDoTelefone(valor), PAIS_PADRAO);
    }
    telefone.value = completo;
    digitouTelefone.value = ehTelefone;
  },
  { immediate: true }
);

const aoDigitarTelefone = evento => {
  digitouTelefone.value = Boolean(String(evento.target?.value || '').trim());
};

const erros = computed(() => {
  const temEmail = Boolean(email.value.trim());
  const telefoneIncompleto = digitouTelefone.value && !telefone.value;
  return {
    nome: nome.value.trim() ? '' : t(`${P}.FALTA_NOME`),
    email:
      (temEmail && !podeCriarContato(email.value) && t(`${P}.EMAIL_INVALIDO`)) ||
      (!temEmail && props.exigeEmail && t(`${P}.FALTA_EMAIL`)) ||
      '',
    telefone: telefoneIncompleto ? t(`${P}.TELEFONE_INVALIDO`) : '',
    contato:
      !temEmail && !telefone.value && !props.exigeEmail
        ? t(`${P}.FALTA_CONTATO`)
        : '',
  };
});
const pronto = computed(() => !Object.values(erros.value).some(Boolean));
const tentou = ref(false);
const mostrar = campo => (tentou.value ? erros.value[campo] : '');

const criar = () => {
  tentou.value = true;
  if (!pronto.value || props.criando) return;
  emit('criar', {
    nome: nome.value.trim(),
    email: email.value.trim(),
    telefone: telefone.value,
  });
};
</script>

<template>
  <form
    class="w-full overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
    data-contato-novo
    novalidate
    @submit.prevent="criar"
  >
    <header
      class="flex items-center gap-3 border-b border-n-weak bg-n-alpha-1 px-5 py-4"
    >
      <Avatar
        v-if="nome.trim()"
        :name="nome.trim()"
        :size="44"
        rounded-full
        class="shrink-0"
      />
      <span
        v-else
        class="grid size-11 shrink-0 place-content-center rounded-full bg-n-alpha-2 text-n-slate-10"
        aria-hidden="true"
      >
        <Icon icon="i-lucide-user-round" class="size-5" />
      </span>
      <div class="min-w-0">
        <p class="mb-0 text-base font-semibold text-n-slate-12">
          {{ nome.trim() || t(`${P}.TITULO`) }}
        </p>
        <p class="mb-0 text-sm text-n-slate-11">{{ t(`${P}.SUBTITULO`) }}</p>
      </div>
    </header>

    <div class="flex flex-col gap-4 px-5 py-5">
      <Input
        v-model="nome"
        :label="t(`${P}.NOME`)"
        :placeholder="t(`${P}.NOME_EXEMPLO`)"
        :message="mostrar('nome')"
        :message-type="mostrar('nome') ? 'error' : 'info'"
        autocomplete="off"
        data-campo-nome
      />
      <Input
        v-model="email"
        type="email"
        :label="
          exigeEmail ? t(`${P}.EMAIL`) : t(`${P}.EMAIL_OPCIONAL`)
        "
        :placeholder="t(`${P}.EMAIL_EXEMPLO`)"
        :message="mostrar('email') || (exigeEmail ? t(`${P}.EMAIL_DICA`) : '')"
        :message-type="mostrar('email') ? 'error' : 'info'"
        autocomplete="off"
        data-campo-email
      />
      <div data-campo-telefone @input="aoDigitarTelefone">
        <CampoDeTelefone
          v-model="telefone"
          :label="t(`${P}.TELEFONE`)"
          :rotulo-do-pais="t(`${P}.PAIS`)"
          :ajuda="t(`${P}.TELEFONE_DICA`)"
          :erro="mostrar('telefone')"
        />
      </div>
      <p
        v-if="tentou && erros.contato"
        role="alert"
        class="mb-0 flex items-center gap-2 text-sm text-n-amber-11"
      >
        <Icon icon="i-lucide-info" class="size-4 shrink-0" />
        {{ erros.contato }}
      </p>
      <p
        v-if="erroAoCriar"
        role="alert"
        class="mb-0 flex items-center gap-2 text-sm text-n-ruby-11"
      >
        <Icon icon="i-lucide-circle-alert" class="size-4 shrink-0" />
        {{ t('NOVA_CONVERSA.PARA_QUEM.ERRO_CRIAR') }}
      </p>
    </div>

    <footer
      class="flex justify-end border-t border-n-weak bg-n-alpha-1 px-5 py-3"
    >
      <Button
        type="submit"
        :label="t(`${P}.CRIAR`)"
        icon="i-lucide-user-round-plus"
        class="!min-h-11"
        :is-loading="criando"
        :disabled="criando"
        data-criar-contato
      />
    </footer>
  </form>
</template>
