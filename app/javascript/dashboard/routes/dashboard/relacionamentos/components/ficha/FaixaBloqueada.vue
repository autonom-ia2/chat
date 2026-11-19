<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #3071 — a faixa de quem está bloqueado, no molde da FaixaNaoQuer: diz o que o
// bloqueio faz e tem "Desbloquear" ali mesmo (desbloquear não apaga nada, então
// não pergunta antes). Quem só pode ver (`podeDesbloquear` falso) lê a faixa e
// não tem o botão.
const props = defineProps({
  pessoa: { type: Object, required: true },
  desbloqueando: { type: Boolean, default: false },
  podeDesbloquear: { type: Boolean, default: true },
});
const emit = defineEmits(['desbloquear']);

const { t } = useI18n();
const primeiroNome = computed(
  () =>
    String(props.pessoa.name ?? '')
      .trim()
      .split(' ')[0]
);
</script>

<template>
  <div
    data-relacionamentos="faixa-bloqueada"
    tabindex="-1"
    class="rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
  >
    <Banner
      color="ruby"
      class="[&>div:first-child]:flex-1 [&>div:first-child]:min-w-0"
    >
      <div
        class="flex flex-col gap-3 py-1 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex items-start min-w-0 gap-3">
          <span
            class="mt-0.5 i-lucide-ban size-5 shrink-0"
            aria-hidden="true"
          />
          <div class="flex flex-col min-w-0 gap-1">
            <p class="m-0 text-base font-medium">
              {{
                t('RELACIONAMENTOS_FICHA.BLOQUEIO.FAIXA', { nome: pessoa.name })
              }}
            </p>
            <p class="m-0 text-sm">
              {{
                t('RELACIONAMENTOS_FICHA.BLOQUEIO.FAIXA_APOIO', {
                  nome: primeiroNome,
                })
              }}
            </p>
          </div>
        </div>
        <Button
          v-if="podeDesbloquear"
          ruby
          outline
          type="button"
          data-relacionamentos="desbloquear"
          class="w-full !h-11 shrink-0 whitespace-nowrap sm:w-auto"
          :is-loading="desbloqueando"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.DESBLOQUEAR')"
          @click="emit('desbloquear')"
        />
      </div>
    </Banner>
  </div>
</template>
