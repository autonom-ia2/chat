<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import ConversationAPI from 'dashboard/api/inbox/conversation';

// #982 — "O Guia notou": a caixa com mais conversas abertas sem responsável,
// quando a distribuição automática dela está desligada. Um toque leva o pedido
// pronto para o Guia montar; "Agora não" esconde a sugestão daquela caixa.
const props = defineProps({
  accountId: { type: Number, required: true },
});

const emit = defineEmits(['aceitar']);

// Abaixo disso não vale interromper a pessoa.
const MINIMO_SEM_DONO = 5;
// Uma consulta por caixa: o teto evita uma rajada em conta com muitas caixas.
const MAX_CAIXAS = 6;

const inboxes = useMapGetter('inboxes/getInboxes');
const achado = ref(null);
const dispensadas = ref(new Set());

const chave = caixaId => `automacoes:sugestao:${props.accountId}:${caixaId}`;

const foiDispensada = caixaId => {
  try {
    return window.localStorage.getItem(chave(caixaId)) === '1';
  } catch {
    return false;
  }
};

const contar = async caixa => {
  try {
    const { data } = await ConversationAPI.meta({
      inboxId: caixa.id,
      status: 'open',
    });
    return {
      caixa,
      semDono: data?.meta?.unassigned_count || 0,
      total: data?.meta?.all_count || 0,
    };
  } catch {
    return null;
  }
};

const procurar = async () => {
  const candidatas = (inboxes.value || [])
    .filter(caixa => !caixa.enable_auto_assignment && !foiDispensada(caixa.id))
    .slice(0, MAX_CAIXAS);
  if (!candidatas.length) return;
  const contagens = (await Promise.all(candidatas.map(contar))).filter(Boolean);
  const maior = contagens.sort((a, b) => b.semDono - a.semDono)[0];
  achado.value = maior && maior.semDono >= MINIMO_SEM_DONO ? maior : null;
};

onMounted(procurar);
watch(
  () => (inboxes.value || []).length,
  (agora, antes) => {
    if (agora && !antes) procurar();
  }
);

const visivel = computed(
  () => achado.value && !dispensadas.value.has(achado.value.caixa.id)
);

const dispensar = () => {
  const { id } = achado.value.caixa;
  dispensadas.value = new Set([...dispensadas.value, id]);
  try {
    window.localStorage.setItem(chave(id), '1');
  } catch {
    // Sem armazenamento, a sugestão some só nesta visita.
  }
};
</script>

<template>
  <!-- `contents`: o embrulho não vira item do layout da página; sem sugestão,
       não sobra espaço no lugar dela. -->
  <div class="contents">
    <section
      v-if="visivel"
      data-sugestao
      :aria-label="$t('AUTOMACOES.SUGESTAO.ROTULO')"
      class="flex flex-wrap items-center gap-5 px-6 py-5 text-white rounded-2xl bg-gradient-to-br from-n-navy to-[#163A6B]"
    >
      <span
        class="grid place-items-center size-12 shrink-0 rounded-xl bg-n-blue-9/20 text-n-blue-6"
      >
        <span class="i-lucide-sparkles size-6" aria-hidden="true" />
      </span>
      <div class="flex-1 min-w-[16rem]">
        <p
          class="mb-0 text-xs font-semibold tracking-wider uppercase text-n-blue-6"
        >
          {{ $t('AUTOMACOES.SUGESTAO.ROTULO') }}
        </p>
        <p class="mb-0 mt-1 text-base leading-relaxed md:text-lg">
          {{
            $t('AUTOMACOES.SUGESTAO.TEXTO', {
              n: achado.semDono,
              total: achado.total,
              caixa: achado.caixa.name,
            })
          }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          data-aceitar
          class="px-5 text-[0.9375rem] font-semibold transition bg-white rounded-xl min-h-11 text-n-navy hover:bg-white/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
          @click="
            emit(
              'aceitar',
              $t('AUTOMACOES.SUGESTAO.PEDIDO', { caixa: achado.caixa.name })
            )
          "
        >
          {{ $t('AUTOMACOES.SUGESTAO.ACEITAR') }}
        </button>
        <button
          type="button"
          data-dispensar
          class="px-4 text-[0.9375rem] transition rounded-xl min-h-11 text-white/75 hover:text-white hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
          @click="dispensar"
        >
          {{ $t('AUTOMACOES.SUGESTAO.AGORA_NAO') }}
        </button>
      </div>
    </section>
  </div>
</template>
