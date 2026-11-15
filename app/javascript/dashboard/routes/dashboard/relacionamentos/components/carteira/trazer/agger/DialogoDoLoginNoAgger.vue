<script setup>
import { ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TituloDoDialogo from '../../../comum/TituloDoDialogo.vue';
import { chaveDaRecusa, codigoDaRecusa } from '../../../../carteira/recusas';

// #2900 (E7.3) — a janela que pede só o login e a senha do Agger, com uma
// frase dizendo para que servem. Quem usa passa `conectar`, que devolve se o
// Agger aceitou; aceito, a janela fecha. Recusado ou sem rede, a frase fica
// dentro da janela e a pessoa tenta de novo. Sem botão desligado: faltando o
// login ou a senha, a janela diz o que falta. A senha não fica guardada aqui
// depois que a janela fecha.
const props = defineProps({
  conectar: { type: Function, required: true },
});

const { t } = useI18n();
const BASE = 'RELACIONAMENTOS_CARTEIRA.AGGER.LOGIN';
const dialogo = useTemplateRef('dialogo');
const login = ref('');
const senha = ref('');
const alerta = ref('');
const ocupado = ref(false);

const limpar = () => {
  senha.value = '';
  alerta.value = '';
  ocupado.value = false;
};

const entrar = async () => {
  if (ocupado.value) return;
  if (!login.value.trim() || !senha.value) {
    alerta.value = t(`${BASE}.FALTA`);
    return;
  }
  ocupado.value = true;
  alerta.value = '';
  try {
    const aceito = await props.conectar({
      login: login.value.trim(),
      senha: senha.value,
    });
    if (aceito) {
      dialogo.value?.close();
      return;
    }
    alerta.value = t(`${BASE}.RECUSADO`);
  } catch (falha) {
    alerta.value = t(chaveDaRecusa(codigoDaRecusa(falha), `${BASE}.NAO_DEU`));
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
    :confirm-button-label="t(`${BASE}.ENTRAR`)"
    :cancel-button-label="t(`${BASE}.VOLTAR`)"
    :is-loading="ocupado"
    :close-on-outside-click="false"
    @confirm="entrar"
    @close="limpar"
  >
    <div data-carteira="login-do-agger" class="flex flex-col gap-4">
      <TituloDoDialogo
        :titulo="t(`${BASE}.TITULO`)"
        :aviso="t(`${BASE}.PARA_QUE`)"
      />
      <Input
        id="carteira-agger-login"
        v-model="login"
        type="text"
        autocomplete="username"
        custom-input-class="!h-11"
        :label="t(`${BASE}.CAMPO_LOGIN`)"
      />
      <Input
        id="carteira-agger-senha"
        v-model="senha"
        type="password"
        autocomplete="current-password"
        custom-input-class="!h-11"
        :label="t(`${BASE}.CAMPO_SENHA`)"
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
