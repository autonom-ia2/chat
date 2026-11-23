import { computed, ref } from 'vue';
import { GRUPO_PADRAO } from '../fonte/grupos';
import { VISOES } from '../fonte/gruposDeCompra';
import { ORDEM_PADRAO_POR_COMPRA } from './ordens';
import { useMeusGrupos } from './useMeusGrupos';

// #3097 — em Pessoas, os grupos por conversa ou por compra ("Mostrar os
// grupos"). Por compra, "Todos" abre, vêm os grupos de compra, a linha diz a
// compra em vez da conversa e a ordem abre por quem está há mais tempo sem
// comprar; de volta à conversa, volta a ordem guardada da pessoa.
// #3168 — a terceira, "Meus grupos" (`comMeusGrupos`), com os grupos guardados
// (useMeusGrupos). Tirado de pages/ListaPage.vue. Em "Meus grupos" a lista
// mostra o grupo escolhido como ele foi guardado, inclusive a visão de onde
// veio (`visaoDaLista`: a linha e as ordens por compra seguem ela), sem as
// pílulas de conversa. Sair de "Meus grupos" tira a busca e os filtros do
// grupo. Guardar um grupo novo leva a "Meus grupos" sem mexer na lista: a
// pessoa continua vendo exatamente quem via.
export const useVisoesDaLista = ({
  visaoInicial,
  comMeusGrupos,
  aba,
  ehEmpresas,
  lista,
  ordemDaAba,
  fonteDosGuardados,
  aoFalhar,
}) => {
  const visao = ref(visaoInicial);
  const naMeusGrupos = computed(
    () => !ehEmpresas.value && visao.value === VISOES.MEUS
  );
  const porCompra = computed(
    () => !ehEmpresas.value && visao.value === VISOES.COMPRA
  );
  const ordemDaVisao = nova =>
    nova === VISOES.COMPRA ? ORDEM_PADRAO_POR_COMPRA : ordemDaAba(aba.value);

  let visaoDaLista;
  const meusGrupos = useMeusGrupos({
    fonte: fonteDosGuardados,
    lista,
    visaoNaTela: () => visaoDaLista.value,
    ordemDaVisao,
    aoFalhar,
  });
  visaoDaLista = computed(() =>
    naMeusGrupos.value
      ? (meusGrupos.grupo.value?.visao ?? VISOES.CONVERSA)
      : visao.value
  );
  const linhasPorCompra = computed(
    () => !ehEmpresas.value && visaoDaLista.value === VISOES.COMPRA
  );

  const trocarVisao = nova => {
    const antes = visaoDaLista.value;
    const saiDosMeus = visao.value === VISOES.MEUS;
    visao.value = nova;
    if (nova === VISOES.MEUS) return meusGrupos.entrar(antes);
    meusGrupos.sair();
    return lista.mudarConsulta({
      grupo: GRUPO_PADRAO[aba.value],
      ordem: ordemDaVisao(nova),
      ...(saiDosMeus ? { busca: '', filtros: {} } : {}),
    });
  };
  const irParaMeusGrupos = () => {
    visao.value = VISOES.MEUS;
  };

  // "Guardar como grupo": com algum filtro ligado, fora de "Meus grupos" (lá,
  // mudar o grupo escolhido mostra a faixa "Você mudou quem aparece neste
  // grupo", com "Guardar no grupo").
  const podeGuardarGrupo = computed(
    () =>
      comMeusGrupos &&
      !ehEmpresas.value &&
      !naMeusGrupos.value &&
      lista.filtrosAtivos.value > 0
  );
  const grupoMudou = computed(
    () => naMeusGrupos.value && meusGrupos.mudou.value
  );
  const semGruposGuardados = computed(
    () => naMeusGrupos.value && !meusGrupos.guardados.value.length
  );

  return {
    visao,
    porCompra,
    naMeusGrupos,
    visaoDaLista,
    linhasPorCompra,
    meusGrupos,
    trocarVisao,
    irParaMeusGrupos,
    podeGuardarGrupo,
    grupoMudou,
    semGruposGuardados,
  };
};
