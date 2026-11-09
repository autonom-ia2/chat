<script setup>
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';

// #2797 (nota da Campanhas) — no pronto do "Pôr na lista": quem entrou num
// canal que está desligado nesta lista não recebe por ele até alguém ligar.
// Uma frase por canal (WhatsApp, e-mail) e o caminho para ligar, em
// Campanhas › Públicos. Pôr gente nunca liga canal (AudienceMembership).
defineProps({
  // [{ canal: 'email' | 'whatsapp', n }]
  canais: { type: Array, default: () => [] },
});

const route = useRoute();
const router = useRouter();
const NS = 'PROSPECTING_ACHAR.PRONTO.LISTA.CANAL_DESLIGADO';
const CHAVE_DO_CANAL = { whatsapp: 'WHATSAPP', email: 'EMAIL' };

const irParaPublicos = () =>
  router.push({
    name: 'campaigns_journey_audiences',
    params: { accountId: route.params.accountId },
  });
</script>

<template>
  <div
    v-show="canais.length"
    role="status"
    class="flex flex-col items-center gap-1"
    data-canais-desligados
  >
    <p
      v-for="item in canais"
      :key="item.canal"
      class="m-0 text-base text-n-amber-11"
      :data-canal-desligado="item.canal"
    >
      {{ $t(`${NS}.${CHAVE_DO_CANAL[item.canal]}`, { n: item.n }, item.n) }}
    </p>
    <Button
      :label="$t(`${NS}.IR`)"
      variant="link"
      class="!min-h-11 justify-center"
      data-ir-para-publicos
      @click="irParaPublicos"
    />
  </div>
</template>
