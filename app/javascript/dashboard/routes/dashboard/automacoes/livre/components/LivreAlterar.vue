<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreCampo from './LivreCampo.vue';
import LivreCondicao from './LivreCondicao.vue';
import LivreDuracao from './LivreDuracao.vue';
import LivreTexto from './LivreTexto.vue';
import LivreModelo from './LivreModelo.vue';
import LivreDestinatarios from './LivreDestinatarios.vue';
import LivreIaCampo from './LivreIaCampo.vue';
import LivreIaTestar from './LivreIaTestar.vue';
import LivreGatilho from './LivreGatilho.vue';
import { caminhosProntos } from '../ia';
import { entradaDoPasso, gravarCampo, lerCampo } from '../catalogo';
import { fraseDaCondicao, fraseDoGatilho, fraseDoPasso } from '../frases';
import { copiar, filtrosDoGatilho } from '../receita';

// #2414 F5 — o painel do "Alterar": os campos do item escolhido (o gatilho, uma
// condição do "Só se" ou um passo), já preenchidos. Nada muda até "Salvar".
// Passo que o editor não conhece (ação avançada) aparece em frase e só sai
// inteiro: o editor nunca reescreve o que não sabe montar.
const props = defineProps({
  catalogo: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  atributosDaPeca: { type: Function, required: true },
  atributosDo: { type: Function, required: true },
  // #2500 C2: o rascunho inteiro com o passo do painel, para o "Testar", e o
  // custo de cada passo ({ com_valores, custos }).
  receitaDoTeste: { type: Function, default: null },
  custos: { type: Object, default: () => ({ com_valores: false, custos: {} }) },
  // #2499: os gatilhos que esta pessoa pode escolher (com a flag e a chave de
  // funis, os de card) e as escolhas deles. Sem a lista, todos os do catálogo.
  gatilhos: { type: Array, default: null },
  escolhasDoGatilho: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['salvar', 'tirar', 'close']);

const { t } = useI18n();
const painel = ref(null);

// { tipo: 'gatilho' | 'condicao' | 'passo', indice?, novo?, listaId?, valor }
const alvo = ref(null);
const rascunho = ref(null);

const entrada = computed(() =>
  alvo.value?.tipo === 'passo'
    ? entradaDoPasso(rascunho.value, props.catalogo)
    : null
);
const avancada = computed(() => alvo.value?.tipo === 'passo' && !entrada.value);

// Os galhos ("então", "senão") ficam na própria lista do Confira, não aqui.
const camposNativos = computed(() =>
  entrada.value && entrada.value.tipo !== 'acao'
    ? entrada.value.campos.filter(campo => campo.peca !== 'passos')
    : []
);
const ehDeIa = computed(() => entrada.value?.grupo === 'IA');
const camposDaAcao = computed(() =>
  entrada.value?.tipo === 'acao' ? entrada.value.campos : []
);
// A mesma etiqueta não vai em "Pôr" e em "Tirar": marcada numa lista, fica
// bloqueada na outra.
const bloqueadasDe = campo =>
  campo.peca === 'etiquetas'
    ? camposDaAcao.value
        .filter(outro => outro.peca === 'etiquetas' && outro !== campo)
        .flatMap(
          outro => lerCampo(rascunho.value, entrada.value, outro.nome) || []
        )
    : [];
const escolhasDoCaminho = computed(() =>
  Object.entries(entrada.value?.caminho || {})
    .filter(([, origem]) => origem.escolher)
    .map(([param, origem]) => ({ param, ...origem }))
);

const titulo = computed(() =>
  alvo.value
    ? t(`AUTOMACAO_LIVRE.ALTERAR_PAINEL.${alvo.value.tipo.toUpperCase()}`)
    : ''
);

const frase = computed(() => {
  if (!alvo.value || !rascunho.value) return '';
  if (alvo.value.tipo === 'passo')
    return fraseDoPasso(rascunho.value, props.catalogo, t);
  if (alvo.value.tipo === 'gatilho')
    return fraseDoGatilho(
      rascunho.value,
      props.catalogo,
      t,
      props.escolhasDoGatilho.nomes
    );
  return fraseDaCondicao(rascunho.value, props.catalogo, t);
});

const gatilhosDoSeletor = computed(
  () => props.gatilhos || props.catalogo.gatilhos
);
// O "Só se" acompanha o gatilho (#2496): o que entra e o que sai aparece aqui,
// antes do "Salvar".
const trocaDoGatilho = computed(() => {
  if (alvo.value?.tipo !== 'gatilho' || !rascunho.value?.tipo) return null;
  if (rascunho.value.tipo === alvo.value.valor?.tipo) return null;
  return filtrosDoGatilho(
    alvo.value.valor?.filtros,
    rascunho.value.tipo,
    props.catalogo
  );
});

// Campo opcional que volta vazio (o modelo da F4b) sai da receita: o esquema
// não aceita null.
const mudarNativo = (nome, novo) => {
  if (novo === null) {
    const { [nome]: _tirado, ...resto } = rascunho.value;
    rascunho.value = resto;
    return;
  }
  rascunho.value = { ...rascunho.value, [nome]: novo };
};
const mudarCampo = (nome, novo) => {
  rascunho.value = gravarCampo(rascunho.value, entrada.value, nome, novo);
};
const mudarCaminho = (param, novo) => {
  rascunho.value = {
    ...rascunho.value,
    caminho: { ...(rascunho.value.caminho || {}), [param]: novo },
  };
};

const abrir = item => {
  alvo.value = item;
  rascunho.value = copiar(item.valor ?? null);
  painel.value?.open();
};

// Quem usa fecha o painel quando a mudança deu certo; se a API recusou, o
// painel fica aberto com o que a pessoa montou.
const salvar = () => {
  const valor = trocaDoGatilho.value
    ? { ...rascunho.value, filtros: trocaDoGatilho.value.filtros }
    : rascunho.value;
  emit('salvar', { ...alvo.value, valor: copiar(valor) });
};

const tirar = () => {
  emit('tirar', alvo.value);
};

const podeTirar = computed(
  () =>
    (alvo.value?.tipo === 'passo' && !alvo.value.novo) ||
    (alvo.value?.tipo === 'condicao' && alvo.value.indice >= 0)
);
// O que o esquema recusaria não chega a "Salvar": a condição sem o que olhar, a
// duração sem número, o alvo a escolher e o campo obrigatório vazios. O
// obrigatório "pelo_modelo" depende de outro campo; quem confere é a API.
const condicaoPronta = condicao =>
  Boolean(condicao?.todas || condicao?.alguma || condicao?.campo?.$valor);
const vazio = valor =>
  valor === undefined ||
  valor === null ||
  valor === '' ||
  (Array.isArray(valor) && !valor.length);
const nativoPronto = campo => {
  const valor = rascunho.value[campo.nome];
  if (campo.peca === 'duracao') return Number.isInteger(valor?.valor);
  if (campo.peca === 'condicao') return condicaoPronta(valor);
  // O texto pede algo além de espaço; o aviso, alguém para chamar.
  if (campo.peca === 'texto_com_valores')
    return (valor || []).some(
      parte => typeof parte !== 'string' || parte.trim()
    );
  // F4b: o modelo é opcional; escolhido, cada variável pede algo além de espaço.
  if (campo.peca === 'modelo_whatsapp')
    return (
      !valor ||
      (valor.variaveis || []).every(partes =>
        (partes || []).some(parte => typeof parte !== 'string' || parte.trim())
      )
    );
  if (campo.peca === 'destinatarios')
    return Boolean(
      valor?.responsavel || valor?.times?.length || valor?.pessoas?.length
    );
  // F7: a pergunta e a instrução escritas; cada caminho e cada dado com nome,
  // descrição e (no extrair) onde gravar; o destino escolhido.
  if (campo.peca === 'instrucao') return Boolean(valor?.trim());
  if (campo.peca === 'caminhos') return caminhosProntos(valor || []);
  if (campo.peca === 'campos_extrair')
    return (
      (valor || []).length >= 1 &&
      valor.every(
        item => item.chave?.trim() && item.descricao?.trim() && item.destino
      )
    );
  if (campo.peca.startsWith('destino_')) return !vazio(valor);
  return true;
};
const acaoPronta = () =>
  escolhasDoCaminho.value.every(
    escolha => !vazio(rascunho.value.caminho?.[escolha.param])
  ) &&
  camposDaAcao.value
    .filter(campo => campo.obrigatorio === true)
    .every(
      campo => !vazio(lerCampo(rascunho.value, entrada.value, campo.nome))
    );

// O que o gatilho pede e é obrigatório (a etapa) precisa vir antes do "Salvar".
const gatilhoPronto = gatilho =>
  Boolean(gatilho.tipo) &&
  (
    props.catalogo.gatilhos.find(item => item.tipo === gatilho.tipo)
      ?.parametros || []
  )
    .filter(parametro => parametro.obrigatorio)
    .every(parametro => !vazio(gatilho[parametro.nome]));

const podeSalvar = computed(() => {
  if (avancada.value || !rascunho.value) return false;
  if (alvo.value?.tipo === 'gatilho') return gatilhoPronto(rascunho.value);
  if (alvo.value?.tipo === 'condicao') return condicaoPronta(rascunho.value);
  return camposNativos.value.every(nativoPronto) && acaoPronta();
});

const fechar = () => painel.value?.close();

const receitaParaTestar = computed(() =>
  ehDeIa.value && props.receitaDoTeste && rascunho.value
    ? props.receitaDoTeste({ ...alvo.value, valor: rascunho.value })
    : null
);

defineExpose({ abrir, fechar });
</script>

<template>
  <SidePanel ref="painel" :title="titulo" width="lg" @close="emit('close')">
    <div v-if="alvo" data-alterar class="flex flex-col gap-5">
      <p
        v-if="frase"
        data-frase-alterar
        class="px-4 py-3 mb-0 text-base font-medium rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ frase }}
      </p>

      <p
        v-if="avancada"
        data-avancada-dica
        class="mb-0 text-[0.9375rem] text-n-slate-11"
      >
        {{ $t('AUTOMACAO_LIVRE.CONFIRA.AVANCADA_DICA') }}
      </p>

      <LivreGatilho
        v-if="alvo.tipo === 'gatilho'"
        :model-value="rascunho"
        :gatilhos="gatilhosDoSeletor"
        :escolhas="escolhasDoGatilho"
        @update:model-value="novo => (rascunho = novo)"
      />

      <p
        v-if="trocaDoGatilho?.entra"
        data-filtro-entra
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-teal-3 text-n-teal-12"
      >
        {{
          $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.FILTRO_ENTRA', {
            condicao: fraseDaCondicao(trocaDoGatilho.entra, catalogo, t),
          })
        }}
      </p>
      <p
        v-for="(filtro, i) in trocaDoGatilho?.saem || []"
        :key="i"
        data-filtro-sai
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{
          $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.FILTRO_SAI', {
            condicao: fraseDaCondicao(filtro, catalogo, t),
          })
        }}
      </p>

      <LivreCondicao
        v-if="alvo.tipo === 'condicao'"
        :gatilho="alvo.gatilho"
        :model-value="rascunho"
        :catalogo="catalogo"
        :atributos-do="atributosDo"
        @update:model-value="novo => (rascunho = novo)"
      />

      <template v-for="campo in camposNativos" :key="campo.nome">
        <LivreDuracao
          v-if="campo.peca === 'duracao'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :unidades="catalogo.unidades"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreCondicao
          v-else-if="campo.peca === 'condicao'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          :na-espera="entrada?.tipo === 'esperar_ate'"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreTexto
          v-else-if="campo.peca === 'texto_com_valores'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreModelo
          v-else-if="campo.peca === 'modelo_whatsapp'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreDestinatarios
          v-else-if="campo.peca === 'destinatarios'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :opcoes="opcoes"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreIaCampo
          v-else-if="ehDeIa"
          :campo="campo"
          :model-value="rascunho[campo.nome]"
          :opcoes="opcoes"
          :atributos-do="atributosDo"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
      </template>

      <div
        v-for="escolha in escolhasDoCaminho"
        :key="escolha.param"
        class="flex flex-col gap-1.5"
        :data-escolher="escolha.escolher"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(escolha.rotulo) }}
        </span>
        <ChoiceSelect
          :model-value="rascunho.caminho?.[escolha.param] ?? ''"
          :aria-label="$t(escolha.rotulo)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoes[escolha.escolher] || []"
          @update:model-value="novo => mudarCaminho(escolha.param, novo)"
        />
      </div>

      <LivreCampo
        v-for="campo in camposDaAcao"
        :key="campo.nome"
        :campo="campo"
        :model-value="lerCampo(rascunho, entrada, campo.nome)"
        :catalogo="catalogo"
        :opcoes="opcoes"
        :atributos="atributosDaPeca(campo.peca)"
        :atributos-do="atributosDo"
        :bloqueadas="bloqueadasDe(campo)"
        @update:model-value="novo => mudarCampo(campo.nome, novo)"
      />

      <LivreIaTestar
        v-if="ehDeIa"
        :passo="rascunho"
        :receita="receitaParaTestar"
        :custo="custos.custos[rascunho.id]"
        :mostra-custo="custos.com_valores"
        :pronto="podeSalvar"
      />
    </div>

    <template #footer>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <Button
          v-if="podeTirar"
          data-tirar
          :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIRAR')"
          icon="i-lucide-trash-2"
          ruby
          link
          class="min-h-11"
          @click="tirar"
        />
        <span v-else />
        <Button
          v-if="!avancada"
          data-salvar
          :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SALVAR')"
          class="min-h-11"
          :disabled="!podeSalvar"
          @click="salvar"
        />
      </div>
    </template>
  </SidePanel>
</template>
