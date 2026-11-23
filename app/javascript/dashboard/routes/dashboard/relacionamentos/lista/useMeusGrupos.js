import { computed, ref } from 'vue';
import { ABAS, GRUPO_PADRAO } from '../fonte/grupos';
import { FILTROS_VAZIOS } from './filtros';

// #3168 — "Meus grupos" da lista de pessoas: os grupos guardados (`fonte`,
// fonte/gruposGuardados.js), o escolhido e o que se faz com eles. O grupo
// guarda o que a pessoa via quando guardou: a visão de onde veio (conversa ou
// compra), a pílula escolhida, a busca e os filtros. Escolher um reaplica tudo
// isso na lista; quando a visão muda, a ordem volta à padrão dela
// (`ordemDaVisao`). `visaoNaTela()`: a visão que a lista mostra agora.
// `semMudanca`: o que está na tela é o grupo escolhido, sem mudança; `mudou`:
// há um grupo escolhido e a tela já não é ele (a faixa "Você mudou quem aparece
// neste grupo"). Apagar volta para o primeiro que sobrou. Cada escrita que
// falha chama `aoFalhar` e devolve `false`.
const comoTexto = filtros =>
  JSON.stringify(
    Object.keys(FILTROS_VAZIOS).map(chave => [
      chave,
      filtros?.[chave] ?? FILTROS_VAZIOS[chave],
    ])
  );
export const mesmosFiltros = (a, b) => comoTexto(a) === comoTexto(b);

export const mesmaConsulta = (tela, guardado) =>
  tela.grupo === guardado.grupo &&
  tela.busca === (guardado.busca ?? '') &&
  mesmosFiltros(tela.filtros, guardado.filtros);

export const useMeusGrupos = ({
  fonte,
  lista,
  visaoNaTela = () => '',
  ordemDaVisao = () => undefined,
  aoFalhar = () => {},
}) => {
  const guardados = ref([]);
  const escolhido = ref('');
  const ocupado = ref(false);
  const grupo = computed(
    () => guardados.value.find(({ id }) => id === escolhido.value) ?? null
  );
  const daTela = () => ({
    grupo: lista.grupo.value,
    busca: lista.busca.value,
    filtros: lista.filtros.value,
  });
  const semMudanca = computed(
    () => Boolean(grupo.value) && mesmaConsulta(daTela(), grupo.value)
  );
  const mudou = computed(() => Boolean(grupo.value) && !semMudanca.value);

  const comCuidado = async escrita => {
    ocupado.value = true;
    try {
      return await escrita();
    } catch {
      aoFalhar();
      return false;
    } finally {
      ocupado.value = false;
    }
  };

  // Os guardados só são lidos quando a pessoa entra em "Meus grupos" (a lista
  // de sempre não pergunta nada a mais ao servidor).
  let carregou = false;
  const carregar = () =>
    comCuidado(async () => {
      guardados.value = await fonte.listar();
      carregou = true;
      return true;
    });

  const aplicar = (achado, visaoAntes) =>
    lista.mudarConsulta({
      grupo: achado.grupo,
      busca: achado.busca ?? '',
      filtros: achado.filtros,
      ordem:
        achado.visao === visaoAntes ? undefined : ordemDaVisao(achado.visao),
    });
  // `visaoAntes`: a visão que a lista mostrava (quem troca de visão passa a de
  // antes da troca).
  const escolher = (id, visaoAntes = visaoNaTela()) => {
    const achado = guardados.value.find(item => item.id === id);
    escolhido.value = achado ? achado.id : '';
    return achado ? aplicar(achado, visaoAntes) : undefined;
  };
  // Ao entrar em "Meus grupos": o primeiro grupo (sem nenhum, a tela mostra o
  // cartão vazio e não a lista).
  const entrar = async visaoAntes => {
    if (!carregou) await carregar();
    return escolher(guardados.value[0]?.id ?? '', visaoAntes);
  };
  const sair = () => {
    escolhido.value = '';
  };
  // "Voltar ao que era": a tela volta a ser o grupo escolhido.
  const voltar = () => escolher(escolhido.value);

  const guardarComoGrupo = nome =>
    comCuidado(async () => {
      const novo = await fonte.criar({
        nome,
        visao: visaoNaTela(),
        ...daTela(),
      });
      guardados.value = [...guardados.value, novo];
      escolhido.value = novo.id;
      return true;
    });

  const trocarGrupo = (mudancas, depois = () => {}) =>
    comCuidado(async () => {
      const mudado = await fonte.mudar(escolhido.value, {
        ...grupo.value,
        ...mudancas,
      });
      guardados.value = guardados.value.map(item =>
        item.id === mudado.id ? mudado : item
      );
      depois(mudado);
      return true;
    });
  const trocarNome = nome => trocarGrupo({ nome });
  // Grava no grupo escolhido a pílula e a busca da tela e os filtros (os da
  // gaveta, ou os da tela quando vem da faixa).
  const guardarNoGrupo = (filtros = lista.filtros.value) =>
    trocarGrupo({ ...daTela(), filtros }, () => {
      if (!mesmosFiltros(filtros, lista.filtros.value)) {
        lista.mudarFiltros(filtros);
      }
    });

  const apagar = () =>
    comCuidado(async () => {
      await fonte.apagar(escolhido.value);
      guardados.value = guardados.value.filter(
        ({ id }) => id !== escolhido.value
      );
      if (guardados.value.length) {
        entrar();
        return true;
      }
      // Era o último: a lista volta a ser a de todos, sem os filtros dele.
      escolhido.value = '';
      lista.mudarConsulta({
        grupo: GRUPO_PADRAO[ABAS.PESSOAS],
        busca: '',
        filtros: {},
      });
      return true;
    });

  return {
    guardados,
    escolhido,
    grupo,
    ocupado,
    semMudanca,
    mudou,
    carregar,
    escolher,
    entrar,
    sair,
    voltar,
    guardarComoGrupo,
    trocarNome,
    guardarNoGrupo,
    apagar,
  };
};
