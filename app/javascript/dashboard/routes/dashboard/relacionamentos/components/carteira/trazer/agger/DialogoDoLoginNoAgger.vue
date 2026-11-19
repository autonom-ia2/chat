<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TituloDoDialogo from '../../../comum/TituloDoDialogo.vue';
import {
  chaveDaRecusaDoAgger,
  codigoDaRecusa,
} from '../../../../carteira/recusas';
import { LOGIN } from '../../../../carteira/useBuscaNoAgger';
import { SEM_ACESSO } from '../../../../ficha/falhas';

// #2900 (E7.3) — a janela que pede só o login e a senha do Agger, com uma
// frase dizendo para que servem. Quem usa passa `conectar`, que devolve o que
// o Agger respondeu (LOGIN); aceito, a janela fecha. Recusado, fora do ar ou
// sem rede, a frase fica dentro da janela e a pessoa tenta de novo (com o Agger
// fora do ar, o botão diz "Tentar de novo"). Quem não pode escrever o login
// (o servidor responde 403) lê para pedir a quem administra a conta, nunca
// "tente de novo". Sem botão desligado: faltando o login ou a senha, a janela
// diz o que falta. A senha não fica guardada aqui depois que a janela fecha.
//
// #3057 — redesenho: cabeçalho com ícone, título e a frase de confiança; cada
// campo com rótulo e ajuda; "Mostrar a senha" dentro do campo (fecha de novo
// ao fechar a janela); o recado de erro numa faixa com ícone, em palavras de
// gente. Entrar é o botão azul, girando enquanto o Agger responde.
// #3057 (revisão) — um aviso de segredo só (o cadeado embaixo da senha); os
// botões do rodapé têm 44 px (size lg).
const props = defineProps({
  conectar: { type: Function, required: true },
});

const { t } = useI18n();
const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.NAO_DEU';
const dialogo = useTemplateRef('dialogo');
const login = ref('');
const senha = ref('');
const alerta = ref('');
const ocupado = ref(false);
const foraDoAr = ref(false);
const senhaVisivel = ref(false);
const rotuloDeEntrar = computed(() =>
  foraDoAr.value
    ? t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.TENTAR_DE_NOVO')
    : t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.ENTRAR')
);

const rotuloDoOlho = computed(() =>
  senhaVisivel.value
    ? t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.ESCONDER_SENHA')
    : t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.MOSTRAR_SENHA')
);

const limpar = () => {
  senha.value = '';
  senhaVisivel.value = false;
  alerta.value = '';
  foraDoAr.value = false;
  ocupado.value = false;
};

const fraseDaFalha = falha => {
  if (falha?.name === SEM_ACESSO) {
    return t('RELACIONAMENTOS_CARTEIRA.AGGER.PECA_AO_ADMIN');
  }
  return t(chaveDaRecusaDoAgger(codigoDaRecusa(falha), NAO_DEU));
};

const entrar = async () => {
  if (ocupado.value) return;
  if (!login.value.trim() || !senha.value) {
    alerta.value = t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.FALTA');
    return;
  }
  ocupado.value = true;
  alerta.value = '';
  try {
    const resposta = await props.conectar({
      login: login.value.trim(),
      senha: senha.value,
    });
    if (resposta === LOGIN.ACEITO) {
      dialogo.value?.close();
      return;
    }
    foraDoAr.value = resposta === LOGIN.FORA_DO_AR;
    alerta.value = foraDoAr.value
      ? t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.FORA_DO_AR')
      : t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.RECUSADO');
  } catch (falha) {
    foraDoAr.value = false;
    alerta.value = fraseDaFalha(falha);
  } finally {
    ocupado.value = false;
  }
};

defineExpose({
  abrir: () => dialogo.value?.open(),
});
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="md"
    :confirm-button-label="rotuloDeEntrar"
    :cancel-button-label="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.VOLTAR')"
    :is-loading="ocupado"
    :close-on-outside-click="false"
    @confirm="entrar"
    @close="limpar"
  >
    <div data-carteira="login-do-agger" class="flex flex-col gap-5">
      <div class="flex items-start gap-4">
        <span
          aria-hidden="true"
          class="flex items-center justify-center size-12 rounded-2xl shrink-0 bg-n-blue-9 text-white"
        >
          <span class="i-lucide-key-round size-6" />
        </span>
        <TituloDoDialogo
          :titulo="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.TITULO')"
          :aviso="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.PARA_QUE')"
        />
      </div>
      <Input
        id="carteira-agger-login"
        v-model="login"
        type="text"
        autocomplete="username"
        custom-input-class="!h-11 !text-base"
        :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.CAMPO_LOGIN')"
      />
      <div class="flex flex-col gap-1">
        <div class="relative">
          <Input
            id="carteira-agger-senha"
            v-model="senha"
            :type="senhaVisivel ? 'text' : 'password'"
            autocomplete="current-password"
            custom-input-class="!h-11 !text-base !pe-12"
            :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.CAMPO_SENHA')"
          />
          <button
            type="button"
            data-carteira="mostrar-senha"
            :aria-label="rotuloDoOlho"
            class="absolute bottom-0 flex items-center justify-center rounded-lg end-0 size-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="senhaVisivel = !senhaVisivel"
          >
            <span
              class="size-5"
              :class="senhaVisivel ? 'i-lucide-eye-off' : 'i-lucide-eye'"
              aria-hidden="true"
            />
          </button>
        </div>
        <p class="flex items-center gap-1.5 m-0 text-sm text-n-slate-11">
          <span class="i-lucide-lock size-4 shrink-0" aria-hidden="true" />
          {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.AJUDA_SENHA') }}
        </p>
      </div>
      <p
        v-if="alerta"
        role="alert"
        data-carteira="alerta-do-login"
        class="flex items-start gap-2 p-3 m-0 text-base font-medium rounded-xl bg-n-ruby-2 text-n-ruby-11 ring-1 ring-inset ring-n-ruby-5"
      >
        <span
          class="i-lucide-circle-alert size-5 shrink-0 mt-0.5"
          aria-hidden="true"
        />
        <span>{{ alerta }}</span>
      </p>
    </div>
    <template #footer>
      <div class="flex items-center w-full gap-3">
        <Button
          slate
          faded
          size="lg"
          type="button"
          class="w-full"
          data-carteira="voltar-do-login"
          :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.VOLTAR')"
          @click="dialogo?.close()"
        />
        <Button
          size="lg"
          type="submit"
          class="w-full"
          data-carteira="entrar-no-agger"
          :label="rotuloDeEntrar"
          :is-loading="ocupado"
          :disabled="ocupado"
        />
      </div>
    </template>
  </Dialog>
</template>
