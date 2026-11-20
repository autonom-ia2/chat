<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { linkCompleto, linkSeguro } from '../../ficha/atributos';
import { formatarCnpj } from '../../ficha/formatos';
import BotaoCopiar from './BotaoCopiar.vue';
import MenuMais from './MenuMais.vue';

// #2894 — o cabeçalho da ficha da empresa: nome, CNPJ com copiar e o site, e as
// ações. Quem só pode ver (`podeEditar` falso) não tem "Alterar".
// #2970 — o que ainda não é de verdade não aparece: "Mandar mensagem" daqui só
// simula, então só existe com `podeMandarMensagem` (a página liga na
// demonstração).
// #3078 — o que a ficha antiga de Empresas tinha no topo: a foto (quadrada),
// a cidade, o site que abre numa aba nova ("Visitar site"), "Lembrete"
// (`podeLembrete`, a regra do "Novo lembrete" da ficha antiga) e "Apagar"
// (`podeApagar`). "Alterar informações" e "Apagar" ficam no "⋯"; com um só
// deles, ele vira um botão (ninguém abre menu para uma escolha).
const props = defineProps({
  empresa: { type: Object, required: true },
  podeEditar: { type: Boolean, default: true },
  podeApagar: { type: Boolean, default: false },
  podeLembrete: { type: Boolean, default: false },
  podeMandarMensagem: { type: Boolean, default: false },
});
const emit = defineEmits(['mandarMensagem', 'alterar', 'lembrete', 'apagar']);

const { t } = useI18n();

// O site gravado é só o nome ("padaria.com.br"); o link abre com https.
const linkDoSite = computed(() =>
  props.empresa.domain ? linkSeguro(linkCompleto(props.empresa.domain)) : ''
);

const ITEM = {
  alterar: { chave: 'ALTERAR_INFORMACOES', icone: 'i-lucide-pencil' },
  apagar: { chave: 'APAGAR_EMPRESA', icone: 'i-lucide-trash-2', perigo: true },
};
const itensDoMais = computed(() =>
  [props.podeEditar && 'alterar', props.podeApagar && 'apagar']
    .filter(Boolean)
    .map(evento => ({ evento, ...ITEM[evento] }))
);
const unico = computed(() =>
  itensDoMais.value.length === 1 ? itensDoMais.value[0] : null
);
const temAcoes = computed(
  () =>
    props.podeMandarMensagem ||
    props.podeLembrete ||
    itensDoMais.value.length > 0
);
const EMITIR = {
  alterar: () => emit('alterar'),
  apagar: () => emit('apagar'),
};
const escolher = evento => EMITIR[evento]?.();
</script>

<template>
  <header
    data-relacionamentos="cabecalho"
    class="flex flex-col w-full min-w-0 gap-6 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-8 lg:flex-row lg:items-start lg:justify-between"
  >
    <div
      class="grid w-full min-w-0 grid-cols-[auto_1fr] items-center gap-x-4 gap-y-4 md:items-start md:gap-x-6 lg:flex-1"
    >
      <Avatar
        :name="empresa.name"
        :src="empresa.thumbnail"
        :size="56"
        class="shrink-0 md:hidden"
      />
      <Avatar
        :name="empresa.name"
        :src="empresa.thumbnail"
        :size="88"
        class="hidden shrink-0 md:row-span-2 md:inline-flex"
      />
      <h1
        class="m-0 text-2xl font-bold leading-tight tracking-tight break-words md:text-4xl text-n-slate-12"
      >
        {{ empresa.name }}
      </h1>
      <div
        data-relacionamentos="contato-da-empresa"
        class="flex flex-col min-w-0 col-span-2 gap-1 md:col-span-1 md:col-start-2"
      >
        <div
          v-if="empresa.cnpj"
          class="flex items-center gap-1 text-base text-n-slate-12"
        >
          <span class="tabular-nums whitespace-nowrap">
            {{ formatarCnpj(empresa.cnpj) }}
          </span>
          <BotaoCopiar
            class="-my-2"
            :valor="formatarCnpj(empresa.cnpj)"
            :item="t('RELACIONAMENTOS_FICHA.CABECALHO.ITEM_CNPJ')"
          />
        </div>
        <p
          v-if="empresa.city"
          data-relacionamentos="cidade-da-empresa"
          class="flex items-center min-w-0 gap-2 m-0 text-base text-n-slate-11"
        >
          <span
            class="i-lucide-map-pin size-4 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <span class="min-w-0 break-words">{{ empresa.city }}</span>
        </p>
        <p
          v-if="empresa.domain"
          class="flex items-center min-w-0 gap-2 m-0 text-base text-n-slate-11"
        >
          <span
            class="i-lucide-globe size-4 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <a
            v-if="linkDoSite"
            data-relacionamentos="site-da-empresa"
            :href="linkDoSite"
            target="_blank"
            rel="noopener noreferrer"
            :aria-label="
              t('RELACIONAMENTOS_FICHA.EMPRESA.VISITAR_SITE', {
                site: empresa.domain,
              })
            "
            class="inline-flex items-center min-w-0 gap-1 -my-2.5 font-medium text-n-blue-11 hover:underline min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            <span class="min-w-0 truncate">{{ empresa.domain }}</span>
            <span
              class="i-lucide-external-link size-4 shrink-0"
              aria-hidden="true"
            />
          </a>
          <span
            v-else
            class="min-w-0 truncate whitespace-nowrap"
            :title="empresa.domain"
          >
            {{ empresa.domain }}
          </span>
        </p>
      </div>
    </div>
    <div
      v-if="temAcoes"
      role="group"
      :aria-label="
        t('RELACIONAMENTOS_FICHA.EMPRESA.ACOES', { nome: empresa.name })
      "
      data-relacionamentos="acoes-da-empresa"
      class="flex flex-col w-full min-w-0 gap-3 sm:flex-row sm:flex-wrap sm:items-center lg:w-auto lg:shrink-0 lg:flex-nowrap"
    >
      <Button
        v-if="podeMandarMensagem"
        data-relacionamentos="mandar-mensagem"
        size="lg"
        class="w-full sm:w-auto whitespace-nowrap shrink-0"
        icon="i-lucide-send"
        :label="t('RELACIONAMENTOS_FICHA.EMPRESA.MANDAR')"
        @click="emit('mandarMensagem')"
      />
      <div class="flex items-center min-w-0 gap-3">
        <Button
          v-if="podeLembrete"
          data-relacionamentos="lembrete"
          slate
          faded
          size="lg"
          icon="i-lucide-bell-plus"
          class="flex-1 whitespace-nowrap sm:flex-none"
          :label="t('RELACIONAMENTOS_FICHA.ACOES.LEMBRETE')"
          @click="emit('lembrete')"
        />
        <Button
          v-if="unico"
          :data-relacionamentos="
            unico.evento === 'alterar' ? 'alterar-empresa' : 'apagar-empresa'
          "
          slate
          faded
          size="lg"
          class="flex-1 whitespace-nowrap sm:flex-none"
          :class="{ '!text-n-ruby-11': unico.perigo }"
          :label="t(`RELACIONAMENTOS_FICHA.ACOES.${unico.chave}`)"
          @click="escolher(unico.evento)"
        />
        <MenuMais
          v-else-if="itensDoMais.length"
          :class="{ 'ms-auto sm:ms-0': !podeLembrete }"
          :itens="itensDoMais"
          @acao="escolher"
        />
      </div>
    </div>
  </header>
</template>
