<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import Button from 'dashboard/components-next/button/Button.vue';
import api from '../api/modelosWhatsapp';

// Campanhas que pararam por causa do modelo (pausado, recusado, alterado, com
// o tipo mudado…). Na lista de campanhas leva ao modelo para resolver; na
// página do modelo leva à campanha. "Retomar" (campaign_manage) confere o
// modelo de novo. Só fica ligado com o modelo aprovado e igual ao que a campanha
// guardou (`podeRetomar`, conferido no servidor); antes disso, "Corrija o modelo
// primeiro" com o link para ele.
const props = defineProps({
  campanhas: { type: Array, required: true },
  // Na página do próprio modelo: não repete o nome dele e leva à campanha.
  noModelo: { type: Boolean, default: false },
});

const emit = defineEmits(['retomada']);
const { t } = useI18n();

const ACAO = {
  modelo_pausado: 'ABRIR_MODELO',
  modelo_em_analise: 'ABRIR_MODELO',
  modelo_recusado: 'CORRIGIR_MODELO',
};

const destino = campanha =>
  props.noModelo || !campanha.modeloId || !ACAO[campanha.motivo]
    ? { name: 'campaigns_journey_index' }
    : {
        name:
          campanha.motivo === 'modelo_recusado'
            ? 'modelos_whatsapp_alterar'
            : 'modelos_whatsapp_modelo',
        params: { id: campanha.modeloId },
      };

const rotuloDaAcao = campanha => {
  if (props.noModelo) return 'VER_CAMPANHA';
  if (!campanha.modeloId) return 'CONFERIR_CAMPANHA';
  return ACAO[campanha.motivo] || 'CONFERIR_CAMPANHA';
};

// Retomar é de quem gerencia campanhas (CampaignPolicy#update?).
const usuario = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const gerenciaCampanhas = computed(() =>
  getUserPermissions(usuario.value, contaId.value).some(permissao =>
    ['administrator', 'campaign_manage'].includes(permissao)
  )
);

const retomando = ref(null);
const retomar = async campanha => {
  retomando.value = campanha.pausaId;
  try {
    await api.retomarCampanha(campanha.pausaId);
    useAlert(t('MODELOS_WHATSAPP.PARADAS.RETOMADA', { nome: campanha.nome }));
    emit('retomada', campanha);
  } catch (erro) {
    useAlert(
      erro.codigo === 'campaign_journey.pause_not_resumable'
        ? t('MODELOS_WHATSAPP.PARADAS.NAO_RETOMOU')
        : t('MODELOS_WHATSAPP.PARADAS.RETOMAR_FALHOU')
    );
  } finally {
    retomando.value = null;
  }
};
</script>

<template>
  <section
    data-campanhas-paradas
    class="flex flex-col gap-3 p-5 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
  >
    <h2
      class="flex items-center gap-2 m-0 text-base font-semibold text-n-slate-12"
    >
      <span
        class="i-lucide-circle-pause size-5 text-n-amber-11"
        aria-hidden="true"
      />
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
        :key="campanha.pausaId || campanha.id"
        :data-campanha-parada="campanha.id"
        class="flex flex-wrap items-center justify-between gap-3 p-4 rounded-xl bg-n-solid-1"
      >
        <span class="flex flex-col min-w-0 gap-0.5">
          <span
            class="text-[0.9375rem] font-semibold break-words text-n-slate-12"
          >
            {{ campanha.nome }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              $t(`MODELOS_WHATSAPP.PARADAS.MOTIVOS.${campanha.motivo}`, {
                modelo: campanha.modeloNome,
              })
            }}
          </span>
          <span
            v-if="
              gerenciaCampanhas && campanha.pausaId && !campanha.podeRetomar
            "
            data-corrija-primeiro
            class="inline-flex flex-wrap items-center gap-x-1 text-sm font-medium text-n-amber-11"
          >
            {{ $t('MODELOS_WHATSAPP.PARADAS.CORRIJA_PRIMEIRO') }}
            <router-link
              v-if="campanha.modeloId"
              :to="{
                name: 'modelos_whatsapp_modelo',
                params: { id: campanha.modeloId },
              }"
              class="inline-flex items-center underline min-h-11 text-n-blue-11"
            >
              {{
                $t('MODELOS_WHATSAPP.PARADAS.VER_MODELO', {
                  modelo: campanha.modeloNome,
                })
              }}
            </router-link>
          </span>
        </span>
        <span class="flex flex-wrap items-center gap-2 shrink-0">
          <Button
            v-if="gerenciaCampanhas && campanha.pausaId"
            data-retomar
            :label="$t('MODELOS_WHATSAPP.PARADAS.ACOES.RETOMAR')"
            icon="i-lucide-play"
            color="slate"
            variant="faded"
            class="!min-h-11 !rounded-xl"
            :is-loading="retomando === campanha.pausaId"
            :disabled="!campanha.podeRetomar"
            @click="retomar(campanha)"
          />
          <router-link
            :to="destino(campanha)"
            class="inline-flex items-center gap-2 px-4 text-sm font-semibold text-white rounded-xl min-h-11 bg-n-brand hover:brightness-110"
          >
            {{ $t(`MODELOS_WHATSAPP.PARADAS.ACOES.${rotuloDaAcao(campanha)}`) }}
            <span
              class="i-lucide-arrow-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </router-link>
        </span>
      </li>
    </ul>
  </section>
</template>
