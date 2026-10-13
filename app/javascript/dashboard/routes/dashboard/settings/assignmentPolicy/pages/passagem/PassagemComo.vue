<script setup>
import { computed, ref } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import PassagemOpcao from './PassagemOpcao.vue';
import {
  ESPERAS_EM_MINUTOS,
  faltaParaQuem,
  minutosDe,
  nomeDe,
  podeFicarSemResposta,
} from './passagem';

// #1385 — como a conversa chega à pessoa: na hora, ou com convite. O que acontece com todos fora está dito na própria
// opção (o "só online" não é escolha: a tela sempre salva com ele). Com convite, "E se ninguém aceitar?" fica fechado
// numa frase com "Alterar". A regra antiga, que entrega para quem está fora, aparece como aviso e é corrigida ao salvar.
const props = defineProps({
  nome: { type: String, required: true },
  equipe: { type: Array, default: () => [] },
  todas: { type: Array, default: () => [] },
  mostrarErros: { type: Boolean, default: false },
});

const regra = defineModel({ type: Object, required: true });

const { t } = useI18n();
const C = 'CRM_KANBAN.PASSAGEM.COMO';

const mudar = campos => {
  regra.value = { ...regra.value, ...campos };
};
const jeito = computed({
  get: () => regra.value.handoff_mode,
  set: valor => mudar({ handoff_mode: valor }),
});
const seNinguem = computed({
  get: () => regra.value.escalation_action,
  set: valor => mudar({ escalation_action: valor }),
});
const minutos = computed({
  get: () => minutosDe(regra.value),
  set: valor => mudar({ pickup_threshold_seconds: Number(valor) * 60 }),
});
const outra = computed({
  get: () => regra.value.escalation_user_id || '',
  set: valor => mudar({ escalation_user_id: Number(valor) || null }),
});
const nomeDaOutra = computed(() =>
  nomeDe(props.todas, regra.value.escalation_user_id)
);
const chaveDaEspera = computed(() => {
  if (seNinguem.value !== 'escalate') return `${C}.ESPERA_AVISA`;
  return nomeDaOutra.value ? `${C}.ESPERA_PASSA` : `${C}.ESPERA_PASSA_SEM`;
});

// Um tempo salvo fora da lista (ex.: 7 min, da tela antiga) continua na lista para não sumir.
const opcoesDeEspera = computed(() => {
  const lista = ESPERAS_EM_MINUTOS.includes(minutos.value)
    ? ESPERAS_EM_MINUTOS
    : [...ESPERAS_EM_MINUTOS, minutos.value].sort((a, b) => a - b);
  return lista.map(valor => ({
    value: valor,
    label: t(`${C}.MINUTOS`, { n: valor }),
  }));
});
const opcoesDePessoa = computed(() => {
  const lista = props.equipe.map(item => ({
    value: item.id,
    label: item.name,
  }));
  const atual = regra.value.escalation_user_id;
  if (atual && !props.equipe.some(item => item.id === atual)) {
    const fora = props.todas.find(item => item.id === atual);
    lista.push({
      value: atual,
      label: t('CRM_KANBAN.PASSAGEM.QUEM.FORA_DA_EQUIPE', {
        nome: fora?.name || atual,
      }),
    });
  }
  return lista;
});
const falta = computed(() => props.mostrarErros && faltaParaQuem(regra.value));
const antiga = computed(() => podeFicarSemResposta(regra.value));
const abriuEspera = ref(false);
const esperaAberta = computed(() => abriuEspera.value || falta.value);
</script>

<template>
  <section class="flex flex-col gap-5" :aria-labelledby="`${nome}-como`">
    <h2 :id="`${nome}-como`" class="mb-0 text-lg font-semibold text-n-slate-12">
      {{ t(`${C}.TITULO`) }}
    </h2>

    <div
      role="radiogroup"
      :aria-labelledby="`${nome}-como`"
      class="grid gap-3 sm:grid-cols-2"
    >
      <PassagemOpcao
        v-model="jeito"
        :name="`${nome}-jeito`"
        value="r2_direct"
        icone="i-lucide-send"
        :titulo="t(`${C}.NA_HORA`)"
        :descricao="t(`${C}.NA_HORA_DESC`)"
      />
      <PassagemOpcao
        v-model="jeito"
        :name="`${nome}-jeito`"
        value="r3_invite"
        icone="i-lucide-bell-ring"
        :titulo="t(`${C}.CONVITE`)"
        :descricao="t(`${C}.CONVITE_DESC`)"
      />
    </div>

    <p
      v-if="antiga"
      data-como-antiga
      class="mb-0 flex items-start gap-2 rounded-xl border border-dashed border-n-amber-8 bg-n-amber-2 px-3 py-2.5 text-[0.9375rem] text-n-slate-12"
    >
      <span
        class="i-lucide-shield-check mt-0.5 size-4 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{ t('CRM_KANBAN.PASSAGEM.ANTIGA.AO_SALVAR') }}
    </p>

    <section
      v-if="jeito === 'r3_invite'"
      data-como-espera
      :aria-labelledby="`${nome}-espera`"
      class="flex flex-col gap-4 rounded-2xl border bg-n-solid-1 p-4 sm:p-5"
      :class="falta ? 'border-n-ruby-8' : 'border-n-weak'"
    >
      <div class="flex items-center gap-3">
        <span
          class="grid size-10 shrink-0 place-items-center rounded-2xl bg-n-iris-3 text-n-iris-11"
          aria-hidden="true"
        >
          <span class="i-lucide-timer size-5" />
        </span>
        <h3
          :id="`${nome}-espera`"
          class="mb-0 min-w-0 flex-1 text-[0.9375rem] font-semibold text-n-slate-12"
        >
          {{ t(`${C}.ESPERA_TITULO`) }}
        </h3>
        <Button
          v-if="!esperaAberta"
          :label="t('CRM_KANBAN.PASSAGEM.ALTERAR')"
          :aria-label="
            t('CRM_KANBAN.PASSAGEM.ALTERAR_PARTE', {
              parte: t(`${C}.ESPERA_TITULO`),
            })
          "
          icon="i-lucide-pencil"
          slate
          faded
          class="!min-h-11 shrink-0"
          @click="abriuEspera = true"
        />
      </div>
      <I18nT
        v-if="!esperaAberta"
        :keypath="chaveDaEspera"
        tag="p"
        scope="global"
        class="-mt-2 mb-0 text-[0.9375rem] leading-6 text-n-slate-12 sm:ps-[3.25rem]"
      >
        <template #minutos>
          <strong class="font-semibold">{{
            t(`${C}.MINUTOS`, { n: minutos })
          }}</strong>
        </template>
        <template #nome>
          <strong class="font-semibold">{{ nomeDaOutra }}</strong>
        </template>
      </I18nT>

      <div v-if="esperaAberta" class="flex flex-col gap-4">
        <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
          <span class="text-[0.9375rem] font-semibold text-n-slate-12">{{
            t(`${C}.ESPERA_TEMPO`)
          }}</span>
          <ChoiceSelect
            v-model="minutos"
            :options="opcoesDeEspera"
            :aria-label="t(`${C}.ESPERA_CAMPO`)"
            class="w-40 [&>button]:!h-11"
          />
        </div>
        <div class="flex flex-col gap-2">
          <span
            :id="`${nome}-depois`"
            class="text-[0.9375rem] font-semibold text-n-slate-12"
          >
            {{ t(`${C}.ESPERA_DEPOIS`) }}
          </span>
          <div
            role="radiogroup"
            :aria-labelledby="`${nome}-depois`"
            class="grid gap-3 sm:grid-cols-2"
          >
            <PassagemOpcao
              v-model="seNinguem"
              :name="`${nome}-se-ninguem`"
              value="renotify"
              :titulo="t(`${C}.AVISAR_DE_NOVO`)"
              :descricao="t(`${C}.AVISAR_DE_NOVO_DESC`)"
            />
            <PassagemOpcao
              v-model="seNinguem"
              :name="`${nome}-se-ninguem`"
              value="escalate"
              :titulo="t(`${C}.PASSAR_OUTRA`)"
              :descricao="t(`${C}.PASSAR_OUTRA_DESC`)"
            />
          </div>
        </div>
        <div v-if="seNinguem === 'escalate'" class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">{{
            t(`${C}.OUTRA_CAMPO`)
          }}</span>
          <ChoiceSelect
            v-model="outra"
            :options="opcoesDePessoa"
            :aria-label="t(`${C}.OUTRA_CAMPO`)"
            :placeholder="t('CRM_KANBAN.PASSAGEM.QUEM.ESCOLHA')"
            :invalid="falta"
            class="w-full sm:max-w-sm [&>button]:!h-11"
          />
          <p
            v-if="falta"
            role="alert"
            class="mb-0 flex items-center gap-2 text-sm font-medium text-n-ruby-11"
          >
            <span
              class="i-lucide-circle-alert size-4 shrink-0"
              aria-hidden="true"
            />
            {{ t('CRM_KANBAN.PASSAGEM.FALTA_PESSOA') }}
          </p>
        </div>
      </div>

      <p
        class="mb-0 flex items-center gap-2 border-t border-n-weak pt-3 text-sm text-n-slate-11"
      >
        <span class="i-lucide-clock size-4 shrink-0" aria-hidden="true" />
        {{ t(`${C}.VALE_24H`) }}
      </p>
    </section>
  </section>
</template>
