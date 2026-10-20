<script setup>
import { computed, ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ResultsToggle from 'dashboard/routes/dashboard/settings/booking/results/ResultsToggle.vue';
import CrmMetasAPI from 'dashboard/api/crmMetas';
import NumerosEspera from './NumerosEspera.vue';
import { P, formatarDinheiro, nomeDoMes } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';
import {
  dividirIgualmente,
  doServidor,
  invalido,
  paraOServidor,
  repetirAnterior,
  somaDiferente,
  temErro,
} from './metasDaGaveta';

// Gaveta "Metas do mês" (#1991, F4 do #1871), como no protótipo aprovado: uma
// aba por funil de Vender, a meta do funil no topo e uma linha por pessoa. Os
// campos vazios mostram a sugestão e o motivo ao lado: ninguém confirma tudo
// sem ler. Os atalhos só preenchem os campos; nada muda antes de salvar.
// Campo de texto com teclado numérico, não type=number: o Input converteria
// "8.000" em 8 sem avisar; aqui ele vira erro (metasDaGaveta#numero).
const emit = defineEmits(['salvo']);
const MES_MUDOU = 'crm.metas.mes_mudou';

const { t, locale } = useNumerosFormato();
const { currentAccount } = useAccount();
const painel = ref(null);
const funis = ref([]);
const funilAtivo = ref(null);
const mes = ref('');
const mesAnterior = ref('');
const carregando = ref(false);
const falhou = ref(false);
const salvando = ref(false);

const nomeMes = chave =>
  chave
    ? nomeDoMes(chave, {
        locale: locale(),
        fuso: fusoDaConta(currentAccount.value),
      })
    : '';
const mesNome = computed(() => nomeMes(mes.value));

const carregar = async () => {
  carregando.value = true;
  falhou.value = false;
  try {
    const { data } = await CrmMetasAPI.show();
    funis.value = doServidor(data.funis);
    funilAtivo.value = funis.value[0]?.id ?? null;
    mes.value = data.mes;
    mesAnterior.value = data.mesAnterior;
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
};

const abrir = () => {
  painel.value?.open();
  carregar();
};
defineExpose({ abrir });

const funil = computed(() => funis.value.find(f => f.id === funilAtivo.value));
const opcoesDeFunil = computed(() =>
  funis.value.map(f => ({ value: f.id, label: f.nome }))
);
const dinheiro = valor =>
  formatarDinheiro(valor, { locale: locale(), moeda: funil.value.moeda });
const simbolo = computed(
  () =>
    new Intl.NumberFormat(locale(), {
      style: 'currency',
      currency: funil.value?.moeda || 'BRL',
    })
      .formatToParts(0)
      .find(parte => parte.type === 'currency')?.value
);
const unidade = computed(() =>
  t(`${P}.METAS.UNIDADE_VALOR`, { moeda: simbolo.value })
);

const trocarFunil = mudanca => {
  funis.value = funis.value.map(f =>
    f.id === funilAtivo.value ? mudanca(f) : f
  );
};
const definirPessoa = (id, valor) =>
  trocarFunil(f => ({
    ...f,
    pessoas: f.pessoas.map(p =>
      p.id === id ? { ...p, meta: String(valor) } : p
    ),
  }));
const definirMetaFunil = valor =>
  trocarFunil(f => ({ ...f, metaFunil: String(valor) }));

const sugestao = p => {
  if (p.sugestao.valor === null)
    return t(`${P}.METAS.SEM_SUGESTAO`, { nome: p.nome });
  const [h1, h2, h3] = p.sugestao.historico.map(dinheiro);
  return t(`${P}.METAS.SUGESTAO_VALOR`, {
    valor: dinheiro(p.sugestao.valor),
    nome: p.nome,
    h1,
    h2,
    h3,
  });
};

const avisoDaSoma = computed(() => {
  const diferenca = funil.value && somaDiferente(funil.value);
  return diferenca
    ? t(`${P}.METAS.SOMA_DIFERENTE`, {
        soma: dinheiro(diferenca.soma),
        meta: dinheiro(diferenca.meta),
      })
    : '';
});
const comErro = computed(() => temErro(funis.value));

const salvar = async () => {
  if (comErro.value) return;
  salvando.value = true;
  try {
    await CrmMetasAPI.salvar({
      mes: mes.value,
      funis: paraOServidor(funis.value),
    });
    useAlert(t(`${P}.METAS.SALVO`, { mes: mesNome.value }));
    emit('salvo');
    painel.value?.close();
  } catch (erro) {
    // O mês virou com a gaveta aberta: recarrega o mês novo, e nada foi gravado.
    if (erro?.response?.data?.error === MES_MUDOU) {
      await carregar();
      useAlert(t(`${P}.METAS.MES_MUDOU`, { mes: mesNome.value }));
    } else {
      useAlert(t(`${P}.METAS.ERRO_SALVAR`));
    }
  } finally {
    salvando.value = false;
  }
};

const ATALHO =
  'inline-flex min-h-11 items-center gap-2 rounded-xl px-4 text-sm font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <SidePanel
    ref="painel"
    width="lg"
    :title="t(`${P}.METAS.TITULO`, { mes: mesNome })"
    :description="t(`${P}.METAS.DESCRICAO`)"
  >
    <NumerosEspera
      v-if="carregando || falhou"
      :falhou="falhou"
      @tentar="carregar"
    />
    <p
      v-else-if="!funil"
      data-metas-sem-funil
      class="mb-0 text-sm text-n-slate-11"
    >
      {{ t(`${P}.METAS.SEM_FUNIL`) }}
    </p>
    <div v-else data-metas-gaveta class="flex flex-col gap-5">
      <ResultsToggle
        v-if="opcoesDeFunil.length > 1"
        v-model="funilAtivo"
        :options="opcoesDeFunil"
        :label="t(`${P}.METAS.FUNIS`)"
      />

      <Input
        :model-value="funil.metaFunil"
        type="text"
        inputmode="numeric"
        :label="`${t(`${P}.METAS.META_FUNIL`, { funil: funil.nome })} (${unidade})`"
        :placeholder="t(`${P}.METAS.VAZIO`)"
        :message="
          invalido(funil.metaFunil)
            ? t(`${P}.METAS.INVALIDO`)
            : t(`${P}.METAS.META_FUNIL_DICA`)
        "
        :message-type="invalido(funil.metaFunil) ? 'error' : 'info'"
        wrap-message
        data-meta-funil
        @update:model-value="definirMetaFunil"
      />

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${P}.METAS.ATALHOS`) }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            data-atalho="repetir"
            :class="ATALHO"
            @click="trocarFunil(repetirAnterior)"
          >
            <span class="i-lucide-repeat size-4" aria-hidden="true" />
            {{ t(`${P}.METAS.REPETIR`, { mes: nomeMes(mesAnterior) }) }}
          </button>
          <button
            type="button"
            data-atalho="dividir"
            :class="ATALHO"
            @click="trocarFunil(dividirIgualmente)"
          >
            <span class="i-lucide-divide size-4" aria-hidden="true" />
            {{ t(`${P}.METAS.DIVIDIR`) }}
          </button>
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t(`${P}.METAS.ATALHOS_DICA`) }}
        </p>
      </div>

      <p
        v-if="!funil.pessoas.length"
        data-metas-sem-pessoas
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t(`${P}.METAS.SEM_PESSOAS`) }}
      </p>
      <ul v-else class="m-0 flex list-none flex-col gap-4 p-0">
        <li
          v-for="p in funil.pessoas"
          :key="p.id"
          :data-meta-pessoa="p.id"
          class="flex flex-col gap-2 rounded-xl p-3 ring-1 ring-inset ring-n-weak"
        >
          <Input
            :model-value="p.meta"
            type="text"
            inputmode="numeric"
            :label="`${t(`${P}.METAS.META_PESSOA`, { nome: p.nome })} (${unidade})`"
            :placeholder="t(`${P}.METAS.VAZIO`)"
            :message="invalido(p.meta) ? t(`${P}.METAS.INVALIDO`) : ''"
            :message-type="invalido(p.meta) ? 'error' : 'info'"
            @update:model-value="valor => definirPessoa(p.id, valor)"
          />
          <p class="mb-0 text-sm text-n-slate-11">{{ sugestao(p) }}</p>
          <button
            v-if="p.sugestao.valor !== null"
            type="button"
            data-usar-sugestao
            class="inline-flex min-h-11 w-fit items-center gap-1 rounded-xl px-1 text-sm font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="definirPessoa(p.id, p.sugestao.valor)"
          >
            {{ t(`${P}.METAS.USAR_SUGESTAO`) }}
          </button>
        </li>
      </ul>

      <Banner v-if="avisoDaSoma" color="slate" data-soma-diferente>
        {{ avisoDaSoma }}
      </Banner>
    </div>

    <template #footer>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          :label="t(`${P}.METAS.CANCELAR`)"
          slate
          faded
          @click="painel?.close()"
        />
        <Button
          :label="t(`${P}.METAS.SALVAR`)"
          :is-loading="salvando"
          :disabled="comErro || !funil"
          data-salvar-metas
          @click="salvar"
        />
      </div>
    </template>
  </SidePanel>
</template>
