<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import LivreCampo from './LivreCampo.vue';
import LivreCondicao from './LivreCondicao.vue';
import LivreDuracao from './LivreDuracao.vue';
import LivrePrazo from './LivrePrazo.vue';
import LivreTexto from './LivreTexto.vue';
import LivreModelo from './LivreModelo.vue';
import LivreDestinatarios from './LivreDestinatarios.vue';
import LivreCampanha from './LivreCampanha.vue';
import LivreProspeccao from './LivreProspeccao.vue';
import LivreParaCada from './LivreParaCada.vue';
import LivreEtapa from './LivreEtapa.vue';
import LivreRetornoPara from './LivreRetornoPara.vue';
import LivreRetornoEnvio from './LivreRetornoEnvio.vue';
import LivreRegistro from './LivreRegistro.vue';
import LivreRetornoQuando from './LivreRetornoQuando.vue';
import LivreIaCampo from './LivreIaCampo.vue';
import LivreDecidirDeNovo from './LivreDecidirDeNovo.vue';
import LivreIaTestar from './LivreIaTestar.vue';
import LivreGatilho from './LivreGatilho.vue';
import { caminhosProntos, deNovoPronto, esperasAnteriores } from '../ia';
import { campanhaPronta } from '../campanha';
import { prospeccaoPronta } from '../prospeccao';
import { paraCadaPronto } from '../paraCada';
import { envioPronto, paraPronto, quandoPronto } from '../retorno';
import { registroPronto } from '../outroRegistro';
import { faltaDaFrequencia } from '../recorrente';
import { entradaDoPasso, gravarCampo, lerCampo } from '../catalogo';
import { temDataIncompleta } from '../texto';
import { fraseDaCondicao, fraseDoGatilho, fraseDoPasso } from '../frases';
import { SEM_PRAZO, copiar, filtrosDoGatilho } from '../receita';
import { custoPorMensagem } from '../custoDaIa';

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
  // A automação já salva, para o "Testar este passo" (#2780).
  automacaoId: { type: Number, default: null },
  custos: { type: Object, default: () => ({ com_valores: false, custos: {} }) },
  // #2499: os gatilhos que esta pessoa pode escolher (com a flag e a chave de
  // funis, os de card) e as escolhas deles. Sem a lista, todos os do catálogo.
  gatilhos: { type: Array, default: null },
  escolhasDoGatilho: { type: Object, default: () => ({}) },
  // G18: os cards do contato só para quem pode mexer no funil.
  podeLerCards: { type: Boolean, default: false },
});

const emit = defineEmits(['salvar', 'tirar', 'close']);

const { t, locale } = useI18n();
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

// Os galhos ("então", "senão") ficam na própria lista do Confira, não aqui. O
// `daqui` do retorno vai dentro da peça do "Quando" (G57), que cuida dos dois.
const temQuando = computed(() =>
  entrada.value?.campos?.some(campo => campo.peca === 'quando_do_retorno')
);
const camposNativos = computed(() =>
  entrada.value && entrada.value.tipo !== 'acao'
    ? entrada.value.campos.filter(
        campo =>
          campo.peca !== 'passos' &&
          !(temQuando.value && campo.nome === 'daqui')
      )
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
// #2660 lote B: ação sem nada a preencher ("marcar como cliente") diz isso,
// em vez de abrir o painel vazio.
const acaoSemCampos = computed(
  () =>
    entrada.value?.tipo === 'acao' &&
    !camposDaAcao.value.length &&
    !escolhasDoCaminho.value.length
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
      props.escolhasDoGatilho.nomes,
      locale.value
    );
  return fraseDaCondicao(rascunho.value, props.catalogo, t);
});

// G9 (#2707): "quem cuida do card" só nos gatilhos de card.
const doCard = computed(
  () =>
    props.catalogo.gatilhos?.find(item => item.tipo === props.catalogo.gatilho)
      ?.alvo === 'Crm::Card'
);
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
// G49: o contato em que o "criar card" nasce: o do alvo (padrão) ou o que um
// passo anterior desta execução criou.
const opcoesDoContatoCriado = computed(() => [
  { value: '', label: t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CONTATO_DO_ALVO') },
  ...(props.catalogo.valores || [])
    .filter(item => item.criado === 'Contact')
    .map(item => ({ value: item.caminho, label: item.rotulo })),
]);
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

// Cada abertura remonta os campos: a peça de data guarda o modo e o número que a
// pessoa está montando, e um passo não pode herdar os do outro (#2414 G16b).
const aberturas = ref(0);
const abrir = item => {
  aberturas.value += 1;
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
const caixasDaConta = useMapGetter('inboxes/getInboxes');
// O texto e a linha (assunto do e-mail, G2) levam dado da conversa; com os dois
// no passo, cada "Pôr um dado" diz em qual caixa o dado entra.
const TEXTOS = ['texto_com_valores', 'linha_com_valores'];
const variosTextos = computed(
  () =>
    camposNativos.value.filter(campo => TEXTOS.includes(campo.peca)).length > 1
);
const rotuloDoDado = campo =>
  variosTextos.value
    ? t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_VALOR_EM', {
        campo: t(campo.rotulo),
      })
    : '';
const nativoPronto = campo => {
  const valor = rascunho.value[campo.nome];
  if (campo.peca === 'duracao') return Number.isInteger(valor?.valor);
  // #2750: sem prazo, o "se o prazo acabar" precisa estar vazio.
  if (campo.peca === 'prazo')
    return valor === SEM_PRAZO
      ? !rascunho.value.se_vencer?.length
      : Number.isInteger(valor?.valor);
  if (campo.peca === 'condicao') return condicaoPronta(valor);
  // O texto pede algo além de espaço; o aviso, alguém para chamar.
  if (TEXTOS.includes(campo.peca))
    return (valor || []).some(
      parte => typeof parte !== 'string' || parte.trim()
    );
  if (campo.peca === 'caixa_de_email') return !vazio(valor);
  // F4b: o modelo é opcional; escolhido, cada variável pede algo além de espaço.
  if (campo.peca === 'modelo_whatsapp')
    return (
      !valor ||
      (valor.variaveis || []).every(partes =>
        (partes || []).some(parte => typeof parte !== 'string' || parte.trim())
      )
    );
  // G14: a peça da campanha mostra e confere o passo inteiro.
  if (campo.peca === 'campanha')
    return campanhaPronta(rascunho.value, caixasDaConta.value);
  // G21: a peça da prospecção também.
  if (campo.peca === 'prospeccao') return prospeccaoPronta(rascunho.value);
  // G24: a peça do "para cada item" também.
  if (campo.peca === 'para_cada') return paraCadaPronto(rascunho.value);
  if (campo.peca === 'quem_recebe_retorno') return paraPronto(valor);
  if (campo.peca === 'envio_do_retorno') return envioPronto(valor);
  if (campo.peca === 'registro_ligado') return registroPronto(valor);
  if (campo.peca === 'quando_do_retorno') return quandoPronto(rascunho.value);
  if (campo.peca === 'destinatarios')
    return Boolean(
      valor?.responsavel ||
        valor?.da_reuniao ||
        valor?.responsavel_do_card ||
        valor?.times?.length ||
        valor?.pessoas?.length
    );
  // G15: a agente de IA escolhida.
  if (campo.peca === 'agente_de_ia') return Number.isInteger(valor);
  // F7: a pergunta e a instrução escritas; cada caminho e cada dado com nome,
  // descrição e (no extrair) onde gravar; o destino escolhido.
  if (campo.peca === 'instrucao') return Boolean(valor?.trim());
  if (campo.peca === 'caminhos') return caminhosProntos(valor || []);
  // G31: decidir de novo, se ligado, com caminho marcado sem passos e prazo.
  if (campo.peca === 'de_novo') return deNovoPronto(rascunho.value);
  if (campo.peca === 'campos_extrair')
    return (
      (valor || []).length >= 1 &&
      valor.every(
        item => item.chave?.trim() && item.descricao?.trim() && item.destino
      )
    );
  if (campo.peca.startsWith('destino_')) return !vazio(valor);
  if (campo.peca === 'etapa') return !vazio(valor);
  return true;
};
// A data calculada pela metade (sem o campo de partida, sem o número) segura o
// "Salvar" (#2414 G16b).
const acaoPronta = () =>
  !temDataIncompleta(rascunho.value.corpo) &&
  escolhasDoCaminho.value.every(
    escolha => !vazio(rascunho.value.caminho?.[escolha.param])
  ) &&
  camposDaAcao.value
    .filter(campo => campo.obrigatorio === true)
    .every(
      campo => !vazio(lerCampo(rascunho.value, entrada.value, campo.nome))
    );

// O que o gatilho pede e é obrigatório (a etapa; no recorrente, o dia ou a data
// da frequência escolhida) precisa vir antes do "Salvar".
const gatilhoPronto = gatilho =>
  Boolean(gatilho.tipo) &&
  !faltaDaFrequencia(gatilho) &&
  (
    props.catalogo.gatilhos.find(item => item.tipo === gatilho.tipo)
      ?.parametros || []
  )
    .filter(parametro => parametro.obrigatorio)
    .every(parametro =>
      parametro.peca === 'antes'
        ? Number.isInteger(gatilho[parametro.nome]?.valor)
        : !vazio(gatilho[parametro.nome])
    );

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

// G46: os "esperar até" de antes do "decidir" para onde o caminho pode voltar,
// com a frase de cada um, lidos do rascunho inteiro.
const esperasDoDecidir = computed(() =>
  esperasAnteriores(receitaParaTestar.value, rascunho.value?.id).map(
    espera => ({
      value: espera.id,
      label: fraseDoPasso(espera, props.catalogo, t),
    })
  )
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

      <p
        v-if="acaoSemCampos"
        data-sem-campos-dica
        class="mb-0 text-[0.9375rem] text-n-slate-11"
      >
        {{ $t('AUTOMACAO_LIVRE.CONFIRA.SEM_CAMPOS_DICA') }}
      </p>

      <LivreGatilho
        v-if="alvo.tipo === 'gatilho'"
        :model-value="rascunho"
        :gatilhos="gatilhosDoSeletor"
        :escolhas="escolhasDoGatilho"
        :opcoes="opcoes"
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
        <LivrePrazo
          v-else-if="campo.peca === 'prazo'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :unidades="catalogo.unidades"
          :conferir-as="rascunho.conferir_as ?? null"
          :tem-se-vencer="Boolean(rascunho.se_vencer?.length)"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
          @update:conferir-as="novo => mudarNativo('conferir_as', novo)"
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
          v-else-if="TEXTOS.includes(campo.peca)"
          :rotulo="$t(campo.rotulo)"
          :uma-linha="campo.peca === 'linha_com_valores'"
          :rotulo-do-dado="rotuloDoDado(campo)"
          :model-value="rascunho[campo.nome]"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <div
          v-else-if="campo.peca === 'caixa_de_email'"
          class="flex flex-col gap-1.5"
          data-peca="caixa_de_email"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t(campo.rotulo) }}
          </span>
          <ChoiceSelect
            v-if="opcoes.caixaDeEmail?.length"
            :model-value="rascunho[campo.nome] ?? ''"
            :aria-label="$t(campo.rotulo)"
            :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
            :options="opcoes.caixaDeEmail"
            @update:model-value="novo => mudarNativo(campo.nome, novo)"
          />
          <p v-else class="text-sm text-n-slate-11" data-sem-caixa-de-email>
            {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_CAIXA_DE_EMAIL') }}
          </p>
        </div>
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
          :do-card="doCard"
          :model-value="rascunho[campo.nome]"
          :opcoes="opcoes"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreCampanha
          v-else-if="campo.peca === 'campanha' && campo.nome === 'faz'"
          :model-value="rascunho"
          :etiquetas="opcoes.etiqueta"
          @update:model-value="novo => (rascunho = novo)"
        />
        <div
          v-else-if="campo.peca === 'contato_criado'"
          class="flex flex-col gap-1.5"
          data-peca="contato_criado"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t(campo.rotulo) }}
          </span>
          <ChoiceSelect
            :model-value="rascunho[campo.nome]?.$valor ?? ''"
            :aria-label="$t(campo.rotulo)"
            :options="opcoesDoContatoCriado"
            @update:model-value="
              novo => mudarNativo(campo.nome, novo ? { $valor: novo } : null)
            "
          />
        </div>
        <LivreProspeccao
          v-else-if="campo.peca === 'prospeccao' && campo.nome === 'faz'"
          :model-value="rascunho"
          :etiquetas="opcoes.etiqueta"
          :etapas="escolhasDoGatilho.etapas || []"
          @update:model-value="novo => (rascunho = novo)"
        />
        <LivreParaCada
          v-else-if="campo.peca === 'para_cada' && campo.nome === 'campos'"
          :model-value="rascunho"
          :etapas="escolhasDoGatilho.etapas || []"
          :opcoes="opcoes"
          :atributos-do="atributosDo"
          @update:model-value="novo => (rascunho = novo)"
        />
        <LivreEtapa
          v-else-if="campo.peca === 'etapa'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :grupos="escolhasDoGatilho.etapas || []"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <div
          v-else-if="campo.peca === 'agente_de_ia'"
          class="flex flex-col gap-1.5"
          data-peca="agente_de_ia"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t(campo.rotulo) }}
          </span>
          <ChoiceSelect
            v-if="opcoes.agenteDeIa?.length"
            :model-value="rascunho[campo.nome] ?? ''"
            :aria-label="$t(campo.rotulo)"
            :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
            :options="opcoes.agenteDeIa"
            @update:model-value="novo => mudarNativo(campo.nome, novo)"
          />
          <p
            v-else-if="opcoes.agenteDeIaFalhou"
            class="mb-0 text-sm text-n-ruby-11"
            data-agentes-de-ia-falhou
          >
            {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.AGENTES_DE_IA_FALHOU') }}
          </p>
          <p
            v-else-if="opcoes.agenteDeIa"
            class="mb-0 text-sm text-n-slate-11"
            data-sem-agente-de-ia
          >
            {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_AGENTE_DE_IA') }}
          </p>
        </div>
        <LivreRetornoPara
          v-else-if="campo.peca === 'quem_recebe_retorno'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :opcoes="opcoes"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreRegistro
          v-else-if="campo.peca === 'registro_ligado'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          :escolhas="escolhasDoGatilho"
          :pode-ler-cards="podeLerCards"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreRetornoQuando
          v-else-if="campo.peca === 'quando_do_retorno'"
          :rotulo="$t(campo.rotulo)"
          :daqui="rascunho.daqui"
          :quando="rascunho.quando"
          :unidades="catalogo.unidades"
          @update="
            novo => {
              mudarNativo('daqui', novo.daqui);
              mudarNativo('quando', novo.quando);
            }
          "
        />
        <LivreRetornoEnvio
          v-else-if="campo.peca === 'envio_do_retorno'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <LivreDecidirDeNovo
          v-else-if="campo.peca === 'de_novo'"
          :rotulo="$t(campo.rotulo)"
          :model-value="rascunho[campo.nome]"
          :passo="rascunho"
          :unidades="catalogo.unidades"
          :esperas="esperasDoDecidir"
          @update:model-value="novo => mudarNativo(campo.nome, novo)"
        />
        <!-- Decisão 18: o sim/não de um passo fora da IA ("Cobrir a pessoa
        enquanto ela não responde", no "Passar para a agente de IA"). Desligado
        tira a chave da receita. -->
        <label
          v-else-if="campo.peca === 'sim_nao' && !ehDeIa"
          class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
          :data-peca="campo.nome"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t(campo.rotulo) }}
          </span>
          <Switch
            class="mx-1.5 scale-[1.4]"
            :model-value="Boolean(rascunho[campo.nome])"
            :aria-label="$t(campo.rotulo)"
            @update:model-value="novo => mudarNativo(campo.nome, novo || null)"
          />
        </label>
        <LivreIaCampo
          v-else-if="ehDeIa && campo.peca !== 'para_cada'"
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
        :key="`${aberturas}-${campo.nome}`"
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
        :por-mensagem="custoPorMensagem(receitaParaTestar, rascunho.id)"
        :pronto="podeSalvar"
        :automacao-id="automacaoId"
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
