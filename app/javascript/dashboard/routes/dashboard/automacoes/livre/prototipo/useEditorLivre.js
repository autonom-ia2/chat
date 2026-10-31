// #2414 F0 — o que o editor faz com a receita: de onde ela vem (automação
// salva, receita, etapa do funil ou do zero) e como cada mudança é aplicada.
// Automação salva: cada mudança vira a próxima versão; ligada com gente no
// meio, a mudança espera a pessoa escolher o que acontece com quem está no meio.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { RECEITAS } from './dados';
import { FREIO_PADRAO, novoPasso } from './catalogo';
import { nomeDaEtapa } from './frases';
import {
  acharPasso,
  copiar,
  inserirPasso,
  receitaVazia,
  tirarPasso,
  trocarPasso,
} from './receita';
import { useAutomacoesLivre } from './useAutomacoesLivre';

export function useEditorLivre(route) {
  const { t } = useI18n();
  const loja = useAutomacoesLivre();

  const ehNova = computed(() => route.name === 'automacoes_livre_nova');
  const automacao = computed(() =>
    ehNova.value ? null : loja.buscar(route.params.id)
  );
  const receitaBase = computed(
    () => RECEITAS.find(item => item.chave === route.query.receita) || null
  );

  const nomeDaNova = computed(() => {
    const base = receitaBase.value;
    if (base?.pacote) return base.pacote.titulo;
    if (base) return t(`AUTOMACAO_LIVRE.RECEITAS.${base.chave}.TITULO`);
    if (route.query.etapa)
      return t('AUTOMACAO_LIVRE.EDITOR.NOVA_NA_ETAPA', {
        etapa: nomeDaEtapa(route.query.etapa),
      });
    return t('AUTOMACAO_LIVRE.EDITOR.NOVA');
  });

  const receitaInicial = () => {
    if (automacao.value) return copiar(automacao.value.versao.receita);
    if (receitaBase.value) return copiar(receitaBase.value.receita);
    if (route.query.etapa)
      return receitaVazia(
        { tipo: 'cartao_entrou', etapa: route.query.etapa },
        { ...FREIO_PADRAO }
      );
    return receitaVazia(null, { ...FREIO_PADRAO });
  };

  const rascunho = ref(receitaInicial());
  watch(
    () => [route.params.id, route.query.receita, route.query.etapa, route.name],
    () => {
      rascunho.value = receitaInicial();
    }
  );

  // Mudança que espera a escolha de quem está no meio.
  const pendente = ref(null);
  const precisaPerguntar = computed(
    () => Boolean(automacao.value?.ativa) && automacao.value.noMeio > 0
  );

  const salvar = (nova, quemEstaNoMeio) => {
    const versao = loja.salvarVersao(automacao.value.id, nova, {
      quemEstaNoMeio,
    });
    rascunho.value = copiar(nova);
    return versao;
  };

  // Devolve 'feito' (aplicada já) ou 'pendente' (espera a escolha).
  const aplicar = nova => {
    if (!automacao.value) {
      rascunho.value = nova;
      return 'feito';
    }
    if (precisaPerguntar.value) {
      pendente.value = nova;
      return 'pendente';
    }
    salvar(nova);
    return 'feito';
  };

  const confirmarPendente = quemEstaNoMeio => {
    if (!pendente.value) return null;
    const versao = salvar(pendente.value, quemEstaNoMeio);
    pendente.value = null;
    return versao;
  };

  const mudancaDoAlterar = ({ tipo, indice, valor }) => {
    const r = rascunho.value;
    if (tipo === 'passo')
      return { ...r, passos: trocarPasso(r.passos, valor.id, valor) };
    if (tipo === 'gatilho') return { ...r, gatilho: valor };
    if (tipo === 'meta') return { ...r, meta: valor };
    if (tipo === 'freio') return { ...r, freio: valor };
    const condicoes =
      indice < 0
        ? [...r.condicoes, valor]
        : r.condicoes.map((item, i) => (i === indice ? valor : item));
    return { ...r, condicoes };
  };

  const mudancaDoTirar = ({ tipo, indice, valor }) => {
    const r = rascunho.value;
    if (tipo === 'passo')
      return { ...r, passos: tirarPasso(r.passos, valor.id) };
    return { ...r, condicoes: r.condicoes.filter((_, i) => i !== indice) };
  };

  const mudancaDoInserir = ({ listaId, indice }, escolha) => {
    const extra = escolha.acao ? { acao: escolha.acao } : {};
    const passo = novoPasso(escolha.tipo, extra);
    return {
      passo,
      receita: {
        ...rascunho.value,
        passos: inserirPasso(rascunho.value.passos, listaId, indice, passo),
      },
    };
  };

  // O item do "Alterar" que a URL pede: gatilho, meta, freio, condição ou
  // o id de um passo.
  const itemDaUrl = chave => {
    const r = rascunho.value;
    if (chave === 'gatilho') return { tipo: 'gatilho', valor: r.gatilho };
    if (chave === 'meta') return { tipo: 'meta', valor: r.meta };
    if (chave === 'freio') return { tipo: 'freio', valor: r.freio };
    if (chave.startsWith('condicao@')) {
      const resto = chave.slice('condicao@'.length);
      if (resto === 'novo')
        return {
          tipo: 'condicao',
          indice: -1,
          valor: { tipo: 'valor_maior', valor: 300 },
        };
      const indice = Number(resto);
      return r.condicoes[indice]
        ? { tipo: 'condicao', indice, valor: r.condicoes[indice] }
        : null;
    }
    const passo = acharPasso(r.passos, chave);
    return passo ? { tipo: 'passo', valor: passo } : null;
  };

  return {
    ehNova,
    automacao,
    receitaBase,
    nomeDaNova,
    rascunho,
    pendente,
    aplicar,
    confirmarPendente,
    mudancaDoAlterar,
    mudancaDoTirar,
    mudancaDoInserir,
    itemDaUrl,
    loja,
  };
}
