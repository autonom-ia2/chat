<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AcharVaiInterruptor from './AcharVaiInterruptor.vue';

// #2692 — uma empresa na lista (v4, T1; molde CampaignJourney/
// AudienceFoundPerson.vue). Iniciais, nome, "categoria · bairro", o selo de
// chance, o porquê numa frase (nunca cortado), o dono e o WhatsApp chegando ao
// vivo, e à direita o interruptor "Vai / Não vai". O cartão inteiro abre a
// gaveta; não há outro botão. Quem fica de fora mostra o motivo no lugar do
// interruptor; em leitura, uma seta diz que o cartão abre (rodada 2).
// Rodada 3: sem selo de chance (o grupo já diz); o motivo de quem fica de fora
// vai numa linha sob o nome, para não apertar o texto no celular; a empresa já
// mandada pela gaveta mostra "Já está no funil {funil}" no lugar do "Vai".
const props = defineProps({
  empresa: { type: Object, required: true },
  leitura: { type: Boolean, default: false },
  vai: { type: Boolean, default: true },
  pesquisaLigada: { type: Boolean, default: true },
  whatsappLigado: { type: Boolean, default: true },
  // Destaque do mapa: o pino desta empresa foi clicado (ou o cartão).
  destacada: { type: Boolean, default: false },
});
const emit = defineEmits(['abrir', 'alternar']);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.CONFIRA';

const iniciais = computed(() =>
  props.empresa.nome
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(parte => parte[0])
    .join('')
    .toUpperCase()
);
const fora = computed(() => props.empresa.fora);
const esmaecida = computed(() => Boolean(fora.value) || !props.vai);
const temInterruptor = computed(
  () => !fora.value && !props.empresa.mandada && !props.leitura
);
// Rodada 5 (G1): em 390 a chave não tem rótulo; a linha desligada diz
// "Não vai" no lugar do porquê.
const naoVaiNoCelular = computed(() => temInterruptor.value && !props.vai);

const dono = computed(() => {
  const { estado, nome, cargo } = props.empresa.dono;
  if (estado === 'procurando')
    return { texto: t(`${NS}.DONO.PROCURANDO`), girando: true };
  if (estado === 'confirmado') {
    return {
      texto: cargo
        ? t(`${NS}.DONO.CONFIRMADO`, { nome, cargo })
        : t(`${NS}.DONO.CONFIRMADO_SEM_CARGO`, { nome }),
    };
  }
  if (estado === 'possivel')
    return { texto: t(`${NS}.DONO.POSSIVEL`, { nome }) };
  if (estado === 'desligada') return null;
  return { texto: t(`${NS}.DONO.NENHUM`) };
});

const WHATS = {
  conferindo: { chave: 'CONFERINDO', classe: 'text-n-slate-11' },
  tem: { chave: 'TEM', classe: 'text-n-teal-11' },
  sem: { chave: 'SEM', classe: 'text-n-slate-11' },
};
const whats = computed(() => WHATS[props.empresa.whatsapp] || WHATS.sem);

const textoDeFora = computed(() => {
  if (!fora.value) return '';
  const chaves = {
    no_funil: fora.value.funil ? 'NO_FUNIL' : 'NO_FUNIL_SEM_NOME',
    nao_quer: 'NAO_QUER',
    tirou: 'TIROU',
    fechou: 'FECHOU',
  };
  return t(`${NS}.FORA.${chaves[fora.value.motivo]}`, {
    funil: fora.value.funil,
  });
});
</script>

<template>
  <li
    class="relative flex items-start gap-3 py-4 transition"
    :class="[
      esmaecida ? 'opacity-60' : '',
      destacada ? '-mx-3 px-3 rounded-xl bg-n-blue-2 ring-2 ring-n-blue-7' : '',
    ]"
    :data-empresa="empresa.id"
  >
    <button
      type="button"
      class="flex flex-1 min-w-0 gap-3 rounded-xl text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      data-abrir-empresa
      @click="emit('abrir')"
    >
      <span
        class="grid text-sm font-semibold rounded-full shrink-0 size-10 place-items-center"
        :class="
          esmaecida
            ? 'bg-n-slate-3 text-n-slate-10'
            : 'bg-n-blue-3 text-n-blue-11'
        "
        aria-hidden="true"
      >
        {{ iniciais }}
      </span>
      <span class="flex flex-col min-w-0 gap-1">
        <span
          class="flex flex-wrap items-center gap-x-2 gap-y-1"
          :class="{ 'pe-12 md:pe-0': temInterruptor }"
        >
          <span class="text-lg font-semibold break-words text-n-slate-12">
            {{ empresa.nome }}
          </span>
        </span>
        <span class="text-sm text-n-slate-11">
          {{ [empresa.categoria, empresa.bairro].filter(Boolean).join(' · ') }}
        </span>
        <span
          v-if="fora"
          class="text-sm font-medium text-n-slate-11"
          data-motivo-fora
        >
          {{ textoDeFora }}
        </span>
        <span
          v-if="empresa.porque && !fora"
          class="text-base text-n-slate-12"
          :class="{ 'hidden md:inline': naoVaiNoCelular }"
        >
          {{ empresa.porque }}
        </span>
        <span
          v-if="naoVaiNoCelular"
          class="text-base font-medium md:hidden text-n-slate-11"
          data-nao-vai
        >
          {{ $t(`${NS}.NAO_VAI`) }}
        </span>
        <span
          v-if="empresa.mandada"
          class="flex items-center gap-1.5 text-sm font-medium text-n-teal-11"
          data-mandada
        >
          <span class="i-lucide-check size-4" aria-hidden="true" />
          {{ $t(`${NS}.MANDADA`, { funil: empresa.mandada }) }}
        </span>
        <span
          v-if="!fora && (pesquisaLigada || whatsappLigado)"
          class="flex flex-wrap items-center text-sm gap-x-4 gap-y-1"
        >
          <span
            v-if="pesquisaLigada && dono"
            class="flex items-center gap-1.5 text-n-slate-11"
            data-dono
          >
            <span
              class="size-4"
              :class="
                dono.girando
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-user-round'
              "
              aria-hidden="true"
            />
            {{ dono.texto }}
          </span>
          <span
            v-if="whatsappLigado"
            class="flex items-center gap-1.5"
            :class="whats.classe"
            data-whatsapp
          >
            <span
              class="size-4"
              :class="
                empresa.whatsapp === 'conferindo'
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-message-circle'
              "
              aria-hidden="true"
            />
            {{ $t(`${NS}.WHATS.${whats.chave}`) }}
          </span>
        </span>
      </span>
    </button>
    <AcharVaiInterruptor
      v-if="temInterruptor"
      class="absolute top-2.5 md:static md:mt-0"
      :class="destacada ? 'end-3' : 'end-0'"
      :vai="vai"
      :nome="empresa.nome"
      @alternar="emit('alternar')"
    />
    <span
      v-else-if="leitura"
      class="i-lucide-chevron-right size-5 shrink-0 mt-2.5 text-n-slate-10 rtl:rotate-180"
      aria-hidden="true"
    />
  </li>
</template>
