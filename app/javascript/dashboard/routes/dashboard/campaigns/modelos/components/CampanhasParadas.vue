<script setup>
// Campanhas que pararam por causa do modelo (pausado, recusado, alterado ou com
// o tipo mudado). Na lista de campanhas leva ao modelo para resolver; na página
// do modelo leva à campanha.
const props = defineProps({
  campanhas: { type: Array, required: true },
  // Na página do próprio modelo: não repete o nome dele e leva à campanha.
  noModelo: { type: Boolean, default: false },
});

const ACAO = {
  modelo_pausado: 'ABRIR_MODELO',
  modelo_recusado: 'CORRIGIR_MODELO',
  modelo_mudou: 'CONFERIR_CAMPANHA',
  tipo_mudou: 'CONFERIR_CAMPANHA',
};

const destino = campanha =>
  props.noModelo || ACAO[campanha.motivo] === 'CONFERIR_CAMPANHA'
    ? { name: 'campaigns_journey_index' }
    : {
        name:
          campanha.motivo === 'modelo_recusado'
            ? 'modelos_whatsapp_alterar'
            : 'modelos_whatsapp_modelo',
        params: { id: campanha.modeloId },
      };

const rotuloDaAcao = campanha =>
  props.noModelo ? 'VER_CAMPANHA' : ACAO[campanha.motivo];
</script>

<template>
  <section
    data-campanhas-paradas
    class="flex flex-col gap-3 p-5 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
  >
    <h2 class="flex items-center gap-2 m-0 text-base font-semibold text-n-slate-12">
      <span class="i-lucide-circle-pause size-5 text-n-amber-11" aria-hidden="true" />
      {{
        $t(
          'MODELOS_WHATSAPP.PARADAS.TITULO',
          { n: campanhas.length },
          campanhas.length
        )
      }}
    </h2>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="campanha in campanhas"
        :key="campanha.id"
        :data-campanha-parada="campanha.id"
        class="flex flex-wrap items-center justify-between gap-3 p-4 rounded-xl bg-n-solid-1"
      >
        <span class="flex flex-col min-w-0 gap-0.5">
          <span class="text-[0.9375rem] font-semibold break-words text-n-slate-12">
            {{ campanha.nome }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              $t(`MODELOS_WHATSAPP.PARADAS.MOTIVOS.${campanha.motivo}`, {
                modelo: campanha.modeloNome,
              })
            }}
          </span>
        </span>
        <router-link
          :to="destino(campanha)"
          class="inline-flex items-center gap-2 px-4 text-sm font-semibold text-white rounded-xl shrink-0 min-h-11 bg-n-brand hover:brightness-110"
        >
          {{ $t(`MODELOS_WHATSAPP.PARADAS.ACOES.${rotuloDaAcao(campanha)}`) }}
          <span class="i-lucide-arrow-right size-4 rtl:rotate-180" aria-hidden="true" />
        </router-link>
      </li>
    </ul>
  </section>
</template>
