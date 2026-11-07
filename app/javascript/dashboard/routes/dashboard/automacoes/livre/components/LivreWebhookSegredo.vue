<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';

// G13 (#2670) — o segredo que o outro sistema usa para conferir que o envio é
// nosso (cabeçalho X-Automacao-Signature). Vê e troca o administrador ou a
// função com `token_manage`, e só com a automação salva (o segredo é de cada
// automação). O valor fica só nesta tela, nunca na receita.
const props = defineProps({
  automacaoId: { type: Number, default: null },
});

const podeVer = usePermissionGranted('token_manage');
const W = 'AUTOMACAO_LIVRE.WEBHOOK.SEGREDO';

const segredo = ref('');
const confirmando = ref(false);
const carregando = ref(false);
const falhou = ref('');

// Se a troca falhar, o segredo da tela pode já não valer (o servidor pode ter trocado e a resposta se perdido):
// some da tela e o aviso pede para ver de novo.
const pedir = async (chamada, aviso) => {
  carregando.value = true;
  falhou.value = '';
  try {
    const { data } = await chamada(props.automacaoId);
    segredo.value = data.secret;
  } catch {
    if (aviso === 'TROCAR_FALHOU') segredo.value = '';
    falhou.value = aviso;
  } finally {
    carregando.value = false;
    confirmando.value = false;
  }
};

const ver = () => pedir(id => AutomacoesAPI.segredoDoWebhook(id), 'FALHOU');
const trocar = () =>
  pedir(id => AutomacoesAPI.trocarSegredoDoWebhook(id), 'TROCAR_FALHOU');
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-2"
    data-peca="segredo_do_webhook"
  >
    <h3 class="mb-0 text-sm font-medium text-n-slate-12">
      {{ $t(`${W}.TITULO`) }}
    </h3>
    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${W}.DICA`) }}</p>

    <p v-if="!podeVer" class="mb-0 text-sm text-n-slate-11" data-sem-acesso>
      {{ $t(`${W}.SEM_ACESSO`) }}
    </p>
    <p
      v-else-if="!automacaoId"
      class="mb-0 text-sm text-n-slate-11"
      data-salvar-antes
    >
      {{ $t(`${W}.SALVAR_ANTES`) }}
    </p>
    <template v-else>
      <input
        v-if="segredo"
        data-segredo
        readonly
        :aria-label="$t(`${W}.TITULO`)"
        :value="segredo"
        class="w-full px-3 py-2 font-mono text-sm border rounded-xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12"
        @focus="evento => evento.target.select()"
      />
      <p
        v-if="falhou"
        class="mb-0 text-sm text-n-ruby-11"
        role="alert"
        data-segredo-falhou
      >
        {{ $t(`${W}.${falhou}`) }}
      </p>
      <div v-if="confirmando" class="flex flex-col gap-2" data-confirmar-troca>
        <p class="mb-0 text-sm text-n-amber-11">{{ $t(`${W}.CONFIRMAR`) }}</p>
        <div class="flex flex-wrap gap-2">
          <Button
            data-trocar-sim
            :label="$t(`${W}.TROCAR_SIM`)"
            ruby
            class="min-h-11"
            :disabled="carregando"
            @click="trocar"
          />
          <Button
            :label="$t(`${W}.CANCELAR`)"
            faded
            class="min-h-11"
            @click="confirmando = false"
          />
        </div>
      </div>
      <div v-else class="flex flex-wrap gap-2">
        <Button
          v-if="!segredo"
          data-ver-segredo
          :label="$t(`${W}.VER`)"
          icon="i-lucide-eye"
          faded
          class="min-h-11"
          :disabled="carregando"
          @click="ver"
        />
        <Button
          data-trocar-segredo
          :label="$t(`${W}.TROCAR`)"
          icon="i-lucide-refresh-cw"
          ruby
          link
          class="min-h-11"
          @click="confirmando = true"
        />
      </div>
    </template>
  </section>
</template>
