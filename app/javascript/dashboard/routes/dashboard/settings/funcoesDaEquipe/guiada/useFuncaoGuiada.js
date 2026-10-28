import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { LOCK_REASONS } from 'dashboard/helper/peopleAccess';
import { PRONTAS, cartaoPronto } from '../cartaoPronto';
import { ALTERAR_NOVA, DUPLICAR_NOVA, LISTA_NOVA } from '../listaPelaFlag';
import { motivoDaTrava } from '../motivoDaTrava';
import { nomeEmUso, primeiroNomeLivre } from '../nomeDisponivel';
import { salvarFuncao } from '../salvarFuncao';

// O estado da conversa guiada (#2308, especificação 5.B e 5.C): de onde começa (pronta, do zero, a função para
// alterar ou a cópia), a etapa, o que mudou desde o começo e o salvar.
const MODO = { [ALTERAR_NOVA]: 'alterar', [DUPLICAR_NOVA]: 'duplicar' };
const mesmas = (a, b) =>
  a.length === b.length && a.every(chave => b.includes(chave));

export function useFuncaoGuiada() {
  const store = useStore();
  const route = useRoute();
  const router = useRouter();
  const { t } = useI18n();
  const { giver, roleLockReason } = usePeopleAccess();
  const funcoes = useMapGetter('customRole/getCustomRoles');
  const uiFlags = useMapGetter('customRole/getUIFlags');

  const modo = computed(() => MODO[route.name] || 'criar');
  const idDaFuncao = computed(() => Number(route.params.roleId) || null);

  const carregou = ref(false);
  const erroAoAbrir = ref(false);
  const etapa = ref('escolha');
  const pronta = ref(null);
  const base = ref('');
  const permissions = ref([]);
  const inicial = ref([]);
  const nome = ref('');
  const descricao = ref('');
  const comeco = ref({ nome: '', descricao: '' });
  const deFora = ref([]);
  const salva = ref(null);
  const salvando = ref(false);
  const erro = ref('');
  const erroDoNome = ref('');

  const comecar = ({ chaves, nomeNovo = '', descricaoNova = '', proxima }) => {
    permissions.value = [...chaves];
    inicial.value = [...chaves];
    nome.value = nomeNovo;
    descricao.value = descricaoNova;
    comeco.value = { nome: nomeNovo, descricao: descricaoNova };
    erro.value = '';
    erroDoNome.value = '';
    etapa.value = proxima;
  };

  const nomeDaPronta = chave => t(`FUNCOES_EQUIPE.PRONTAS.${chave}.NOME`);

  const usarPronta = chave => {
    pronta.value = chave;
    base.value = nomeDaPronta(chave);
    comecar({
      chaves: cartaoPronto({ chave }, giver.value).corte,
      nomeNovo: primeiroNomeLivre(base.value, funcoes.value),
      descricaoNova: t(`FUNCOES_EQUIPE.PRONTAS.${chave}.DESCRICAO`),
      proxima: 'ajustes',
    });
  };

  const doZero = () => {
    pronta.value = null;
    base.value = '';
    comecar({ chaves: [], proxima: 'ajustes' });
  };

  const voltarParaLista = () => router.push({ name: LISTA_NOVA });

  // Alterar exige alcançar a função e não ser a própria; duplicar só não abre uma acima do alcance (como a lista).
  const podeAbrir = funcao => {
    if (!funcao) return false;
    const trava = roleLockReason(funcao);
    return modo.value === 'alterar' ? !trava : trava !== LOCK_REASONS.ABOVE;
  };

  const abrirDaConta = funcao => {
    if (modo.value === 'alterar') {
      comecar({
        chaves: funcao.permissions,
        nomeNovo: funcao.name,
        descricaoNova: funcao.description || '',
        proxima: 'ajustes',
      });
      return;
    }
    // A cópia corta o que quem monta não pode dar, e avisa (especificação 5.C).
    deFora.value = funcao.permissions.filter(chave =>
      motivoDaTrava(giver.value, chave)
    );
    base.value = funcao.name;
    comecar({
      chaves: funcao.permissions.filter(chave => !deFora.value.includes(chave)),
      nomeNovo: primeiroNomeLivre(funcao.name, funcoes.value),
      descricaoNova: funcao.description || '',
      proxima: 'confira',
    });
  };

  // ?pronta= só aceita uma pronta de verdade e ao alcance de quem monta (o Financeiro sem ver os custos fica fora).
  const prontaValida = chave => {
    const achada = PRONTAS.find(item => item.chave === chave);
    return Boolean(achada) && !cartaoPronto(achada, giver.value).fora;
  };

  // Sempre a lista fresca e as pessoas (a perda de acesso depende delas). Falhou: erro com "Tentar de novo", nunca
  // a lista vazia nem a volta em silêncio.
  const carregar = async () => {
    carregou.value = false;
    erroAoAbrir.value = false;
    const [, pessoas] = await Promise.all([
      store.dispatch('customRole/getCustomRole'),
      store.dispatch('agents/get'),
    ]);
    if (uiFlags.value?.fetchingListFailed || pessoas === false) {
      erroAoAbrir.value = true;
      return;
    }
    carregou.value = true;
    if (modo.value === 'criar') {
      if (prontaValida(route.query.pronta)) usarPronta(route.query.pronta);
      return;
    }
    const funcao = funcoes.value.find(item => item.id === idDaFuncao.value);
    if (!podeAbrir(funcao)) {
      router.replace({ name: LISTA_NOVA });
      return;
    }
    abrirDaConta(funcao);
  };

  const mudou = computed(
    () =>
      !mesmas(permissions.value, inicial.value) ||
      nome.value !== comeco.value.nome ||
      descricao.value !== comeco.value.descricao
  );

  const dicaDoNome = computed(() => {
    const emUso = base.value && nomeEmUso(base.value, funcoes.value);
    return emUso && nome.value.trim() !== base.value
      ? t('FUNCOES_EQUIPE.CONFIRA.DICA_NOME', { base: base.value })
      : '';
  });

  const concluir = funcao => {
    salva.value = funcao;
    if (modo.value !== 'alterar') {
      etapa.value = 'sucesso';
      return;
    }
    useAlert(t('FUNCOES_EQUIPE.SALVAR.ALTERADA', { nome: funcao.name }));
    voltarParaLista();
  };

  const conferirAntes = (nomeLimpo, idAtual) => {
    if (nomeLimpo.length < 2) return { erroDoNome: 'NOME_CURTO' };
    if (nomeEmUso(nomeLimpo, funcoes.value, idAtual))
      return { erroDoNome: 'NOME_EM_USO' };
    return permissions.value.length ? null : { erro: 'NADA_LIGADO' };
  };

  const mostrar = (resultado, nomeLimpo) => {
    if (resultado.sugestao) nome.value = resultado.sugestao;
    const valores = { nome: nomeLimpo, sugestao: resultado.sugestao };
    erroDoNome.value = resultado.erroDoNome
      ? t(`FUNCOES_EQUIPE.SALVAR.${resultado.erroDoNome}`, valores)
      : '';
    erro.value = resultado.erro
      ? t(`FUNCOES_EQUIPE.SALVAR.${resultado.erro}`)
      : '';
  };

  const salvar = async () => {
    if (salvando.value) return;
    const nomeLimpo = nome.value.trim();
    const idAtual = modo.value === 'alterar' ? idDaFuncao.value : null;
    const recusa = conferirAntes(nomeLimpo, idAtual);
    if (recusa) {
      mostrar(recusa, nomeLimpo);
      return;
    }
    salvando.value = true;
    const resultado = await salvarFuncao({
      store,
      giver: giver.value,
      id: idAtual,
      dados: {
        name: nomeLimpo,
        description: descricao.value.trim(),
        permissions: permissions.value,
      },
    });
    salvando.value = false;
    if (resultado.funcao) concluir(resultado.funcao);
    else mostrar(resultado, nomeLimpo);
  };

  return {
    modo,
    idDaFuncao,
    carregou,
    erroAoAbrir,
    etapa,
    pronta,
    permissions,
    inicial,
    nome,
    descricao,
    comeco,
    deFora,
    salva,
    salvando,
    erro,
    erroDoNome,
    dicaDoNome,
    mudou,
    nomeDaPronta,
    usarPronta,
    doZero,
    carregar,
    salvar,
    voltarParaLista,
  };
}
