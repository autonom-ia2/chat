<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { LOCK_REASONS } from 'dashboard/helper/peopleAccess';
import Button from 'dashboard/components-next/button/Button.vue';
import AgenteGaveta from 'dashboard/routes/dashboard/autonomia/agentes/components/AgenteGaveta.vue';
import DialogoDaCasa from '../guiada/DialogoDaCasa.vue';
import { useTextos } from '../guiada/useTextos';
import { explicar401 } from '../salvarFuncao';
import { useSemFuncao } from '../useSemFuncao';
import PessoaDaFuncao from './PessoaDaFuncao.vue';

// Quem usa uma função, ou quem está sem função (#2308, especificação 5.D). Com `funcao`: "Quem vai ser …?", com quem
// já é e as outras pessoas; sem ela: "Quem está sem função", uma escolha por pessoa. Nada grava até "Salvar";
// "Cancelar" descarta; Esc e o clique no fundo, com mudança pendente, perguntam antes. Grava como o diálogo de hoje
// (AssignAgentsDialog): agents/update com custom_role_id, null para sem função. Se alguma falha, a gaveta fica
// aberta só com o que não gravou, diz de quem e por quê (o 401 passa pelo explicar401) e recarrega as pessoas. Sem
// Pessoas, ou numa função fora do alcance, a gaveta só mostra quem é.
const props = defineProps({
  funcao: { type: Object, default: null },
});

const emit = defineEmits(['fechar']);

const store = useStore();
const { t } = useI18n();
const { lista } = useTextos();
const { canManagePeople, memberLockReason, roleLockReason, reachesRole } =
  usePeopleAccess();
const { diff, curtoDa } = useSemFuncao();
const agentes = useMapGetter('agents/getAgents');
const funcoes = useMapGetter('customRole/getCustomRoles');

const mudancas = ref(new Map());
const salvando = ref(false);
const erro = ref('');
const sairSemSalvar = ref(null);

const somenteLeitura = computed(
  () =>
    !canManagePeople.value ||
    Boolean(props.funcao && roleLockReason(props.funcao))
);

const porNome = (a, b) => a.name.localeCompare(b.name);
const daFuncao = pessoa => pessoa.custom_role_id === props.funcao?.id;
const jaSao = computed(() => agentes.value.filter(daFuncao).sort(porNome));
const outras = computed(() =>
  agentes.value.filter(pessoa => !daFuncao(pessoa)).sort(porNome)
);
const semFuncao = computed(() =>
  agentes.value
    .filter(pessoa => pessoa.role === 'agent' && !pessoa.custom_role_id)
    .sort(porNome)
);

const funcaoDe = id => funcoes.value.find(funcao => funcao.id === id) || null;
// Administrador já pode tudo: uma função só esconderia telas dele.
const travaDe = pessoa =>
  pessoa.role === 'administrator'
    ? LOCK_REASONS.ADMIN
    : memberLockReason(pessoa) || '';

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
  mudancas.value = new Map([...mudancas.value, [pessoa.id, destino]]);
};
const desfazer = pessoa => {
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
  opcoes: opcoes.value,
  alvo: props.funcao,
});

const nomeDe = id => agentes.value.find(item => item.id === id)?.name;

const fraseDoRodape = ([id, destino]) => {
  const pessoa = nomeDe(id);
  if (destino !== null)
    return t('FUNCOES_EQUIPE.GAVETA.RODAPE.PASSA_A_SER', {
      pessoa,
      funcao: funcaoDe(destino)?.name,
    });
  const atual = agentes.value.find(item => item.id === id)?.custom_role_id;
  const [ganho] = diff(funcaoDe(atual)?.permissions).ganha;
  return ganho
    ? t('FUNCOES_EQUIPE.GAVETA.RODAPE.FICA_SEM', {
        pessoa,
        ganho: curtoDa(ganho),
      })
    : t('FUNCOES_EQUIPE.GAVETA.RODAPE.FICA_SEM_SO', { pessoa });
};
const frases = computed(() => [...mudancas.value].map(fraseDoRodape));

const titulo = computed(() =>
  props.funcao
    ? t('FUNCOES_EQUIPE.GAVETA.TITULO', { nome: props.funcao.name })
    : t('FUNCOES_EQUIPE.GAVETA.TITULO_SEM_FUNCAO')
);

const podeFechar = () => {
  if (!mudancas.value.size) return true;
  sairSemSalvar.value?.abrir();
  return false;
};

// O motivo da falha: o 401 diz se foi alcance, flag ou a própria função (sessão vencida vai para o login, sem
// mensagem); o resto é rede.
const motivoDa = async falhas => {
  const recusa = falhas.find(({ razao }) => razao?.status === 401);
  if (!recusa) return t('FUNCOES_EQUIPE.GAVETA.TENTE');
  const { erro: chave } = await explicar401(recusa.razao.code);
  return chave === null ? null : t(`FUNCOES_EQUIPE.SALVAR.${chave}`);
};

const salvar = async () => {
  salvando.value = true;
  erro.value = '';
  const pedidos = [...mudancas.value];
  const resultados = await Promise.allSettled(
    pedidos.map(([id, destino]) =>
      store.dispatch('agents/update', {
        id,
        name: nomeDe(id),
        custom_role_id: destino,
      })
    )
  );
  const falhas = pedidos
    .map((pedido, indice) => ({ pedido, razao: resultados[indice].reason }))
    .filter((_, indice) => resultados[indice].status === 'rejected');
  if (!falhas.length) {
    salvando.value = false;
    useAlert(t('FUNCOES_EQUIPE.GAVETA.SALVO'));
    emit('fechar');
    return;
  }
  const nomes = falhas.map(({ pedido: [id] }) => nomeDe(id));
  const motivo = await motivoDa(falhas);
  if (motivo === null) {
    salvando.value = false;
    return;
  }
  mudancas.value = new Map(falhas.map(({ pedido }) => pedido));
  erro.value = t(
    'FUNCOES_EQUIPE.GAVETA.ERRO_PARCIAL',
    { nomes: lista(nomes), motivo },
    nomes.length
  );
  await store.dispatch('agents/get');
  salvando.value = false;
};
</script>

<template>
  <AgenteGaveta
    :titulo="titulo"
    :pode-fechar="podeFechar"
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
        {{ $t('FUNCOES_EQUIPE.GAVETA.SO_LEITURA') }}
      </p>
      <section class="flex flex-col gap-1">
        <h3 class="m-0 text-sm font-semibold text-n-slate-11">
          {{
            $t('FUNCOES_EQUIPE.GAVETA.JA_SAO', {
              nome: funcao.name,
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

    <template v-if="!somenteLeitura" #rodape>
      <p
        v-for="frase in frases"
        :key="frase"
        data-frase-rodape
        class="m-0 text-sm text-n-slate-12"
      >
        {{ frase }}
      </p>
      <p
        v-if="erro"
        data-erro-gaveta
        role="alert"
        class="m-0 text-sm font-medium text-n-ruby-11"
      >
        {{ erro }}
      </p>
      <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <Button
          data-cancelar
          :label="$t('FUNCOES_EQUIPE.GAVETA.CANCELAR')"
          slate
          faded
          class="min-h-11 max-sm:w-full max-sm:!h-12"
          @click="emit('fechar')"
        />
        <Button
          data-salvar
          :label="$t('FUNCOES_EQUIPE.GAVETA.SALVAR')"
          :disabled="!mudancas.size"
          :is-loading="salvando"
          class="min-h-11 max-sm:w-full max-sm:!h-12"
          @click="salvar"
        />
      </div>
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
