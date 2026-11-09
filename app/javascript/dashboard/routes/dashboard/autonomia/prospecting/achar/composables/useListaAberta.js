import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

// #2775 — F6, uma lista aberta: as empresas (uma página por vez, "Ver mais"),
// "Tirar" com "Desfazer" e, na lista já enviada, "Criar uma cópia para
// editar". Tirar grava na hora; o Desfazer devolve a empresa à mesma linha. Os
// números vêm de novo do servidor a cada mudança. Na demonstração nada é
// gravado.
// - "Ver mais" pede as empresas depois da última linha mostrada (cursor), então
//   tirar alguém no meio não faz a próxima página pular ninguém.
// - A lista que passa a "já enviada" com a tela aberta (a campanha saiu nesse
//   meio-tempo): "Tirar" e "Desfazer" dizem isso e a tela recarrega nesse estado.
// - "Criar uma cópia para editar" não roda duas vezes (clique duplo) e diz
//   quantas empresas não foram para a cópia.
const NS = 'PROSPECTING_ACHAR.LISTA';
const LISTA_ENVIADA = 'prospecting.audience.audience_locked';

export function useListaAberta({ fonte, listaId, demo }) {
  const { t } = useI18n();
  const carregando = ref(true);
  const erro = ref(false);
  const lista = ref(null);
  const membros = ref([]);
  const total = ref(0);
  const depois = ref(null);
  const temMais = ref(false);
  const carregandoMais = ref(false);
  const ocupado = ref(false);
  const aviso = ref(null);
  const copiando = ref(false);

  const carregar = async () => {
    carregando.value = true;
    erro.value = false;
    aviso.value = null;
    try {
      const lida = await fonte.value.lista(listaId());
      lista.value = lida.lista;
      membros.value = lida.membros;
      total.value = lida.total;
      depois.value = lida.depois;
      temMais.value = lida.temMais;
    } catch {
      erro.value = true;
    }
    carregando.value = false;
  };

  const verMais = async () => {
    carregandoMais.value = true;
    try {
      const lida = await fonte.value.lista(listaId(), {
        depois: depois.value,
      });
      const jaTem = new Set(membros.value.map(membro => membro.contatoId));
      membros.value = [
        ...membros.value,
        ...lida.membros.filter(membro => !jaTem.has(membro.contatoId)),
      ];
      total.value = lida.total;
      depois.value = lida.depois;
      temMais.value = lida.temMais;
    } catch {
      useAlert(t(`${NS}.ERRO_VER_MAIS`));
    } finally {
      carregandoMais.value = false;
    }
  };

  const atualizarNumeros = nova => {
    if (nova) lista.value = { ...lista.value, ...nova };
  };

  // A recusa da lista que virou "já enviada": a frase própria e a tela de novo,
  // já no estado de enviada. As outras falhas, a frase de erro de cada ação.
  const falhou = async (erroDaFonte, chave) => {
    if (erroDaFonte?.codigo !== LISTA_ENVIADA) {
      useAlert(t(`${NS}.${chave}`));
      return;
    }
    useAlert(t(`${NS}.ERRO_ENVIADA`));
    await carregar();
  };

  const desfazer = async membro => {
    ocupado.value = true;
    try {
      const { lista: nova } = await fonte.value.devolverNaLista({
        listaId: listaId(),
        contatoIds: [membro.contatoId],
      });
      atualizarNumeros(nova);
      membros.value = [...membros.value, membro].sort(
        (a, b) => a.linha - b.linha
      );
      total.value += 1;
      aviso.value = null;
    } catch (erroDaFonte) {
      await falhou(erroDaFonte, 'ERRO_DESFAZER');
    } finally {
      ocupado.value = false;
    }
  };

  const tirar = async membro => {
    ocupado.value = true;
    try {
      const { lista: nova } = await fonte.value.tirarDaLista({
        listaId: listaId(),
        contatoIds: [membro.contatoId],
      });
      atualizarNumeros(nova);
      membros.value = membros.value.filter(
        item => item.contatoId !== membro.contatoId
      );
      total.value = Math.max(0, total.value - 1);
      aviso.value = {
        texto: t(`${NS}.TIROU`, { nome: membro.nome }),
        desfazer: () => desfazer(membro),
      };
    } catch (erroDaFonte) {
      await falhou(erroDaFonte, 'ERRO_TIRAR');
    } finally {
      ocupado.value = false;
    }
  };

  const avisoDaCopia = deFora => {
    if (demo.value) return t('PROSPECTING_ACHAR.COMUM.DEMO_NAO_GRAVA');
    if (deFora) return t(`${NS}.COPIADA_COM_FORA`, { n: deFora }, deFora);
    return t(`${NS}.COPIADA`);
  };

  // A cópia nasce nova, sem campanha: devolve a lista criada para a tela abrir.
  // Enquanto copia, outro clique não cria uma segunda cópia.
  const copiar = async () => {
    if (copiando.value) return null;
    copiando.value = true;
    try {
      const { lista: copia, deFora } = await fonte.value.copiarLista(
        lista.value.id
      );
      useAlert(avisoDaCopia(deFora));
      return copia;
    } catch {
      useAlert(t(`${NS}.ERRO_COPIAR`));
      return null;
    } finally {
      copiando.value = false;
    }
  };

  return {
    carregando,
    erro,
    lista,
    membros,
    total,
    temMais,
    carregandoMais,
    ocupado,
    aviso,
    copiando,
    carregar,
    verMais,
    tirar,
    copiar,
  };
}
