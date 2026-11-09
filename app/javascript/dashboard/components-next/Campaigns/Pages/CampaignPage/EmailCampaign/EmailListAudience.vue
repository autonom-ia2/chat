<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import EmailListsAPI from 'dashboard/api/emailLists';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// G52 (#2760) — "Quem recebe" da campanha de e-mail: a planilha de sempre ou
// uma lista de e-mail da conta. A lista vale na hora do envio: quem estiver
// nela naquela hora recebe; quem pediu para não receber fica de fora.
defineProps({
  disabled: { type: Boolean, default: false },
  invalid: { type: Boolean, default: false },
});

const modo = defineModel('modo', { type: String, default: 'planilha' });
const listaId = defineModel('listaId', { type: Number, default: null });

const { t } = useI18n();
// O aviso de "escolha uma lista", ligado ao campo por aria-describedby.
const ERRO_ID = 'email-list-audience-erro';

const listas = ref(null);
const erroAoCarregar = ref(false);
const criando = ref(false);
const nome = ref('');
const erroAoCriar = ref('');
const salvando = ref(false);

const carregar = async () => {
  erroAoCarregar.value = false;
  try {
    const { data } = await EmailListsAPI.index();
    listas.value = data || [];
  } catch {
    erroAoCarregar.value = true;
  }
};
onMounted(carregar);

const pessoas = lista =>
  t('EMAIL_LISTS.PESSOAS', { n: lista.contatos_count }, lista.contatos_count);

const opcoes = computed(() =>
  (listas.value || []).map(lista => ({
    value: lista.id,
    label: lista.name,
    hint: pessoas(lista),
  }))
);
const escolhida = computed(() =>
  (listas.value || []).find(lista => lista.id === listaId.value)
);
const semEmail = computed(
  () =>
    escolhida.value &&
    escolhida.value.recebem_count < escolhida.value.contatos_count
);

const erroDoNome = erros => {
  if (erros?.name?.includes('taken')) return t('EMAIL_LISTS.NOME_REPETIDO');
  if (erros?.name?.length) return t('EMAIL_LISTS.NOME_INVALIDO');
  return t('EMAIL_LISTS.FALHOU_CRIAR');
};

const criar = async () => {
  if (!nome.value.trim() || salvando.value) return;
  salvando.value = true;
  erroAoCriar.value = '';
  try {
    const { data } = await EmailListsAPI.create(nome.value.trim());
    listas.value = [...(listas.value || []), data];
    listaId.value = data.id;
    criando.value = false;
    nome.value = '';
  } catch (error) {
    erroAoCriar.value = erroDoNome(error?.response?.data?.errors);
  } finally {
    salvando.value = false;
  }
};

const cancelar = () => {
  criando.value = false;
  nome.value = '';
  erroAoCriar.value = '';
};
</script>

<template>
  <div class="flex flex-col gap-2" data-email-list-audience>
    <span
      id="email-list-audience-label"
      class="text-sm font-medium text-n-slate-12"
    >
      {{ t('EMAIL_LISTS.QUEM_RECEBE') }}
    </span>
    <div
      role="group"
      aria-labelledby="email-list-audience-label"
      class="flex flex-wrap gap-2"
    >
      <Button
        type="button"
        data-modo="planilha"
        :label="t('EMAIL_LISTS.PLANILHA')"
        icon="i-lucide-sheet"
        :variant="modo === 'planilha' ? 'solid' : 'outline'"
        color="slate"
        class="min-h-11"
        :aria-pressed="modo === 'planilha'"
        :disabled="disabled"
        @click="modo = 'planilha'"
      />
      <Button
        type="button"
        data-modo="lista"
        :label="t('EMAIL_LISTS.LISTA')"
        icon="i-lucide-list"
        :variant="modo === 'lista' ? 'solid' : 'outline'"
        color="slate"
        class="min-h-11"
        :aria-pressed="modo === 'lista'"
        :disabled="disabled"
        @click="modo = 'lista'"
      />
    </div>

    <template v-if="modo === 'lista'">
      <p
        v-if="erroAoCarregar"
        class="mb-0 text-xs text-n-ruby-11"
        data-listas-erro
      >
        {{ t('EMAIL_LISTS.FALHOU_CARREGAR') }}
      </p>
      <ChoiceSelect
        v-else-if="opcoes.length"
        v-model="listaId"
        class="w-full"
        :aria-label="t('EMAIL_LISTS.ESCOLHA')"
        :placeholder="t('EMAIL_LISTS.ESCOLHA')"
        :options="opcoes"
        :invalid="invalid"
        :described-by="invalid ? ERRO_ID : undefined"
        :disabled="disabled"
      />
      <p
        v-else-if="listas && !criando"
        class="mb-0 text-xs text-n-slate-11"
        data-sem-lista
      >
        {{ t('EMAIL_LISTS.SEM_LISTA') }}
      </p>

      <p
        v-if="invalid"
        :id="ERRO_ID"
        class="mb-0 text-xs text-n-ruby-9"
        data-lista-obrigatoria
      >
        {{ t('EMAIL_LISTS.ESCOLHA_ERRO') }}
      </p>

      <div v-if="criando" class="flex flex-col gap-2" data-criar-lista>
        <Input
          v-model="nome"
          :label="t('EMAIL_LISTS.NOME')"
          :placeholder="t('EMAIL_LISTS.NOME_PLACEHOLDER')"
          :message="erroAoCriar"
          :message-type="erroAoCriar ? 'error' : 'info'"
          @input="erroAoCriar = ''"
          @keydown.enter.prevent="criar"
        />
        <div class="flex flex-wrap gap-2">
          <Button
            type="button"
            data-confirmar-lista
            :label="t('EMAIL_LISTS.CRIAR_CONFIRMAR')"
            size="sm"
            class="min-h-11"
            :is-loading="salvando"
            :disabled="!nome.trim() || salvando"
            @click="criar"
          />
          <Button
            type="button"
            :label="t('EMAIL_LISTS.CANCELAR')"
            variant="faded"
            color="slate"
            size="sm"
            class="min-h-11"
            @click="cancelar"
          />
        </div>
      </div>
      <Button
        v-else-if="!erroAoCarregar && listas"
        type="button"
        data-criar-lista-abrir
        :label="t('EMAIL_LISTS.CRIAR')"
        icon="i-lucide-plus"
        variant="link"
        size="sm"
        class="self-start min-h-11"
        :disabled="disabled"
        @click="criando = true"
      />

      <div
        v-if="escolhida"
        class="px-3 py-2 rounded-xl bg-n-alpha-2"
        data-lista-escolhida
      >
        <p class="mb-1 text-sm font-medium text-n-slate-12">
          {{ pessoas(escolhida) }}
          <template v-if="semEmail">
            ·
            {{
              t(
                'EMAIL_LISTS.COM_EMAIL',
                { n: escolhida.recebem_count },
                escolhida.recebem_count
              )
            }}
          </template>
        </p>
        <p class="mb-0 text-xs text-n-slate-11">{{ t('EMAIL_LISTS.REGRA') }}</p>
      </div>
    </template>
  </div>
</template>
