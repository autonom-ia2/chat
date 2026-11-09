import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

// #2775 — F6, uma lista aberta: as empresas (uma página por vez, "Ver mais"),
// "Tirar" com "Desfazer" e, na lista já enviada, "Criar uma cópia para
// editar". Tirar grava na hora; o Desfazer devolve a empresa à mesma linha. Os
// números vêm de novo do servidor a cada mudança. Na demonstração nada é
// gravado.
const NS = 'PROSPECTING_ACHAR.LISTA';

export function useListaAberta({ fonte, listaId, demo }) {
  const { t } = useI18n();
  const carregando = ref(true);
  const erro = ref(false);
  const lista = ref(null);
  const membros = ref([]);
  const total = ref(0);
  const pagina = ref(1);
  const carregandoMais = ref(false);
  const ocupado = ref(false);
  const aviso = ref(null);
  const copiando = ref(false);

  const temMais = computed(() => membros.value.length < total.value);

  const carregar = async () => {
    carregando.value = true;
    erro.value = false;
    aviso.value = null;
    try {
      const lida = await fonte.value.lista(listaId(), 1);
      lista.value = lida.lista;
      membros.value = lida.membros;
      total.value = lida.total;
      pagina.value = 1;
    } catch {
      erro.value = true;
    }
    carregando.value = false;
  };

  const verMais = async () => {
    carregandoMais.value = true;
    try {
      const lida = await fonte.value.lista(listaId(), pagina.value + 1);
      const jaTem = new Set(membros.value.map(membro => membro.contatoId));
      membros.value = [
        ...membros.value,
        ...lida.membros.filter(membro => !jaTem.has(membro.contatoId)),
      ];
      total.value = lida.total;
      pagina.value += 1;
    } catch {
      useAlert(t(`${NS}.ERRO_VER_MAIS`));
    } finally {
      carregandoMais.value = false;
    }
  };

  const atualizarNumeros = nova => {
    if (nova) lista.value = { ...lista.value, ...nova };
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
    } catch {
      useAlert(t(`${NS}.ERRO_DESFAZER`));
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
    } catch {
      useAlert(t(`${NS}.ERRO_TIRAR`));
    } finally {
      ocupado.value = false;
    }
  };

  // A cópia nasce nova, sem campanha: devolve a lista criada para a tela abrir.
  const copiar = async () => {
    copiando.value = true;
    try {
      const copia = await fonte.value.copiarLista(lista.value.id);
      useAlert(
        t(
          demo.value
            ? 'PROSPECTING_ACHAR.COMUM.DEMO_NAO_GRAVA'
            : `${NS}.COPIADA`
        )
      );
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
