<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LivreValor from './LivreValor.vue';
import { TIPOS_DE_PASSO } from '../prototipo/catalogo';
import {
  dinheiro,
  fraseDoPasso,
  modeloPorId,
  rotuloDoCaminho,
} from '../prototipo/frases';
import { custoDoPasso, idDaLista, passoSemVolta } from '../prototipo/receita';

// #2414 F0 — os passos do "Faça", numerados, com "Alterar" em cada um e um "+"
// entre eles. Decisor, espera por resposta e "Se" mostram os caminhos como
// galhos: o primeiro nível aberto, os de dentro recolhidos ("Mostrar tudo"
// abre todos). O componente chama a si mesmo para os galhos.
const props = defineProps({
  passos: { type: Array, required: true },
  listaId: { type: String, required: true },
  nivel: { type: Number, default: 0 },
  podeMudar: { type: Boolean, default: false },
  tudo: { type: Boolean, default: false },
});

const emit = defineEmits(['alterar', 'inserir']);

const { t } = useI18n();

// Galhos que a pessoa abriu ou fechou à mão (o contrário do padrão).
const trocados = ref(new Set());
const chaveDoGalho = (passo, caminho) => idDaLista(passo.id, caminho.chave);
const aberto = (passo, caminho) => {
  if (props.tudo) return true;
  const padrao = props.nivel === 0;
  return trocados.value.has(chaveDoGalho(passo, caminho)) ? !padrao : padrao;
};
const alternarGalho = (passo, caminho) => {
  const chave = chaveDoGalho(passo, caminho);
  const novos = new Set(trocados.value);
  if (novos.has(chave)) novos.delete(chave);
  else novos.add(chave);
  trocados.value = novos;
};

const icone = passo => TIPOS_DE_PASSO[passo.tipo]?.icone || 'i-lucide-blocks';
const mensagem = passo => {
  if (passo.tipo === 'mandar_mensagem') return passo.texto;
  if (passo.tipo === 'mandar_modelo') return modeloPorId(passo.modelo)?.texto;
  return null;
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
          class="flex items-start gap-3 p-4 border rounded-2xl bg-n-solid-1"
          :class="passoSemVolta(passo) ? 'border-n-amber-6' : 'border-n-weak'"
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
            <p class="mb-0 text-base text-n-slate-12 break-words">
              {{ fraseDoPasso(passo, t) }}
            </p>
            <div
              v-if="passoSemVolta(passo) || custoDoPasso(passo)"
              class="flex flex-wrap gap-2"
            >
              <span
                v-if="passoSemVolta(passo)"
                data-sem-volta
                class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-amber-3 text-n-amber-11"
              >
                <span class="i-lucide-send size-3" aria-hidden="true" />
                {{ $t('AUTOMACAO_LIVRE.SELO_SEM_VOLTA') }}
              </span>
              <span
                v-if="custoDoPasso(passo)"
                data-custo
                class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-iris-3 text-n-iris-11"
              >
                <span class="i-lucide-sparkles size-3" aria-hidden="true" />
                {{
                  $t('AUTOMACAO_LIVRE.CUSTO', {
                    custo: dinheiro(custoDoPasso(passo)),
                  })
                }}
              </span>
            </div>
            <p
              v-if="mensagem(passo)"
              class="self-start max-w-full px-3.5 py-2.5 mb-0 text-[0.9375rem] leading-relaxed rounded-xl rounded-bl-sm bg-n-teal-2 text-n-slate-12"
            >
              <LivreValor :pedacos="mensagem(passo)" />
            </p>
            <p
              v-if="passo.tipo === 'decisor'"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ $t('AUTOMACAO_LIVRE.CONFIRA.DECISOR_DUVIDA') }}
            </p>
          </div>
          <Button
            v-if="podeMudar"
            data-alterar-passo
            :label="$t('AUTOMACAO_LIVRE.ALTERAR')"
            :aria-label="
              $t('AUTOMACAO_LIVRE.ALTERAR_ROTULO', {
                frase: fraseDoPasso(passo, t),
              })
            "
            slate
            faded
            size="sm"
            class="min-h-11 shrink-0"
            @click="emit('alterar', passo.id)"
          />
        </div>

        <ul
          v-if="passo.caminhos"
          class="flex flex-col gap-2 p-0 m-0 list-none border-n-weak ms-4 ps-4 border-s-2"
        >
          <li v-for="caminho in passo.caminhos" :key="caminho.chave">
            <button
              type="button"
              data-galho
              class="inline-flex items-center gap-2 px-2 text-sm font-semibold rounded-lg min-h-11 text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-expanded="aberto(passo, caminho)"
              @click="alternarGalho(passo, caminho)"
            >
              <span
                class="size-4 text-n-slate-10 rtl:rotate-180"
                :class="
                  aberto(passo, caminho)
                    ? 'i-lucide-chevron-down'
                    : 'i-lucide-chevron-right'
                "
                aria-hidden="true"
              />
              <span
                class="i-lucide-corner-down-right size-4 text-n-slate-9"
                aria-hidden="true"
              />
              {{ rotuloDoCaminho(passo, caminho, t) }}
              <span
                v-if="!aberto(passo, caminho)"
                class="font-normal text-n-slate-10"
              >
                {{
                  $t(
                    'AUTOMACAO_LIVRE.CONFIRA.PASSOS_NO_GALHO',
                    { n: caminho.passos.length },
                    caminho.passos.length
                  )
                }}
              </span>
            </button>
            <div v-if="aberto(passo, caminho)" class="pt-1">
              <LivrePassos
                :passos="caminho.passos"
                :lista-id="idDaLista(passo.id, caminho.chave)"
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
