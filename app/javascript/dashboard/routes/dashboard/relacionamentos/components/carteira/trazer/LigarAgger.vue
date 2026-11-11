<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CampoDoSeguro from '../CampoDoSeguro.vue';
import { ERROS_DO_LOGIN } from '../../../carteira/useBuscaNoAgger';

// #2897 — "Ligar o Agger". Conta já ligada: uma frase e um botão. Conta ainda
// não ligada: o usuário e a senha que a pessoa já usa lá e UM botão, sempre
// ligado: sem um dos dois, o clique diz o que falta e leva o foco ao campo.
// Nada do que é digitado aqui fica guardado no protótipo.
const props = defineProps({
  ligado: { type: Boolean, default: false },
  entrando: { type: Boolean, default: false },
  erro: { type: String, default: ERROS_DO_LOGIN.NENHUM },
});
const emit = defineEmits(['entrar', 'buscar', 'voltar']);

const { t } = useI18n();
const ta = chave => t(`RELACIONAMENTOS_CARTEIRA.TRAZER.AGGER.${chave}`);
const id = useId();
const ids = {
  usuario: `${id}-usuario`,
  senha: `${id}-senha`,
  senhaSegura: `${id}-senha-segura`,
};

const usuario = ref('');
const senha = ref('');
const senhaVisivel = ref(false);
const falta = ref({ usuario: '', senha: '' });

const semApolices = computed(() => props.erro === ERROS_DO_LOGIN.SEM_APOLICES);
const erroDoLogin = computed(() =>
  props.erro && !semApolices.value ? ta(props.erro) : ''
);

const entrar = async () => {
  if (props.entrando) return;
  falta.value = {
    usuario: usuario.value.trim() ? '' : ta('FALTA_USUARIO'),
    senha: senha.value ? '' : ta('FALTA_SENHA'),
  };
  const primeiro = ['usuario', 'senha'].find(campo => falta.value[campo]);
  if (primeiro) {
    await nextTick();
    document.getElementById(ids[primeiro])?.focus();
    return;
  }
  emit('entrar', { usuario: usuario.value.trim(), senha: senha.value });
};

watch(usuario, () => {
  falta.value = { ...falta.value, usuario: '' };
});
watch(senha, () => {
  falta.value = { ...falta.value, senha: '' };
});
</script>

<template>
  <section
    v-if="ligado"
    data-carteira="agger-ligado"
    class="flex flex-col gap-8"
  >
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ ta('JA_LIGADO') }}
    </h1>
    <p
      v-if="erroDoLogin"
      role="alert"
      data-carteira="agger-erro"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ erroDoLogin }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        data-carteira="agger-trazer"
        size="lg"
        :label="ta('TRAZER_DO_AGGER')"
        :is-loading="entrando"
        :disabled="entrando"
        @click="emit('buscar')"
      />
    </div>
  </section>

  <section
    v-else-if="semApolices"
    data-carteira="agger-sem-apolices"
    class="flex flex-col gap-8"
  >
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-2xl font-bold tracking-tight outline-none md:text-3xl text-n-slate-12"
    >
      {{ ta('SEM_APOLICES') }}
    </h1>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        data-carteira="agger-entendi"
        size="lg"
        :label="t('RELACIONAMENTOS.COMUM.ENTENDI')"
        @click="emit('voltar')"
      />
    </div>
  </section>

  <form
    v-else
    data-carteira="agger-entrar-form"
    class="flex flex-col gap-6"
    novalidate
    @submit.prevent="entrar"
  >
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ ta('ENTRAR_TITULO') }}
    </h1>
    <div class="flex flex-col max-w-md gap-4">
      <CampoDoSeguro
        :id="ids.usuario"
        v-model="usuario"
        type="text"
        autocomplete="off"
        autocapitalize="none"
        spellcheck="false"
        data-carteira="agger-usuario"
        :rotulo="ta('USUARIO')"
        :falta="falta.usuario"
      />
      <div data-carteira="agger-campo-senha" class="flex flex-col gap-1.5">
        <CampoDoSeguro
          :id="ids.senha"
          v-model="senha"
          :type="senhaVisivel ? 'text' : 'password'"
          autocomplete="off"
          data-carteira="agger-senha"
          :rotulo="ta('SENHA')"
          :falta="falta.senha"
          :descrito-por="ids.senhaSegura"
        >
          <template #dentro>
            <!-- O nome do botão não muda: quem diz se a senha está à mostra é o
                 aria-pressed. -->
            <button
              type="button"
              data-carteira="agger-mostrar-senha"
              :aria-label="ta('MOSTRAR_SENHA')"
              :title="ta('MOSTRAR_SENHA')"
              :aria-pressed="senhaVisivel ? 'true' : 'false'"
              class="absolute inset-y-0 inline-flex items-center justify-center p-0 bg-transparent border-0 rounded-lg end-0 size-12 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="senhaVisivel = !senhaVisivel"
            >
              <span
                class="size-5"
                :class="senhaVisivel ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                aria-hidden="true"
              />
            </button>
          </template>
        </CampoDoSeguro>
        <p
          :id="ids.senhaSegura"
          data-carteira="agger-senha-segura"
          class="flex items-start gap-2 m-0 text-sm text-n-slate-11"
        >
          <span
            class="i-lucide-lock size-4 shrink-0 mt-0.5"
            aria-hidden="true"
          />
          {{ ta('SENHA_SEGURA') }}
        </p>
      </div>
      <p class="m-0 text-sm text-n-slate-11">{{ ta('APOIO') }}</p>
    </div>
    <p
      v-if="erroDoLogin"
      role="alert"
      data-carteira="agger-erro"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ erroDoLogin }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        type="submit"
        data-carteira="agger-entrar"
        size="lg"
        :label="ta('ENTRAR')"
        :is-loading="entrando"
        :disabled="entrando"
      />
    </div>
  </form>
</template>
