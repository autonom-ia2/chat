<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { soDigitos } from '../../fonte/texto';
import { emailValido } from '../../ficha/validacao';
import { SITUACAO_DO_PROBLEMA, nomeValido } from '../../trazer/contagem';

// #2894 — uma linha da planilha que precisa da pessoa: o problema em palavras
// simples e o conserto ali mesmo (telefone, e-mail, nome, qual duplicada fica).
// Consertou: vira "Pronto ✓". Guardar e Deixar de fora saem como evento.
const props = defineProps({
  problema: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['guardar', 'deixarDeFora', 'reabrir']);

const { t } = useI18n();

const CAMPO_DO_TIPO = {
  telefone: 'telefone',
  sem_contato: 'telefone',
  email: 'email',
  nome: 'nome',
  duplicada: '',
};
const TEXTO_DO_TIPO = {
  telefone: 'RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA.TELEFONE',
  email: 'RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA.EMAIL',
  nome: 'RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA.NOME',
  duplicada: 'RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA.DUPLICADA',
  sem_contato: 'RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA.SEM_CONTATO',
};

const campo = computed(() => CAMPO_DO_TIPO[props.problema.tipo]);
const aberto = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.ABERTO
);

// O telefone errado já aparece no campo; só vale quando a pessoa o conserta.
const telefoneDeInicio = props.problema.valor
  ? `+${soDigitos(props.problema.valor)}`
  : '';
const valor = ref(
  campo.value === 'telefone' ? telefoneDeInicio : props.problema.valor || ''
);

const preenchido = computed(() => {
  if (campo.value === 'telefone') {
    return Boolean(valor.value) && valor.value !== telefoneDeInicio;
  }
  if (campo.value === 'email') return emailValido(valor.value.trim());
  return nomeValido(valor.value);
});

const guardar = () => {
  if (!preenchido.value || props.ocupado) return;
  const texto = campo.value === 'telefone' ? valor.value : valor.value.trim();
  emit('guardar', props.problema.linha, texto);
};

const textoDoProblema = computed(() =>
  t(TEXTO_DO_TIPO[props.problema.tipo], {
    linha: props.problema.linha,
    outraLinha: props.problema.outraLinha,
  })
);
const naPlanilha = computed(() =>
  props.problema.valor && campo.value !== 'telefone'
    ? t('RELACIONAMENTOS_TRAZER.PRECISAM.NA_PLANILHA', {
        valor: props.problema.valor,
      })
    : ''
);
const guardado = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.GUARDADO
);
const doTexto = computed(
  () => campo.value === 'email' || campo.value === 'nome'
);
</script>

<template>
  <li
    :data-linha="problema.linha"
    class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <template v-if="aberto">
      <form class="flex flex-col gap-4" novalidate @submit.prevent="guardar">
        <div class="flex flex-col gap-1">
          <p class="m-0 text-base font-medium text-n-slate-12">
            {{ textoDoProblema }}
          </p>
          <p v-if="naPlanilha" class="m-0 text-sm text-n-slate-11">
            {{ naPlanilha }}
          </p>
        </div>
        <CampoDeTelefone
          v-if="campo === 'telefone'"
          v-model="valor"
          :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.TELEFONE')"
          :rotulo-do-pais="t('RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.PAIS')"
        />
        <Input
          v-else-if="doTexto"
          v-model="valor"
          :label="
            t(
              campo === 'email'
                ? 'RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.EMAIL'
                : 'RELACIONAMENTOS_TRAZER.PRECISAM.CAMPO.NOME'
            )
          "
        />
        <div v-else class="flex flex-wrap gap-3">
          <Button
            v-for="linha in [problema.outraLinha, problema.linha]"
            :key="linha"
            slate
            faded
            type="button"
            class="min-h-11"
            :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.FICAR_COM', { linha })"
            :disabled="ocupado"
            @click="emit('guardar', problema.linha, linha)"
          />
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <Button
            v-if="campo"
            type="submit"
            class="min-h-11"
            :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.GUARDAR')"
            :disabled="!preenchido || ocupado"
          />
          <Button
            ghost
            slate
            type="button"
            data-relacionamentos="deixar-de-fora"
            class="min-h-11"
            :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.DEIXAR_DE_FORA')"
            :disabled="ocupado"
            @click="emit('deixarDeFora', problema.linha)"
          />
        </div>
      </form>
    </template>
    <div v-else class="flex flex-wrap items-center justify-between gap-2">
      <p class="flex items-center gap-2 m-0 text-base text-n-slate-11">
        <span
          class="size-5 shrink-0"
          :class="
            guardado
              ? 'i-lucide-circle-check text-n-teal-11'
              : 'i-lucide-circle-minus'
          "
          aria-hidden="true"
        />
        <span>{{ textoDoProblema }}</span>
        <span class="font-medium text-n-slate-12">
          {{
            t(
              guardado
                ? 'RELACIONAMENTOS_TRAZER.PRECISAM.PRONTO'
                : 'RELACIONAMENTOS_TRAZER.PRECISAM.DEIXADA'
            )
          }}
        </span>
      </p>
      <Button
        ghost
        slate
        type="button"
        data-relacionamentos="voltar-atras"
        class="min-h-11"
        :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.VOLTAR_ATRAS')"
        :aria-label="
          t('RELACIONAMENTOS_TRAZER.PRECISAM.VOLTAR_ATRAS_LINHA', {
            linha: problema.linha,
          })
        "
        :disabled="ocupado"
        @click="emit('reabrir', problema.linha)"
      />
    </div>
  </li>
</template>
