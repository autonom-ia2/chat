<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import {
  comMaiuscula,
  diasDoCanal,
  horarioEmTexto,
} from 'dashboard/helper/horarioEmTexto';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper';
import { INBOX_PERMISSIONS } from 'dashboard/constants/permissions';
import { chaveDoTipoDaCaixa } from 'dashboard/routes/dashboard/autonomia/agentes/utils/canais';

// #1619 (flag `horario_unico_caixa`) — "Horário dos canais" em CRM › SLA, só leitura: o horário de
// cada canal mora na tela do canal (Configurações › Caixas › Horário de funcionamento), que é a
// única fonte da IA, da mensagem de fora do horário e do SLA. Aqui só mostra e leva até lá.
const { t } = useI18n();
const NS = 'HORARIO_DO_CANAL.SLA';

const caixas = useMapGetter('inboxes/getInboxes');
// O fuso que o servidor devolve nas caixas: com a flag, é o mesmo em todas (o da conta, ou o padrão do CRM).
const fuso = computed(() =>
  rotuloDoFuso((caixas.value || []).find(caixa => caixa.timezone)?.timezone)
);

// O link só para quem abre a tela do canal (meta.permissions de settings_inbox_show).
const usuario = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const podeAbrirCanal = computed(() =>
  hasPermissions(
    ['administrator', ...INBOX_PERMISSIONS],
    getUserPermissions(usuario.value, contaId.value)
  )
);

const linhas = computed(() =>
  (caixas.value || []).map(caixa => {
    const chave = chaveDoTipoDaCaixa(caixa);
    const texto = horarioEmTexto(diasDoCanal(caixa), t);
    return {
      id: caixa.id,
      nome: caixa.name,
      tipo: chave ? t(`AGENTS.JORNADA.ONDE_QUANDO.TIPO.${chave}`) : '',
      texto: comMaiuscula(texto),
      rota: {
        name: 'settings_inbox_show',
        params: { inboxId: caixa.id, tab: 'business-hours' },
      },
    };
  })
);
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-base font-medium text-n-slate-12">
        {{ t(`${NS}.CANAIS_TITULO`) }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">
        {{
          fuso
            ? t(`${NS}.CANAIS_TEXTO`, { fuso })
            : t(`${NS}.CANAIS_TEXTO_SEM_FUSO`)
        }}
      </p>
    </div>

    <p v-if="!linhas.length" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.SEM_CANAIS`) }}
    </p>
    <ul
      v-else
      class="flex flex-col p-0 m-0 list-none border divide-y rounded-xl border-n-weak divide-n-weak"
    >
      <li
        v-for="linha in linhas"
        :key="linha.id"
        data-canal
        class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 px-4 py-3"
      >
        <div class="min-w-0">
          <p
            class="flex flex-wrap items-center gap-2 m-0 text-sm font-medium text-n-slate-12"
          >
            <span class="min-w-0 break-words">{{ linha.nome }}</span>
            <span
              v-if="linha.tipo"
              class="px-2 py-0.5 text-xs font-normal rounded-full bg-n-slate-3 text-n-slate-11"
            >
              {{ linha.tipo }}
            </span>
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{ linha.texto || t(`${NS}.CANAL_SEM_HORARIO`) }}
          </p>
        </div>
        <router-link
          v-if="podeAbrirCanal"
          :to="linha.rota"
          :aria-label="
            linha.texto
              ? t(`${NS}.VER_CANAL_ROTULO`, { nome: linha.nome })
              : t(`${NS}.DEFINIR_CANAL_ROTULO`, { nome: linha.nome })
          "
          class="inline-flex items-center text-sm font-medium underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        >
          {{ linha.texto ? t(`${NS}.VER_CANAL`) : t(`${NS}.DEFINIR_CANAL`) }}
        </router-link>
      </li>
    </ul>
  </section>
</template>
