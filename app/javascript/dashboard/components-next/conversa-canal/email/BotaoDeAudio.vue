<script setup>
// Microfone da resposta de e-mail (#1786): um toque e a pessoa dita; ao tocar em
// "Pronto", o texto entra onde está o cursor, para revisar antes de enviar (como no
// Claude e no Ditar do Outlook). Gravando, o desenho é o do gravador do WhatsApp
// (GravadorDoWhatsapp): lixeira, ponto vermelho com o tempo, a onda ao vivo e
// pausar/continuar. Sem áudio anexado no e-mail (Rodrigo, 18/10: em e-mail ninguém
// manda gravação). Sem IA de transcrição na conta, o botão não aparece.
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useRecursosDoEmail } from './recursosDoEmail';
import { LIMITE_DO_DITADO, useDitado } from './useDitado';
import { useEmailDaConversa } from './useConversaDeEmail';
import OndaAoVivo from './OndaAoVivo.vue';

// Para onde vai o texto ditado. Padrão: o editor da resposta (enable-insert-events).
// A gaveta "Escrever" (#1809) passa o dela, para não cair na resposta aberta por trás.
const props = defineProps({
  inserir: {
    type: Function,
    default: texto => emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, texto),
  },
});

const { t } = useI18n();
const ditado = useDitado();
const { recursos } = useRecursosDoEmail(
  useMapGetter('getCurrentAccountId').value
);
const podeDitar = computed(() => recursos.value.ditado);

const ditar = async () => {
  await ditado.iniciar();
  if (ditado.erro.value === 'microfone') {
    useAlert(t('CONVERSA_CANAL.EMAIL.SEM_MICROFONE'));
  }
};

const pararEInserir = async () => {
  const texto = await ditado.parar();
  if (texto) {
    // Entra no ponto do cursor, com um espaço no fim para o que vier depois não grudar.
    props.inserir(`${texto} `);
    return;
  }
  if (ditado.erro.value) {
    useAlert(
      ditado.erro.value === 'falhou'
        ? t('CONVERSA_CANAL.EMAIL.DITADO_FALHOU')
        : ditado.erro.value
    );
  }
};

// No teto de tempo o ditado para e o texto entra, como no "Pronto".
watch(ditado.segundos, valor => {
  if (valor >= LIMITE_DO_DITADO) pararEInserir();
});
// Fechar a resposta (ou trocar de conversa, que fecha) não deixa o microfone ligado
// escondido: o que estava sendo ditado é descartado.
const { respostaAberta } = useEmailDaConversa();
watch(respostaAberta, aberta => {
  if (!aberta) ditado.cancelar();
});

const pausado = computed(() => ditado.estado.value === 'pausado');
const gravando = computed(() =>
  ['ouvindo', 'pausado'].includes(ditado.estado.value)
);

const BOTAO =
  'grid place-content-center !size-9 rounded-full flex-shrink-0 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12';

const tempo = computed(() => {
  const s = ditado.segundos.value;
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
});
</script>

<template>
  <div
    v-if="gravando"
    class="flex items-center gap-1.5 h-11 ps-1 pe-1 rounded-full bg-n-alpha-1 border border-n-weak"
    role="group"
    :aria-label="t('CONVERSA_CANAL.EMAIL.OUVINDO', { tempo })"
    data-ditando
  >
    <button
      type="button"
      data-livre
      :class="BOTAO"
      :aria-label="t('CONVERSA_CANAL.EMAIL.CANCELAR_DITADO')"
      :title="t('CONVERSA_CANAL.EMAIL.CANCELAR_DITADO')"
      data-cancelar-ditado
      @click="ditado.cancelar"
    >
      <Icon icon="i-ph-trash" class="size-5" />
    </button>
    <span class="flex items-center gap-2 flex-shrink-0 ps-0.5">
      <span
        class="size-2.5 rounded-full"
        :class="pausado ? 'bg-n-slate-8' : 'bg-n-ruby-9 animate-pulse'"
        aria-hidden="true"
      />
      <span class="text-[15px] tabular-nums text-n-slate-12" aria-live="off">
        {{ tempo }}
      </span>
    </span>
    <div
      class="w-40 max-sm:w-20 h-7 flex-shrink min-w-0"
      :class="pausado ? 'text-n-slate-7' : 'text-n-slate-10'"
    >
      <OndaAoVivo :fluxo="ditado.fluxo.value" :pausado="pausado" />
    </div>
    <button
      type="button"
      data-livre
      class="grid place-content-center !size-9 rounded-full flex-shrink-0 text-n-ruby-11 hover:bg-n-ruby-3"
      :class="{ 'bg-n-ruby-3': pausado }"
      :aria-label="
        pausado
          ? t('CONVERSA_CANAL.EMAIL.CONTINUAR_DITADO')
          : t('CONVERSA_CANAL.EMAIL.PAUSAR_DITADO')
      "
      :title="
        pausado
          ? t('CONVERSA_CANAL.EMAIL.CONTINUAR_DITADO')
          : t('CONVERSA_CANAL.EMAIL.PAUSAR_DITADO')
      "
      data-pausar-ditado
      @click="ditado.pausarOuContinuar"
    >
      <Icon
        :icon="pausado ? 'i-ph-microphone-fill' : 'i-ph-pause-fill'"
        class="size-5"
      />
    </button>
    <button
      type="button"
      data-livre
      class="inline-flex items-center gap-1.5 !h-9 !px-3.5 rounded-full flex-shrink-0 !bg-n-brand !text-white text-sm font-medium hover:brightness-110"
      :title="t('CONVERSA_CANAL.EMAIL.PRONTO_DICA')"
      data-parar-ditado
      @click="pararEInserir"
    >
      <Icon icon="i-lucide-check" class="size-4" />
      {{ t('CONVERSA_CANAL.EMAIL.PARAR_E_ESCREVER') }}
    </button>
  </div>
  <div
    v-else-if="ditado.estado.value === 'transcrevendo'"
    class="flex items-center gap-2 h-11 px-4 rounded-full bg-n-alpha-1 border border-n-weak text-sm text-n-slate-11"
    role="status"
    data-ditando
  >
    <Icon icon="i-lucide-loader-circle" class="size-4 animate-spin" />
    {{ t('CONVERSA_CANAL.EMAIL.TRANSCREVENDO') }}
  </div>
  <button
    v-else-if="podeDitar"
    type="button"
    :aria-label="t('CONVERSA_CANAL.EMAIL.DITAR')"
    :title="t('CONVERSA_CANAL.EMAIL.DITAR')"
    data-ditar
    @click="ditar"
  >
    <Icon icon="i-ph-microphone" class="size-[22px]" />
  </button>
</template>
