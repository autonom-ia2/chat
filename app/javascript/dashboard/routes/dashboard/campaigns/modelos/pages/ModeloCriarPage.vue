<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import api from '../api/modelosWhatsapp';
import { CAMPOS, ETAPAS_DA_CRIACAO, formatoPorChave } from '../constants';
import {
  conferirConteudo,
  copiarRascunho,
  podeEnviar,
  camposUsados,
  lerTextoComCampos,
  rascunhoDoObjetivo,
} from '../helpers/conteudo';
import { rascunhoDoFormato } from '../helpers/formatos';
import { exemploDoCampo } from '../helpers/campos';
import { useCanUseIA } from '../helpers/useCanUseIA';
import AgenteGaveta from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue';
import { diaEMes, hora } from '../helpers/datas';
import ModeloCelular from '../components/ModeloCelular.vue';
import ModeloConferencia from '../components/ModeloConferencia.vue';
import ModeloEtapas from '../components/ModeloEtapas.vue';
import ModeloUsos from '../components/ModeloUsos.vue';
import EtapaConfira from '../components/criar/EtapaConfira.vue';
import EtapaExtras from '../components/criar/EtapaExtras.vue';
import EtapaNumeros from '../components/criar/EtapaNumeros.vue';
import EtapaObjetivo from '../components/criar/EtapaObjetivo.vue';
import EtapaCartoes from '../components/criar/EtapaCartoes.vue';
import EtapaCriarComIA from '../components/criar/EtapaCriarComIA.vue';
import EtapaCatalogo from '../components/criar/EtapaCatalogo.vue';
import EtapaCodigo from '../components/criar/EtapaCodigo.vue';
import EtapaFormulario from '../components/criar/EtapaFormulario.vue';
import EtapaOferta from '../components/criar/EtapaOferta.vue';
import EtapaTexto from '../components/criar/EtapaTexto.vue';

// Criar (jornada 2), duplicar e alterar/corrigir (jornadas 3 e 4) usam a mesma
// tela: Objetivo → Texto → Extras → Números → Confira. A etapa fica na query
// (?etapa=), então voltar do navegador volta uma etapa.
const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();

const estado = ref('carregando');
const numeros = ref([]);
const modelo = ref(null);
const usos = ref([]);
const rascunho = ref(null);
const enviando = ref(false);
const catalogo = ref(null);
const formularios = ref([]);
const verPrevia = ref(false);
// "Criar com IA" é a entrega E (#1333): escondido até lá.
const podeUsarIA = useCanUseIA();

const alterando = computed(() => route.name === 'modelos_whatsapp_alterar');

const modo = computed(() => {
  if (alterando.value) {
    return modelo.value?.situacao === 'recusado' ? 'corrigir' : 'alterar';
  }
  return route.query.de ? 'duplicar' : 'novo';
});

// Alterar não troca a conta do WhatsApp, então não tem a etapa Números.
const etapas = computed(() => {
  if (alterando.value) return ['texto', 'extras', 'confira'];
  return modo.value === 'duplicar'
    ? ETAPAS_DA_CRIACAO.filter(etapa => etapa !== 'objetivo')
    : ETAPAS_DA_CRIACAO;
});

const etapa = computed(() => {
  if (!rascunho.value) return 'objetivo';
  const pedida = route.query.etapa;
  return etapas.value.includes(pedida)
    ? pedida
    : etapas.value.find(item => item !== 'objetivo');
});

// Vindo da campanha (?from=campaign&caixa=), a conta da caixa já vem escolhida.
const ORIGEM = ['from', 'caixa'];
const origem = () =>
  Object.fromEntries(
    ORIGEM.filter(chave => route.query[chave]).map(chave => [
      chave,
      route.query[chave],
    ])
  );

const numerosDaPrimeiraConta = lista => {
  const daCaixa = lista.find(item => item.id === Number(route.query.caixa));
  const conta = (daCaixa || lista[0])?.conta.id;
  return lista.filter(item => item.conta.id === conta).map(item => item.id);
};

const doModelo = dados =>
  copiarRascunho({
    nome: dados.nome,
    objetivo: dados.objetivo,
    biblioteca: dados.biblioteca,
    tipo: dados.tipo,
    numeros: dados.numeros,
    conteudo: dados.conteudo,
  });

// Rascunho novo de um formato (carrossel, oferta…), com os exemplos já preenchidos.
const doFormato = chave => ({
  ...rascunhoDoFormato(chave, {
    t,
    ler: fonte => lerTextoComCampos(fonte, CAMPOS),
    exemplosDe: texto =>
      Object.fromEntries(
        camposUsados(texto).map(campo => [campo, exemploDoCampo(t, campo)])
      ),
  }),
  numeros: numerosDaPrimeiraConta(numeros.value),
});

// Rascunho pedido pelo endereço (?objetivo= ou ?formato=), com os textos prontos.
const rascunhoDaQuery = () => {
  const formatoPedido = formatoPorChave(route.query.formato);
  if (formatoPedido && formatoPedido.disponivel !== false) {
    return doFormato(route.query.formato);
  }
  if (!route.query.objetivo) return null;
  return {
    ...rascunhoDoObjetivo(route.query.objetivo, { t, campos: CAMPOS }),
    numeros: numerosDaPrimeiraConta(numeros.value),
  };
};
// O idioma da conta pode chegar depois da tela: o rascunho que ninguém mexeu
// ainda é refeito no idioma certo.
let montadoDaQuery = '';

const carregar = async () => {
  estado.value = 'carregando';
  rascunho.value = null;
  modelo.value = null;
  try {
    [numeros.value, catalogo.value, formularios.value] = await Promise.all([
      api.listarNumeros(),
      api.obterCatalogo(),
      api.listarFormularios(),
    ]);
    const id = alterando.value ? route.params.id : route.query.de;
    if (id) {
      modelo.value = await api.obterModelo(id);
      usos.value = alterando.value ? await api.ondeEstaEmUso(id) : [];
      // Modelo em uso não muda (a API recusa): a tela mostra onde, em vez do formulário.
      if (alterando.value && usos.value.length) {
        estado.value = 'em_uso';
        return;
      }
      const base = doModelo(modelo.value);
      rascunho.value = alterando.value
        ? base
        : {
            ...base,
            nome: t('MODELOS_WHATSAPP.CRIAR.COPIA_DE', { nome: base.nome }),
          };
    } else {
      rascunho.value = rascunhoDaQuery();
      montadoDaQuery = rascunho.value ? JSON.stringify(rascunho.value) : '';
    }
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(carregar);
// Novo e alterar usam este mesmo componente: trocar de rota recarrega.
watch(() => route.name, carregar);
watch(locale, () => {
  if (!montadoDaQuery || JSON.stringify(rascunho.value) !== montadoDaQuery)
    return;
  rascunho.value = rascunhoDaQuery();
  montadoDaQuery = JSON.stringify(rascunho.value);
});

const ir = proxima =>
  router.replace({ query: { ...route.query, etapa: proxima } });

const escolherObjetivo = chave => {
  rascunho.value = {
    ...rascunhoDoObjetivo(chave, { t, campos: CAMPOS }),
    numeros: numerosDaPrimeiraConta(numeros.value),
  };
  router.replace({ query: { ...origem(), objetivo: chave, etapa: 'texto' } });
};

// Criar com IA: abre na própria etapa Objetivo (?ia=1); "Usar esta" vira o rascunho.
const abrirIA = () => router.replace({ query: { ...origem(), ia: '1' } });
const fecharIA = () => router.replace({ query: origem() });
const usarOpcaoDaIA = opcao => {
  rascunho.value = {
    nome: opcao.nome,
    objetivo: 'em_branco',
    biblioteca: false,
    tipo: opcao.tipo,
    numeros: numerosDaPrimeiraConta(numeros.value),
    conteudo: opcao.conteudo,
  };
  router.replace({ query: { ...origem(), etapa: 'texto' } });
};

const escolherFormato = chave => {
  rascunho.value = doFormato(chave);
  router.replace({ query: { ...origem(), formato: chave, etapa: 'texto' } });
};

const formato = computed(() => rascunho.value?.conteudo.formato || 'padrao');
const contexto = computed(() => ({ temCatalogo: Boolean(catalogo.value) }));

// No carrossel, a etapa "Extras" vira "Cartões"; na oferta, "Oferta"; e assim por diante.
const rotulos = computed(() =>
  formato.value === 'padrao'
    ? {}
    : { extras: t(`MODELOS_WHATSAPP.FORMATOS.${formato.value}.ETAPA`) }
);

// O que aparece no Confira na linha da etapa própria do formato.
const resumoDoFormato = computed(() => {
  const conteudo = rascunho.value?.conteudo;
  if (!conteudo || formato.value === 'padrao') return '';
  const falta = t('MODELOS_WHATSAPP.CONFIRA.FALTA_PREENCHER');
  const resumos = {
    carrossel: () => {
      const n = conteudo.cartoes.length;
      return t('MODELOS_WHATSAPP.CONFIRA.CARTOES', { n }, n);
    },
    oferta: () => conteudo.oferta.titulo || falta,
    catalogo: () => catalogo.value?.nome || falta,
    codigo: () =>
      t('MODELOS_WHATSAPP.CONFIRA.CODIGO', {
        botao: t(
          `MODELOS_WHATSAPP.FORMATOS.codigo.BOTOES.${conteudo.codigo.botao}`
        ),
        n: conteudo.codigo.validade,
      }),
    formulario: () =>
      formularios.value.find(item => item.id === conteudo.formulario.id)
        ?.nome || falta,
  };
  return resumos[formato.value]();
});

const indice = computed(() => etapas.value.indexOf(etapa.value));
const anterior = computed(() => etapas.value[indice.value - 1]);
const proxima = computed(() => etapas.value[indice.value + 1]);

const podeSeguir = computed(() => {
  if (!rascunho.value) return false;
  if (etapa.value === 'texto') {
    const temTexto =
      formato.value === 'codigo' || rascunho.value.conteudo.texto.length > 0;
    return Boolean(rascunho.value.nome.trim() && temTexto);
  }
  if (etapa.value === 'numeros') return rascunho.value.numeros.length > 0;
  if (etapa.value === 'confira') {
    return (
      podeEnviar(rascunho.value.conteudo, contexto.value) &&
      rascunho.value.numeros.length > 0
    );
  }
  return true;
});

const terminaComCampo = computed(
  () =>
    modo.value === 'corrigir' &&
    conferirConteudo(rascunho.value.conteudo).find(
      item => item.chave === 'NAO_TERMINA_COM_CAMPO'
    )?.ok === false
);

const remetente = computed(() => {
  const escolhido = numeros.value.find(item =>
    rascunho.value?.numeros.includes(item.id)
  );
  return (escolhido || numeros.value[0])?.conta.nome || '';
});

const voltarPara = computed(() => {
  if (route.query.from === 'campaign') {
    return { name: 'campaigns_journey_new', query: { returned: '1' } };
  }
  return alterando.value || route.query.de
    ? {
        name: 'modelos_whatsapp_modelo',
        params: { id: route.params.id || route.query.de },
      }
    : { name: 'modelos_whatsapp_lista' };
});

const enviar = async () => {
  enviando.value = true;
  try {
    // Criar devolve um modelo por conta do WhatsApp (cada conta faz a sua análise).
    const opcoes = {
      textos: { botaoDaOferta: t('MODELOS_WHATSAPP.FORMATOS.oferta.BOTAO') },
    };
    const salvos = alterando.value
      ? [await api.alterarModelo(route.params.id, rascunho.value, opcoes)]
      : await api.criarModelo(rascunho.value, opcoes);
    // Uma conta do WhatsApp criou e a outra não: segue com a criada e diz o que faltou.
    if (salvos.falha) {
      useAlert(
        t('MODELOS_WHATSAPP.CRIAR.FALHOU_UMA_CONTA', {
          motivo: salvos.falha.mensagem || '',
        })
      );
    }
    router.push({
      name: 'modelos_whatsapp_enviado',
      query: {
        ...origem(),
        ids: salvos.map(salvo => salvo.id).join(','),
        modo: modo.value,
      },
    });
  } catch (erro) {
    // O servidor já manda o motivo traduzido (nome repetido, em uso, a Meta recusou).
    useAlert(erro.mensagem || t('MODELOS_WHATSAPP.CRIAR.FALHOU'));
  } finally {
    enviando.value = false;
  }
};

const rotuloDoEnvio = computed(() =>
  t(`MODELOS_WHATSAPP.CRIAR.ENVIAR.${modo.value}`)
);

const proximaAlteracao = computed(() => {
  const liberadaEm = modelo.value?.edicoes?.liberadaEm;
  return liberadaEm
    ? {
        dia: diaEMes(liberadaEm, locale.value),
        hora: hora(liberadaEm, locale.value),
      }
    : null;
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-6 px-5 pt-8 pb-24 mx-auto max-w-6xl md:px-8 md:py-10"
      >
        <router-link
          :to="voltarPara"
          class="inline-flex items-center self-start gap-2 text-[0.9375rem] font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
          {{ $t('MODELOS_WHATSAPP.CRIAR.CANCELAR') }}
        </router-link>

        <div
          v-if="estado === 'carregando'"
          aria-busy="true"
          class="h-96 rounded-3xl bg-n-alpha-2 animate-pulse"
        >
          <span class="sr-only">{{ $t('MODELOS_WHATSAPP.CARREGANDO') }}</span>
        </div>

        <p
          v-else-if="estado === 'erro'"
          role="alert"
          class="p-8 mb-0 text-base border rounded-2xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ $t('MODELOS_WHATSAPP.ERRO') }}
        </p>

        <section
          v-else-if="estado === 'em_uso'"
          data-alterar-em-uso
          class="flex flex-col gap-4 p-6 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
        >
          <h1 class="m-0 text-2xl font-bold tracking-tight text-n-slate-12">
            {{
              $t('MODELOS_WHATSAPP.ALTERAR.EM_USO_TITULO', {
                nome: modelo.nome,
              })
            }}
          </h1>
          <p class="mb-0 text-[0.9375rem] text-n-slate-12">
            {{ $t('MODELOS_WHATSAPP.ALTERAR.EM_USO_TEXTO') }}
          </p>
          <ModeloUsos :usos="usos" sem-moldura sem-titulo />
          <Button
            data-duplicar-em-uso
            :label="$t('MODELOS_WHATSAPP.ACOES.DUPLICAR')"
            icon="i-lucide-copy"
            class="self-start !min-h-11 !rounded-xl"
            @click="
              router.push({
                name: 'modelos_whatsapp_novo',
                query: { de: modelo.id, etapa: 'texto' },
              })
            "
          />
        </section>

        <template v-else>
          <header class="flex flex-col gap-5">
            <h1
              class="m-0 text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
            >
              {{ $t(`MODELOS_WHATSAPP.CRIAR.TITULO.${modo}`) }}
            </h1>
            <ModeloEtapas
              :etapas="etapas"
              :atual="etapa"
              :rotulos="rotulos"
              @ir="ir"
            />
          </header>

          <section
            v-if="modo === 'corrigir' && etapa !== 'confira'"
            data-aviso-correcao
            class="flex flex-col gap-2 p-5 rounded-2xl bg-n-ruby-2 ring-1 ring-inset ring-n-ruby-6"
          >
            <h2 class="m-0 text-base font-semibold text-n-ruby-11">
              {{
                $t(
                  `MODELOS_WHATSAPP.RECUSAS.${modelo.recusa?.codigo || 'outro'}.TITULO`
                )
              }}
            </h2>
            <p class="mb-0 text-[0.9375rem] text-n-slate-12">
              <strong class="font-semibold">{{
                $t('MODELOS_WHATSAPP.MODELO.COMO_RESOLVER')
              }}</strong>
              {{
                $t(
                  `MODELOS_WHATSAPP.RECUSAS.${modelo.recusa?.codigo || 'outro'}.COMO_RESOLVER`
                )
              }}
            </p>
          </section>

          <section
            v-if="modo === 'alterar' && etapa === 'texto'"
            data-aviso-alteracao
            class="flex flex-col gap-4 p-5 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
          >
            <ul
              class="flex flex-col gap-1.5 p-0 m-0 list-none text-[0.9375rem] text-n-slate-12"
            >
              <li>{{ $t('MODELOS_WHATSAPP.ALTERAR.VOLTA_PARA_ANALISE') }}</li>
              <li>
                {{
                  modelo.edicoes.restantesNoMes == null
                    ? $t('MODELOS_WHATSAPP.ALTERAR.REGRA')
                    : $t(
                        'MODELOS_WHATSAPP.ALTERAR.LIMITE',
                        { n: modelo.edicoes.restantesNoMes },
                        modelo.edicoes.restantesNoMes
                      )
                }}
              </li>
              <li v-if="proximaAlteracao">
                {{
                  $t('MODELOS_WHATSAPP.MODELO.ALTERAR_DEPOIS', proximaAlteracao)
                }}
              </li>
            </ul>
            <ModeloUsos v-if="usos.length" :usos="usos" sem-moldura />
          </section>

          <section
            v-if="modo === 'duplicar' && etapa === 'texto'"
            data-aviso-copia
            class="flex gap-3 p-5 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-5"
          >
            <span
              class="i-lucide-copy size-5 mt-0.5 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />
            <p class="mb-0 text-[0.9375rem] text-n-slate-12">
              {{
                $t('MODELOS_WHATSAPP.CRIAR.AVISO_COPIA', { nome: modelo.nome })
              }}
            </p>
          </section>

          <EtapaCriarComIA
            v-if="podeUsarIA && etapa === 'objetivo' && route.query.ia === '1'"
            :numeros="numeros.map(numero => numero.id)"
            :remetente="remetente"
            @usar="usarOpcaoDaIA"
            @voltar="fecharIA"
            @meu-jeito="escolherObjetivo('em_branco')"
          />
          <EtapaObjetivo
            v-else-if="etapa === 'objetivo'"
            @escolher="escolherObjetivo"
            @formato="escolherFormato"
            @ia="abrirIA"
          />

          <div
            v-else
            class="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_20rem]"
          >
            <div class="flex flex-col min-w-0 gap-6">
              <Button
                data-ver-como-fica
                :label="$t('MODELOS_WHATSAPP.CELULAR.VER_COMO_FICA')"
                icon="i-lucide-smartphone"
                color="slate"
                variant="faded"
                class="self-start min-h-11 lg:!hidden"
                @click="verPrevia = true"
              />
              <template v-if="etapa === 'texto'">
                <EtapaTexto
                  v-model:rascunho="rascunho"
                  :destacar-fim="terminaComCampo"
                />
                <ModeloConferencia
                  v-if="modo === 'corrigir'"
                  :conteudo="rascunho.conteudo"
                  :contexto="contexto"
                />
              </template>
              <template v-else-if="etapa === 'extras'">
                <EtapaCartoes
                  v-if="formato === 'carrossel'"
                  v-model:rascunho="rascunho"
                />
                <EtapaOferta
                  v-else-if="formato === 'oferta'"
                  v-model:rascunho="rascunho"
                />
                <EtapaCatalogo
                  v-else-if="formato === 'catalogo'"
                  :catalogo="catalogo"
                />
                <EtapaCodigo
                  v-else-if="formato === 'codigo'"
                  v-model:rascunho="rascunho"
                />
                <EtapaFormulario
                  v-else-if="formato === 'formulario'"
                  v-model:rascunho="rascunho"
                  :formularios="formularios"
                />
                <EtapaExtras v-else v-model:rascunho="rascunho" />
              </template>
              <EtapaNumeros
                v-else-if="etapa === 'numeros'"
                v-model:rascunho="rascunho"
                :numeros="numeros"
              />
              <EtapaConfira
                v-else
                :rascunho="rascunho"
                :numeros="numeros"
                :etapas="etapas"
                :rotulos="rotulos"
                :contexto="contexto"
                :resumo-do-formato="resumoDoFormato"
                @ir="ir"
              />

              <nav
                class="flex flex-wrap items-center justify-between gap-3 pt-6 border-t border-n-weak"
                :aria-label="$t('MODELOS_WHATSAPP.ETAPAS.ROTULO')"
              >
                <Button
                  v-if="anterior"
                  data-voltar
                  :label="$t('MODELOS_WHATSAPP.CRIAR.VOLTAR')"
                  icon="i-lucide-arrow-left"
                  color="slate"
                  variant="ghost"
                  class="min-h-11"
                  @click="ir(anterior)"
                />
                <span v-else />
                <Button
                  v-if="proxima"
                  data-continuar
                  :label="$t('MODELOS_WHATSAPP.CRIAR.CONTINUAR')"
                  icon="i-lucide-arrow-right"
                  trailing-icon
                  size="lg"
                  class="!min-h-12 !rounded-xl"
                  :disabled="!podeSeguir"
                  @click="ir(proxima)"
                />
                <Button
                  v-else
                  data-enviar
                  :label="rotuloDoEnvio"
                  icon="i-lucide-send"
                  size="lg"
                  class="!min-h-12 !rounded-xl"
                  :disabled="!podeSeguir"
                  :is-loading="enviando"
                  @click="enviar"
                />
              </nav>
            </div>

            <aside class="flex-col hidden gap-2 lg:flex lg:sticky lg:top-6">
              <p class="mb-0 text-sm font-medium text-center text-n-slate-11">
                {{ $t('MODELOS_WHATSAPP.CELULAR.TITULO') }}
              </p>
              <ModeloCelular
                :conteudo="rascunho.conteudo"
                :remetente="remetente"
              />
            </aside>
          </div>

          <AgenteGaveta
            v-if="verPrevia"
            :titulo="$t('MODELOS_WHATSAPP.CELULAR.TITULO')"
            @fechar="verPrevia = false"
          >
            <ModeloCelular
              data-previa-gaveta
              :conteudo="rascunho.conteudo"
              :remetente="remetente"
              compacto
            />
          </AgenteGaveta>
        </template>
      </div>
    </main>
  </section>
</template>
