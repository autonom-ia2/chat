<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AutomationAPI from 'dashboard/api/automation';
import Button from 'dashboard/components-next/button/Button.vue';
import { descreverAutomacao } from 'dashboard/helper/automacaoEmPortugues';
import AutomacaoHeroi from '../components/AutomacaoHeroi.vue';
import AutomacaoLinha from '../components/AutomacaoLinha.vue';
import AutomacaoModelos from '../components/AutomacaoModelos.vue';
import AutomacaoSugestao from '../components/AutomacaoSugestao.vue';
import { useNomesDaConta } from '../composables/useNomesDaConta';
import { useCriadasPeloGuia } from '../composables/useCriadasPeloGuia';

// #859/#982 — Automações no menu principal. Sem nenhuma: uma pergunta ("o que
// você quer que aconteça sozinho?") e as prontas. Com automações: cada uma como
// frase, com o interruptor e o selo de quem criou, mais o que o Guia notou.
// Criar é com o Guia (tela "nova"); o formulário antigo continua como modo
// manual.
const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const podeMudar = useCanManage('automation_manage');
const { nomes, carregarNomes } = useNomesDaConta();
const { criadas, carregarCriadas } = useCriadasPeloGuia();

const estado = ref('carregando');
const automacoes = ref([]);
const mudando = ref(null);

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const { data } = await AutomationAPI.get();
    automacoes.value = [...(data?.payload || [])].sort((a, b) => b.id - a.id);
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(() => {
  carregarNomes();
  carregarCriadas();
  carregar();
});

const linhas = computed(() =>
  automacoes.value.map(automacao => ({
    automacao,
    descricao: descreverAutomacao(automacao, { t, nomes: nomes.value }),
    criadaPeloGuia: criadas.value.has(automacao.id),
  }))
);

const ligadas = computed(
  () => automacoes.value.filter(automacao => automacao.active).length
);

const abrir = automacao =>
  router.push({
    name: 'automacoes_editar',
    params: { accountId: accountId.value, id: automacao.id },
  });

// O modelo vai na URL (só chaves conhecidas); o texto livre vai no estado da
// navegação, que um link de fora não consegue preencher: o pedido sai sozinho
// para o Guia, então só a própria tela pode escrevê-lo.
const nova = ({ modelo, pedido, anexos, porVoz } = {}) => {
  let estadoDaNavegacao = {};
  if (pedido) estadoDaNavegacao = { pedidoAutomacao: pedido };
  // Os prints e arquivos vão como arquivo (o navegador copia File no estado da
  // navegação); sobem só na tela do Guia.
  if (anexos?.length) {
    estadoDaNavegacao = { ...estadoDaNavegacao, anexosAutomacao: anexos };
  }
  if (porVoz) estadoDaNavegacao = { pedidoPorVoz: true };
  return router.push({
    name: 'automacoes_nova',
    params: { accountId: accountId.value },
    query: modelo ? { modelo } : {},
    state: estadoDaNavegacao,
  });
};

const modoManual = () =>
  router.push({
    name: 'automation_list',
    params: { accountId: accountId.value },
  });

const alternar = async automacao => {
  if (!podeMudar.value || mudando.value) return;
  const ligar = !automacao.active;
  mudando.value = automacao.id;
  try {
    await AutomationAPI.update(automacao.id, { active: ligar });
    automacoes.value = automacoes.value.map(item =>
      item.id === automacao.id ? { ...item, active: ligar } : item
    );
    useAlert(
      ligar ? t('AUTOMACOES.LISTA.LIGOU') : t('AUTOMACOES.LISTA.DESLIGOU')
    );
  } catch {
    useAlert(t('AUTOMACOES.LISTA.FALHA_TROCA'));
  } finally {
    mudando.value = null;
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-8 px-5 py-8 mx-auto max-w-6xl md:px-8 md:py-10"
      >
        <div
          v-if="estado === 'carregando'"
          data-carregando
          aria-busy="true"
          class="flex flex-col gap-4"
        >
          <span class="sr-only">{{ $t('AUTOMACOES.LISTA.CARREGANDO') }}</span>
          <div class="h-56 rounded-3xl bg-n-alpha-2 animate-pulse" />
          <div
            v-for="indice in 3"
            :key="indice"
            class="h-24 rounded-2xl bg-n-alpha-2 animate-pulse"
          />
        </div>

        <div
          v-else-if="estado === 'erro'"
          data-erro
          role="alert"
          class="flex flex-col items-start gap-4 p-8 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <span
            class="grid place-items-center size-12 rounded-xl bg-n-ruby-3 text-n-ruby-11"
          >
            <span class="i-lucide-wifi-off size-6" aria-hidden="true" />
          </span>
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('AUTOMACOES.LISTA.ERRO') }}
          </p>
          <Button
            :label="$t('AUTOMACOES.LISTA.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="min-h-11"
            @click="carregar"
          />
        </div>

        <template v-else-if="!linhas.length">
          <div data-vazio class="contents">
            <AutomacaoHeroi
              :desabilitado="!podeMudar"
              @pedir="({ texto, anexos }) => nova({ pedido: texto, anexos })"
              @falar="nova({ porVoz: true })"
            />
            <section class="flex flex-col gap-5">
              <div>
                <h2
                  class="text-2xl font-semibold tracking-tight text-n-slate-12"
                >
                  {{ $t('AUTOMACOES.LISTA.VAZIO_TITULO') }}
                </h2>
                <p class="mb-0 mt-1.5 text-base text-n-slate-11">
                  {{ $t('AUTOMACOES.LISTA.VAZIO_TEXTO') }}
                </p>
              </div>
              <AutomacaoModelos
                :desabilitado="!podeMudar"
                @escolher="modelo => nova({ modelo })"
              />
            </section>
            <p
              v-if="podeMudar"
              class="mb-0 text-[0.9375rem] text-center text-n-slate-11"
            >
              {{ $t('AUTOMACOES.LISTA.PREFERE_MANUAL') }}
              <button
                type="button"
                data-modo-manual
                class="font-medium text-n-blue-11 hover:underline min-h-11"
                @click="modoManual"
              >
                {{ $t('AUTOMACOES.LISTA.USAR_MANUAL') }}
              </button>
            </p>
          </div>
        </template>

        <template v-else>
          <header class="flex flex-wrap items-end justify-between gap-5">
            <div class="min-w-0">
              <h1
                class="text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
              >
                {{ $t('AUTOMACOES.LISTA.TITULO') }}
              </h1>
              <p class="mb-0 mt-2 text-base md:text-lg text-n-slate-11">
                {{ $t('AUTOMACOES.LISTA.SUBTITULO') }}
              </p>
            </div>
            <Button
              v-if="podeMudar"
              data-nova
              :label="$t('AUTOMACOES.LISTA.NOVA')"
              icon="i-lucide-plus"
              size="lg"
              class="!min-h-12 !rounded-xl"
              @click="nova()"
            />
          </header>

          <div data-contagem class="flex flex-wrap gap-3">
            <span
              class="inline-flex items-center gap-2.5 px-4 py-2.5 text-[0.9375rem] border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <span
                class="rounded-full size-2.5 bg-n-teal-9"
                aria-hidden="true"
              />
              {{
                $t('AUTOMACOES.LISTA.CONTAGEM_LIGADAS', { n: ligadas }, ligadas)
              }}
            </span>
            <span
              class="inline-flex items-center gap-2.5 px-4 py-2.5 text-[0.9375rem] border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <span
                class="rounded-full size-2.5 bg-n-slate-8"
                aria-hidden="true"
              />
              {{
                $t(
                  'AUTOMACOES.LISTA.CONTAGEM_DESLIGADAS',
                  { n: linhas.length - ligadas },
                  linhas.length - ligadas
                )
              }}
            </span>
          </div>

          <AutomacaoSugestao
            v-if="podeMudar"
            :account-id="accountId"
            @aceitar="pedido => nova({ pedido })"
          />

          <ul class="flex flex-col gap-3.5 p-0 m-0 list-none">
            <AutomacaoLinha
              v-for="linha in linhas"
              :key="linha.automacao.id"
              :automacao="linha.automacao"
              :descricao="linha.descricao"
              :criada-pelo-guia="linha.criadaPeloGuia"
              :pode-mudar="podeMudar"
              :mudando="mudando === linha.automacao.id"
              @abrir="abrir(linha.automacao)"
              @alternar="alternar(linha.automacao)"
            />
          </ul>
        </template>
      </div>
    </main>
  </section>
</template>
