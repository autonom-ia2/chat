<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { entradaDoPasso } from '../catalogo';
import { fraseDoPasso } from '../frases';
import { galhosDe, idDaLista } from '../receita';

// #2414 F5 — os passos do "Faça", numerados, com "Alterar" em cada um e um "+"
// entre eles. "Se", "Esperar até" e "Decidir" mostram os galhos: o primeiro nível aberto,
// os de dentro recolhidos ("Mostrar tudo" abre todos). O componente chama a si
// mesmo para os galhos.
const props = defineProps({
  passos: { type: Array, required: true },
  listaId: { type: String, required: true },
  catalogo: { type: Object, required: true },
  nivel: { type: Number, default: 0 },
  podeMudar: { type: Boolean, default: false },
  tudo: { type: Boolean, default: false },
});

const emit = defineEmits(['alterar', 'inserir']);

const { t } = useI18n();

// Galhos que a pessoa abriu ou fechou à mão (o contrário do padrão).
const trocados = ref(new Set());
const aberto = chave => {
  if (props.tudo) return true;
  const padrao = props.nivel === 0;
  return trocados.value.has(chave) ? !padrao : padrao;
};
const alternarGalho = chave => {
  const novos = new Set(trocados.value);
  if (novos.has(chave)) novos.delete(chave);
  else novos.add(chave);
  trocados.value = novos;
};

const ICONES = {
  esperar: 'i-lucide-hourglass',
  esperar_ate: 'i-lucide-alarm-clock',
  se: 'i-lucide-git-branch',
  parar: 'i-lucide-octagon-x',
  acao: 'i-lucide-play',
  decidir: 'i-lucide-split',
  extrair: 'i-lucide-scan-text',
  escrever: 'i-lucide-pen-line',
  resumir: 'i-lucide-text-quote',
};
const icone = passo => ICONES[passo.tipo] || 'i-lucide-blocks';
const avancada = passo => !entradaDoPasso(passo, props.catalogo);

// O galho opcional vazio ("Senão" sem passo) só aparece para quem pode mudar.
const galhos = passo =>
  galhosDe(passo)
    .map(galho => ({
      ramo: galho.ramo,
      nome: galho.nome,
      chave: idDaLista(passo.id, galho.ramo),
      passos: galho.passos || [],
    }))
    .filter(galho => props.podeMudar || galho.passos.length);

const frase = passo => fraseDoPasso(passo, props.catalogo, t);
// O galho do caminho do "decidir" leva o nome que a pessoa deu; sem nome,
// "Caminho N".
const rotuloDoGalho = galho => {
  const [ramo, indice] = galho.ramo.split('.');
  if (ramo === 'caminhos')
    return (
      galho.nome ||
      t('AUTOMACAO_LIVRE.RAMOS.CAMINHO', { n: Number(indice) + 1 })
    );
  return t(`AUTOMACAO_LIVRE.RAMOS.${galho.ramo.toUpperCase()}`);
};
const inserir = indice => emit('inserir', { listaId: props.listaId, indice });
</script>

<template>
  <ol class="flex flex-col gap-2 p-0 m-0 list-none">
    <li v-if="podeMudar && !passos.length">
      <button
        type="button"
        data-inserir
        class="inline-flex items-center gap-2 px-4 text-sm font-medium border border-dashed rounded-xl min-h-11 border-n-slate-6 text-n-slate-11 hover:border-n-blue-7 hover:text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="inserir(0)"
      >
        <span class="i-lucide-plus size-4" aria-hidden="true" />
        {{ $t('AUTOMACAO_LIVRE.CONFIRA.PRIMEIRO_PASSO') }}
      </button>
    </li>
    <li v-else-if="!passos.length" class="text-sm text-n-slate-10">
      {{ $t('AUTOMACAO_LIVRE.CONFIRA.NADA') }}
    </li>
    <template v-for="(passo, indice) in passos" :key="passo.id">
      <li :data-passo="passo.id" class="flex flex-col gap-2">
        <div
          class="flex items-start gap-3 p-4 border rounded-2xl bg-n-solid-1 border-n-weak"
        >
          <span
            v-if="nivel === 0"
            class="grid text-sm font-bold rounded-full place-items-center size-9 shrink-0 bg-n-teal-3 text-n-teal-11"
          >
            {{ indice + 1 }}
          </span>
          <span
            v-else
            class="grid rounded-full place-items-center size-9 shrink-0 bg-n-slate-3 text-n-slate-11"
          >
            <span class="size-4" :class="icone(passo)" aria-hidden="true" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-2">
            <p class="mb-0 text-base break-words text-n-slate-12">
              {{ frase(passo) }}
            </p>
            <span
              v-if="avancada(passo)"
              data-avancada
              class="inline-flex items-center self-start gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-slate-3 text-n-slate-11"
            >
              <span class="i-lucide-lock size-3" aria-hidden="true" />
              {{ $t('AUTOMACAO_LIVRE.CONFIRA.AVANCADA') }}
            </span>
          </div>
          <Button
            v-if="podeMudar"
            data-alterar-passo
            :label="$t('AUTOMACAO_LIVRE.ALTERAR')"
            :aria-label="
              $t('AUTOMACAO_LIVRE.ALTERAR_ROTULO', { frase: frase(passo) })
            "
            slate
            faded
            size="sm"
            class="min-h-11 shrink-0"
            @click="emit('alterar', passo.id)"
          />
        </div>

        <ul
          v-if="galhos(passo).length"
          class="flex flex-col gap-2 p-0 m-0 list-none border-n-weak ms-4 ps-4 border-s-2"
        >
          <li v-for="galho in galhos(passo)" :key="galho.chave">
            <button
              type="button"
              data-galho
              class="inline-flex items-center gap-2 px-2 text-sm font-semibold rounded-lg min-h-11 text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-expanded="aberto(galho.chave)"
              @click="alternarGalho(galho.chave)"
            >
              <span
                class="size-4 text-n-slate-10 rtl:rotate-180"
                :class="
                  aberto(galho.chave)
                    ? 'i-lucide-chevron-down'
                    : 'i-lucide-chevron-right'
                "
                aria-hidden="true"
              />
              <span
                class="i-lucide-corner-down-right size-4 text-n-slate-9"
                aria-hidden="true"
              />
              {{ rotuloDoGalho(galho) }}
              <span
                v-if="!aberto(galho.chave)"
                class="font-normal text-n-slate-10"
              >
                {{
                  $t(
                    'AUTOMACAO_LIVRE.CONFIRA.PASSOS_NO_GALHO',
                    { n: galho.passos.length },
                    galho.passos.length
                  )
                }}
              </span>
            </button>
            <div v-if="aberto(galho.chave)" class="pt-1">
              <LivrePassos
                :passos="galho.passos"
                :lista-id="galho.chave"
                :catalogo="catalogo"
                :nivel="nivel + 1"
                :pode-mudar="podeMudar"
                :tudo="tudo"
                @alterar="id => emit('alterar', id)"
                @inserir="posicao => emit('inserir', posicao)"
              />
            </div>
          </li>
        </ul>
      </li>
      <li v-if="podeMudar" class="flex justify-center">
        <button
          type="button"
          data-inserir
          :aria-label="$t('AUTOMACAO_LIVRE.CONFIRA.INSERIR')"
          :title="$t('AUTOMACAO_LIVRE.CONFIRA.INSERIR')"
          class="grid border rounded-full place-items-center size-11 border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-blue-7 hover:text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="inserir(indice + 1)"
        >
          <span class="i-lucide-plus size-5" aria-hidden="true" />
        </button>
      </li>
    </template>
  </ol>
</template>
