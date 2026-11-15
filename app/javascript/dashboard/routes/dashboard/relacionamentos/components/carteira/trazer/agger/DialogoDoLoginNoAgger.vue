<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
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
const rotuloDeEntrar = computed(() =>
  foraDoAr.value
    ? t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.TENTAR_DE_NOVO')
    : t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.ENTRAR')
);

const limpar = () => {
  senha.value = '';
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
    <div data-carteira="login-do-agger" class="flex flex-col gap-4">
      <TituloDoDialogo
        :titulo="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.TITULO')"
        :aviso="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.PARA_QUE')"
      />
      <Input
        id="carteira-agger-login"
        v-model="login"
        type="text"
        autocomplete="username"
        custom-input-class="!h-11"
        :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.CAMPO_LOGIN')"
      />
      <Input
        id="carteira-agger-senha"
        v-model="senha"
        type="password"
        autocomplete="current-password"
        custom-input-class="!h-11"
        :label="t('RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN.CAMPO_SENHA')"
      />
      <p
        v-if="alerta"
        role="alert"
        data-carteira="alerta-do-login"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ alerta }}
      </p>
    </div>
  </Dialog>
</template>
