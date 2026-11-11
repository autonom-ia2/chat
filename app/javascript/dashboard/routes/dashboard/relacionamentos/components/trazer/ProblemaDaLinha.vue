<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { soDigitos } from '../../fonte/texto';
import { emailValido } from '../../ficha/validacao';
import { partesDoEmail } from '../../trazer/emailEmPartes';
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

const formulario = ref(null);
const erro = ref('');
const QUE_FALTA = {
  telefone: 'RELACIONAMENTOS_TRAZER.PRECISAM.QUE_FALTA.TELEFONE',
  email: 'RELACIONAMENTOS_TRAZER.PRECISAM.QUE_FALTA.EMAIL',
  nome: 'RELACIONAMENTOS_TRAZER.PRECISAM.QUE_FALTA.NOME',
};
watch(valor, () => {
  erro.value = '';
});

// Salvar fica sempre ligado: campo sem o que falta não salva, diz o que falta
// e leva o foco ao campo.
const guardar = () => {
  if (props.ocupado) return;
  if (!preenchido.value) {
    erro.value = t('RELACIONAMENTOS_TRAZER.PRECISAM.ERRO_PREENCHER', {
      campo: t(QUE_FALTA[campo.value]),
    });
    formulario.value?.querySelector('input')?.focus();
    return;
  }
  const texto = campo.value === 'telefone' ? valor.value : valor.value.trim();
  emit('guardar', props.problema.linha, texto);
};

// Quem é, em palavras da pessoa: o nome; sem nome, o telefone ou e-mail que
// houver; sem nada, a linha. A linha da planilha vai como apoio, em cinza.
const quem = computed(
  () =>
    props.problema.nome ||
    props.problema.contato ||
    t('RELACIONAMENTOS_TRAZER.PRECISAM.QUEM_SEM_NOME', {
      linha: props.problema.linha,
    })
);
const textoDoProblema = computed(() =>
  t(TEXTO_DO_TIPO[props.problema.tipo], { quem: quem.value })
);
const apoioDaLinha = computed(() =>
  props.problema.tipo === 'duplicada'
    ? t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHAS_DA_PLANILHA', {
        linha: props.problema.linha,
        outraLinha: props.problema.outraLinha,
      })
    : t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHA_DA_PLANILHA', {
        linha: props.problema.linha,
      })
);

// Cada linha repetida mostra o que a distingue da outra: o telefone (ou, sem
// telefone, o e-mail) é o título do cartão; o e-mail vem logo abaixo.
const detalheDaLinha = linha => {
  const dados = props.problema.duplicadas?.find(item => item.linha === linha);
  if (!dados) return null;
  if (dados.telefone) {
    return {
      titulo: dados.telefone,
      email: dados.email ? partesDoEmail(dados.email) : [],
    };
  }
  return {
    titulo: '',
    emailNoTitulo: dados.email
      ? partesDoEmail(dados.email)
      : [t('RELACIONAMENTOS_TRAZER.PRECISAM.SEM_TELEFONE')],
    email: [],
  };
};
const naPlanilha = computed(() =>
  props.problema.valor &&
  campo.value !== 'telefone' &&
  props.problema.tipo !== 'duplicada'
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
      <form
        ref="formulario"
        class="flex flex-col gap-4"
        novalidate
        @submit.prevent="guardar"
      >
        <div class="flex flex-col gap-1">
          <p class="m-0 text-lg font-semibold text-n-slate-12">
            {{ textoDoProblema }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">{{ apoioDaLinha }}</p>
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
        <div v-else class="grid gap-3 sm:grid-cols-2">
          <button
            v-for="linha in [problema.outraLinha, problema.linha]"
            :key="linha"
            type="button"
            :data-opcao="linha"
            :aria-label="
              t('RELACIONAMENTOS_TRAZER.PRECISAM.FICAR_COM', { linha })
            "
            class="flex flex-col items-start w-full gap-1 p-4 border min-h-11 text-start rounded-xl border-n-weak bg-n-alpha-1 hover:enabled:bg-n-alpha-2 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            :disabled="ocupado"
            @click="emit('guardar', problema.linha, linha)"
          >
            <template v-if="detalheDaLinha(linha)">
              <span
                data-relacionamentos="titulo-do-cartao"
                class="text-base font-medium break-words text-n-slate-12 tabular-nums"
              >
                <template v-if="detalheDaLinha(linha).titulo">
                  {{ detalheDaLinha(linha).titulo }}
                </template>
                <template v-else>
                  <template
                    v-for="(parte, posicao) in detalheDaLinha(linha)
                      .emailNoTitulo"
                    :key="posicao"
                  >
                    <wbr v-if="posicao" />{{ parte }}
                  </template>
                </template>
              </span>
              <span
                v-if="detalheDaLinha(linha).email.length"
                class="text-sm break-words text-n-slate-11"
              >
                <template
                  v-for="(parte, posicao) in detalheDaLinha(linha).email"
                  :key="posicao"
                >
                  <wbr v-if="posicao" />{{ parte }}
                </template>
              </span>
            </template>
            <span
              v-else
              data-relacionamentos="titulo-do-cartao"
              class="text-base font-medium text-n-slate-12"
            >
              {{ t('RELACIONAMENTOS_TRAZER.PRECISAM.FICAR_COM', { linha }) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{
                t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHA_DA_PLANILHA', {
                  linha,
                })
              }}
            </span>
            <span
              data-relacionamentos="ficar-com-esta"
              class="flex items-center gap-1 mt-1 text-sm font-medium text-n-blue-11"
            >
              {{ t('RELACIONAMENTOS_TRAZER.PRECISAM.FICAR_COM_ESTA') }}
              <span
                class="i-lucide-arrow-right size-4 rtl:rotate-180"
                aria-hidden="true"
              />
            </span>
          </button>
        </div>
        <p
          v-if="erro"
          data-relacionamentos="erro-do-campo"
          role="alert"
          class="m-0 text-sm font-medium text-n-ruby-11"
        >
          {{ erro }}
        </p>
        <div class="flex flex-wrap items-center gap-3">
          <Button
            v-if="campo"
            type="submit"
            size="lg"
            :label="t('RELACIONAMENTOS_TRAZER.PRECISAM.GUARDAR')"
            :disabled="ocupado"
          />
          <Button
            slate
            faded
            type="button"
            size="lg"
            data-relacionamentos="deixar-de-fora"
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
