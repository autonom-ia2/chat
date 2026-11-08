<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { LOCK_REASONS } from 'dashboard/helper/peopleAccess';
import AgenteGaveta from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue';
import DialogoDaCasa from '../guiada/DialogoDaCasa.vue';
import { useTextos } from '../guiada/useTextos';
import { useSemFuncao } from '../useSemFuncao';
import PessoaDaFuncao from './PessoaDaFuncao.vue';
import RodapeDaGaveta from './RodapeDaGaveta.vue';
import { useSalvarGaveta } from './useSalvarGaveta';

// Quem usa uma função, ou quem está sem função (#2308, especificação 5.D). Com `funcao`: "Quem vai ser …?", com quem
// já é e as outras pessoas; sem ela: "Quem está sem função", uma escolha por pessoa. Nada grava até "Salvar";
// "Cancelar" descarta; Esc, o X e o clique no fundo, com mudança pendente, perguntam antes. Enquanto salva, nada fecha
// (Cancelar, Esc, X e fundo ficam travados) e o botão diz "Salvando…". O salvar e a conferência moram
// em useSalvarGaveta; se algo falha, a gaveta fica aberta só com o que não gravou e diz de quem e por quê. Sem
// Pessoas, numa função fora do alcance ou na própria função, a gaveta só mostra quem é, com o motivo certo. Quem perde
// Pessoas no meio do salvar vê o porquê no rodapé (rodada 4). A função vem como cópia de quando abriu; título, trava
// e "Pôr como" leem a função de agora na lista, pelo id: apagada ou fora do alcance em paralelo, a gaveta vira só
// leitura e o pendente sai (rodada 8). Mudar ou desfazer apaga o aviso antigo. Rodapé e avisos: RodapeDaGaveta.
const props = defineProps({
  funcao: { type: Object, default: null },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const { lista } = useTextos();
const { canManagePeople, memberLockReason, roleLockReason, reachesRole } =
  usePeopleAccess();
const { efeitoDe, semFuncaoTravado } = useSemFuncao();
const agentes = useMapGetter('agents/getAgents');
const funcoes = useMapGetter('customRole/getCustomRoles');

const mudancas = ref(new Map());
const sairSemSalvar = ref(null);

// A função da gaveta como está na lista agora; null quando a gaveta é de quem está sem função, ou se ela foi apagada.
const funcaoAtual = computed(() =>
  props.funcao
    ? funcoes.value.find(funcao => funcao.id === props.funcao.id) || null
    : null
);
const apagada = computed(() => Boolean(props.funcao) && !funcaoAtual.value);
const nomeDaFuncao = computed(
  () => funcaoAtual.value?.name ?? props.funcao?.name
);

// Por que a gaveta é só leitura: a função foi apagada, sem Pessoas, ou a função está acima do alcance (ABOVE) ou é a
// de quem monta (MINE).
const motivoDaLeitura = computed(() => {
  if (apagada.value) return 'SO_LEITURA_APAGADA';
  if (!canManagePeople.value) return 'SO_LEITURA';
  const trava = funcaoAtual.value && roleLockReason(funcaoAtual.value);
  return trava ? `SO_LEITURA_${trava}` : '';
});
const somenteLeitura = computed(() => Boolean(motivoDaLeitura.value));

const porNome = (a, b) => a.name.localeCompare(b.name);
const daFuncao = pessoa => pessoa.custom_role_id === props.funcao?.id;
const jaSao = computed(() => agentes.value.filter(daFuncao).sort(porNome));
const outras = computed(() =>
  agentes.value.filter(pessoa => !daFuncao(pessoa)).sort(porNome)
);
const estaSemFuncao = pessoa =>
  pessoa.role === 'agent' && !pessoa.custom_role_id;
const semFuncao = computed(() =>
  agentes.value.filter(estaSemFuncao).sort(porNome)
);
// Quem a gaveta mostra: a de uma função mostra todo mundo; a de quem está sem função, só essas pessoas.
const naLista = pessoa => Boolean(props.funcao) || estaSemFuncao(pessoa);

const funcaoDe = id => funcoes.value.find(funcao => funcao.id === id) || null;
// Administrador já pode tudo: uma função só esconderia telas dele.
const travaDe = pessoa =>
  pessoa.role === 'administrator'
    ? LOCK_REASONS.ADMIN
    : memberLockReason(pessoa) || '';
const {
  salvando,
  aviso,
  salvar: gravar,
  limparAviso,
} = useSalvarGaveta(mudancas, { travaDe, naLista, somenteLeitura });
const temAviso = computed(
  () => Boolean(aviso.value.salva) || aviso.value.problemas.length > 0
);

// Só leitura no meio (função apagada, fora do alcance, sem Pessoas; no salvar ou por uma recarga de fora): nada fica
// pendente.
watch(somenteLeitura, agora => {
  if (agora) mudancas.value = new Map();
});

// Só as funções que quem monta pode dar; as outras somem da escolha, com o nome numa nota.
const opcoes = computed(() =>
  funcoes.value
    .filter(funcao => funcao.id !== props.funcao?.id && reachesRole(funcao))
    .map(funcao => ({ value: funcao.id, label: funcao.name }))
);
const escondidas = computed(() =>
  funcoes.value.filter(funcao => !reachesRole(funcao)).map(item => item.name)
);

const mudar = (pessoa, destino) => {
  limparAviso();
  mudancas.value = new Map([...mudancas.value, [pessoa.id, destino]]);
};
const desfazer = pessoa => {
  limparAviso();
  mudancas.value = new Map(
    [...mudancas.value].filter(([id]) => id !== pessoa.id)
  );
};

const linha = pessoa => ({
  pessoa,
  atual: funcaoDe(pessoa.custom_role_id),
  destino: mudancas.value.get(pessoa.id),
  nomeDoDestino: funcaoDe(mudancas.value.get(pessoa.id))?.name || '',
  trava: travaDe(pessoa),
  somenteLeitura: somenteLeitura.value,
  salvando: salvando.value,
  opcoes: opcoes.value,
  alvo: funcaoAtual.value,
  semFuncaoTravado: semFuncaoTravado.value,
});

const nomeDe = id => agentes.value.find(item => item.id === id)?.name;

// Quem fica sem função: a mesma frase da linha da pessoa (efeitoDe), com o primeiro ganho, a perda que mais pesa e o
// que só o administrador daria (os R$) (revisão do #2308, rodada 4).
const RODAPE_SEM_FUNCAO = {
  ganhoEPerda: 'FICA_SEM_E_DEIXA',
  ganho: 'FICA_SEM',
  perda: 'FICA_SEM_DEIXA',
  nada: 'FICA_SEM_SO',
};
const fraseDoRodape = ([id, destino]) => {
  const pessoa = nomeDe(id);
  if (destino !== null)
    return t('FUNCOES_EQUIPE.GAVETA.RODAPE.PASSA_A_SER', {
      pessoa,
      funcao: funcaoDe(destino)?.name,
    });
  const atual = agentes.value.find(item => item.id === id)?.custom_role_id;
  const { forma, ganho, perda, tambem } = efeitoDe(
    funcaoDe(atual)?.permissions
  );
  return [
    t(`FUNCOES_EQUIPE.GAVETA.RODAPE.${RODAPE_SEM_FUNCAO[forma]}`, {
      pessoa,
      ganho,
      perda,
    }),
    ...tambem,
  ].join(' ');
};
const frases = computed(() => [...mudancas.value].map(fraseDoRodape));

// Apagada, a função não tem mais quem "vai ser": o título fica só com o nome (rodada 9).
const titulo = computed(() => {
  if (!props.funcao) return t('FUNCOES_EQUIPE.GAVETA.TITULO_SEM_FUNCAO');
  if (apagada.value) return nomeDaFuncao.value;
  return t('FUNCOES_EQUIPE.GAVETA.TITULO', { nome: nomeDaFuncao.value });
});

const podeFechar = () => {
  if (salvando.value) return false;
  if (!mudancas.value.size) return true;
  sairSemSalvar.value?.abrir();
  return false;
};

const salvar = async () => {
  if (!(await gravar())) return;
  useAlert(t('FUNCOES_EQUIPE.GAVETA.SALVO'));
  emit('fechar');
};
</script>

<template>
  <AgenteGaveta
    :titulo="titulo"
    :pode-fechar="podeFechar"
    guarda-no-x
    @fechar="emit('fechar')"
  >
    <template v-if="!funcao">
      <p class="m-0 text-[0.9375rem] text-n-slate-11">
        {{ $t('FUNCOES_EQUIPE.FAIXA.TEXTO', semFuncao.length) }}
      </p>
      <ul data-sem-funcao class="flex flex-col gap-1 p-0 m-0 list-none">
        <PessoaDaFuncao
          v-for="pessoa in semFuncao"
          :key="pessoa.id"
          modo="sem"
          v-bind="linha(pessoa)"
          @mudar="destino => mudar(pessoa, destino)"
          @desfazer="desfazer(pessoa)"
        />
      </ul>
    </template>
    <template v-else>
      <p
        v-if="somenteLeitura"
        data-so-leitura
        class="flex items-start gap-2 m-0 text-sm text-n-slate-11"
      >
        <span class="i-lucide-info size-4 mt-0.5 shrink-0" aria-hidden="true" />
        {{
          $t(`FUNCOES_EQUIPE.GAVETA.${motivoDaLeitura}`, { nome: nomeDaFuncao })
        }}
      </p>
      <p
        v-if="!apagada && !jaSao.length"
        data-ninguem-ainda
        class="m-0 text-[0.9375rem] text-n-slate-11"
      >
        {{ $t('FUNCOES_EQUIPE.GAVETA.NINGUEM_AINDA') }}
      </p>
      <section v-else-if="!apagada" class="flex flex-col gap-1">
        <h3 class="m-0 text-sm font-semibold text-n-slate-11">
          {{
            $t('FUNCOES_EQUIPE.GAVETA.JA_SAO', {
              nome: nomeDaFuncao,
              n: jaSao.length,
            })
          }}
        </h3>
        <ul data-ja-sao class="flex flex-col gap-1 p-0 m-0 list-none">
          <PessoaDaFuncao
            v-for="pessoa in jaSao"
            :key="pessoa.id"
            modo="ja"
            v-bind="linha(pessoa)"
            @mudar="destino => mudar(pessoa, destino)"
            @desfazer="desfazer(pessoa)"
          />
        </ul>
      </section>
      <section v-if="!somenteLeitura" class="flex flex-col gap-1">
        <h3 class="m-0 text-sm font-semibold text-n-slate-11">
          {{ $t('FUNCOES_EQUIPE.GAVETA.OUTRAS') }}
        </h3>
        <ul data-outras class="flex flex-col gap-1 p-0 m-0 list-none">
          <PessoaDaFuncao
            v-for="pessoa in outras"
            :key="pessoa.id"
            modo="outra"
            v-bind="linha(pessoa)"
            @mudar="destino => mudar(pessoa, destino)"
            @desfazer="desfazer(pessoa)"
          />
        </ul>
      </section>
    </template>
    <p
      v-if="escondidas.length && !somenteLeitura"
      data-escondidas
      class="flex items-start gap-2 m-0 text-sm text-n-slate-11"
    >
      <span class="i-lucide-lock size-4 mt-0.5 shrink-0" aria-hidden="true" />
      {{
        $t(
          'FUNCOES_EQUIPE.GAVETA.ESCONDIDAS',
          { nomes: lista(escondidas) },
          escondidas.length
        )
      }}
    </p>

    <!-- O rodapé fica na tela enquanto salva: o status do "foi salva" não nasce de novo se a gaveta virar só leitura
    no meio do salvar. A gaveta que já abre só leitura não tem rodapé (rodada 9). -->
    <template v-if="!somenteLeitura || temAviso || salvando" #rodape>
      <RodapeDaGaveta
        :frases="frases"
        :aviso="aviso"
        :salvando="salvando"
        :somente-leitura="somenteLeitura"
        :pendentes="mudancas.size"
        @fechar="emit('fechar')"
        @salvar="salvar"
      />
    </template>
  </AgenteGaveta>
  <DialogoDaCasa
    ref="sairSemSalvar"
    tipo="destrutivo"
    icone="i-lucide-door-open"
    :titulo="$t('FUNCOES_EQUIPE.GUARDA.TITULO')"
    :texto="$t('FUNCOES_EQUIPE.GUARDA.TEXTO')"
    :seguro="$t('FUNCOES_EQUIPE.GAVETA.CONTINUAR')"
    :acao="$t('FUNCOES_EQUIPE.GUARDA.SAIR')"
    @acao="emit('fechar')"
  />
</template>
