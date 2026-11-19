<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import DialogoDeConfirmacao from '../carteira/DialogoDeConfirmacao.vue';

// #3071 — pôr e tirar etiqueta na ficha: o diálogo abre com as etiquetas da
// conta (com a cor) e as que a pessoa tem já marcadas. Marcar põe, desmarcar
// tira; "Salvar etiquetas" emite `salvar` com a lista inteira que ela passa a
// ter (o servidor troca a lista toda, como a ficha antiga). Sem mudança, só
// fecha. A etiqueta que a pessoa tem e a conta já apagou aparece marcada, com o
// aviso: desmarcar tira, mas ela não volta. Quem usa fecha (`fechar`) quando
// deu certo, ou passa a frase em `alerta` e o diálogo continua aberto.
const props = defineProps({
  pessoa: { type: Object, required: true },
  // () => Promise<[{ nome, cor }]>: as etiquetas da conta.
  carregar: { type: Function, required: true },
  salvando: { type: Boolean, default: false },
  alerta: { type: String, default: '' },
});
const emit = defineEmits(['salvar']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const daConta = ref([]);
const escolhidas = ref([]);

const ET = 'RELACIONAMENTOS_FICHA.ETIQUETAS';
const nome = computed(() => props.pessoa.name);

const opcoes = computed(() => {
  const nomesDaConta = new Set(daConta.value.map(item => item.nome));
  const soDaPessoa = (props.pessoa.labels ?? [])
    .filter(etiqueta => !nomesDaConta.has(etiqueta))
    .map(etiqueta => ({ nome: etiqueta, cor: null, apagada: true }));
  return [...daConta.value, ...soDaPessoa];
});

const marcada = etiqueta => escolhidas.value.includes(etiqueta);
const alternar = etiqueta => {
  escolhidas.value = marcada(etiqueta)
    ? escolhidas.value.filter(item => item !== etiqueta)
    : [...escolhidas.value, etiqueta];
};

const mudou = () => {
  const antes = new Set(props.pessoa.labels ?? []);
  return (
    antes.size !== escolhidas.value.length ||
    escolhidas.value.some(etiqueta => !antes.has(etiqueta))
  );
};

const abrir = async () => {
  try {
    daConta.value = await props.carregar();
  } catch {
    useAlert(t(`${ET}.NAO_CARREGOU`));
    return;
  }
  escolhidas.value = [...(props.pessoa.labels ?? [])];
  dialogo.value?.abrir();
};

const fechar = () => dialogo.value?.fechar();

const salvar = () => {
  if (props.salvando) return;
  if (!opcoes.value.length || !mudou()) {
    fechar();
    return;
  }
  emit('salvar', [...escolhidas.value]);
};

defineExpose({ abrir, fechar });
</script>

<template>
  <DialogoDeConfirmacao
    ref="dialogo"
    marca="dialogo-etiquetas"
    tipo="edit"
    :titulo="t(`${ET}.TITULO`, { nome })"
    :aviso="opcoes.length ? t(`${ET}.AVISO`, { nome }) : ''"
    :confirmar="
      opcoes.length ? t(`${ET}.SALVAR`) : t('RELACIONAMENTOS.COMUM.FECHAR')
    "
    :voltar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :ocupado="salvando"
    :alerta="alerta"
    @confirmar="salvar"
  >
    <p
      v-if="!opcoes.length"
      data-relacionamentos="sem-etiquetas"
      class="m-0 text-base text-n-slate-11"
    >
      {{ t(`${ET}.SEM_ETIQUETAS`) }}
    </p>
    <ul
      v-else
      data-relacionamentos="etiquetas-da-conta"
      :aria-label="t(`${ET}.TITULO`, { nome })"
      class="flex flex-col p-1 m-0 overflow-y-auto list-none border rounded-xl max-h-72 border-n-weak"
    >
      <li v-for="etiqueta in opcoes" :key="etiqueta.nome">
        <label
          class="flex items-center gap-3 px-3 rounded-lg cursor-pointer min-h-11 hover:bg-n-alpha-1"
          :class="{ 'bg-n-alpha-1': marcada(etiqueta.nome) }"
        >
          <Checkbox
            :model-value="marcada(etiqueta.nome)"
            :data-etiqueta="etiqueta.nome"
            @change="alternar(etiqueta.nome)"
          />
          <span
            class="rounded-full size-2.5 shrink-0 bg-n-slate-8"
            :style="etiqueta.cor ? { backgroundColor: etiqueta.cor } : {}"
            aria-hidden="true"
          />
          <span class="min-w-0 text-base truncate text-n-slate-12">
            {{ etiqueta.nome }}
          </span>
          <span
            v-if="etiqueta.apagada"
            data-relacionamentos="etiqueta-apagada"
            class="text-sm text-n-slate-11 shrink-0"
          >
            {{ t(`${ET}.APAGADA_DA_CONTA`) }}
          </span>
        </label>
      </li>
    </ul>
  </DialogoDeConfirmacao>
</template>
