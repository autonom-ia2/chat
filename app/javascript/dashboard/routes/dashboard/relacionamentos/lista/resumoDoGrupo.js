import { textoDaData } from '../ficha/dataDoCampo';
import { camposDoTopo } from './camposDoTopo';
import { preenchido } from './filtros';
import {
  JUNTAR,
  OPERADORES,
  TIPOS,
  condicoesProntas,
  pedeValor,
  rotuloDoComo,
  temUmComoSo,
} from './informacoes';

// #3168 — a frase de quem entra num grupo guardado, para o leigo ler antes de
// guardar e ao escolher o grupo: "Clientes · Cidade: Campinas · Última
// conversa há mais de 90 dias". Junta a pílula (`nomeDoGrupo(id)`, '' para a
// que não diz nada), a busca, os filtros de cima e as linhas de "Por outra
// informação" (só as prontas). Com "Pelo menos uma", as linhas viram "Pelo
// menos uma destas: A, B ou C". Sem nada, "Todo mundo". Função pura.
// `informacoes`: o catálogo (lista/informacoes.js, catalogoDeInformacoes).
const CC = 'RELACIONAMENTOS.LISTA.CONDICOES';
const CR = `${CC}.RESUMO`;
const SIM_NAO = 'RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO';

// O nome da opção escolhida; o país vai sem a bandeira (`searchLabel`).
const rotuloDaOpcao = (opcoes, valor) => {
  const opcao = (opcoes ?? []).find(item => item.value === valor);
  return opcao ? (opcao.searchLabel ?? opcao.label) : String(valor);
};

const dosCampos = (filtros, contexto) =>
  camposDoTopo({ ...contexto, veValores: true })
    .filter(({ chave }) => preenchido(filtros[chave]))
    .map(({ chave, rotulo, opcoes }) =>
      contexto.t(`${CR}.CAMPO`, {
        rotulo,
        valor: rotuloDaOpcao(opcoes, filtros[chave]),
      })
    );

const valorEmTexto = (condicao, informacao, { t, idioma }) => {
  const { tipo, valor } = condicao;
  if (tipo === TIPOS.SIM_NAO) return t(`${SIM_NAO}.${valor ? 'SIM' : 'NAO'}`);
  if (tipo === TIPOS.LISTA) return rotuloDaOpcao(informacao?.opcoes, valor);
  if (tipo === TIPOS.DATA || tipo === TIPOS.DATA_DA_CONTA) {
    return textoDaData(valor, idioma);
  }
  return String(valor).trim();
};

const textoDaCondicao = (condicao, todas, contexto) => {
  const { t } = contexto;
  const informacao = todas.find(item => item.chave === condicao.chave);
  const nome = informacao?.rotulo ?? condicao.chave;
  const como = t(`${CC}.COMO.${rotuloDoComo(condicao.tipo, condicao.como)}`);
  if (!pedeValor(condicao.como)) {
    return t(`${CR}.SEM_VALOR`, { informacao: nome, como });
  }
  if (condicao.como === OPERADORES.HA_MAIS_DE_DIAS) {
    return t(`${CR}.DIAS`, { informacao: nome, dias: Number(condicao.valor) });
  }
  const valor = valorEmTexto(condicao, informacao, contexto);
  if (temUmComoSo(condicao)) {
    return t(`${CR}.CAMPO`, { rotulo: nome, valor });
  }
  // O texto vai entre aspas: "Nome tem o texto “Ana”".
  const chave = condicao.tipo === TIPOS.TEXTO ? 'TEXTO' : 'VALOR';
  return t(`${CR}.${chave}`, {
    informacao: nome,
    como,
    valor,
  });
};

const emUmaLista = (textos, t) =>
  textos.length > 1
    ? t(`${CR}.OU`, {
        antes: textos.slice(0, -1).join(', '),
        depois: textos[textos.length - 1],
      })
    : textos[0];

const dasCondicoes = (filtros, contexto) => {
  const { informacoes = {} } = contexto;
  const todas = [
    ...(informacoes.daPessoa ?? []),
    ...(informacoes.daConta ?? []),
  ];
  const textos = condicoesProntas(filtros.condicoes).map(condicao =>
    textoDaCondicao(condicao, todas, contexto)
  );
  if (filtros.juntar !== JUNTAR.QUALQUER || textos.length < 2) return textos;
  return [
    contexto.t(`${CR}.PELO_MENOS_UMA`, {
      lista: emUmaLista(textos, contexto.t),
    }),
  ];
};

export const resumoDoGrupo = (
  { grupo, busca = '', filtros = {} },
  { t, idioma, opcoes = {}, informacoes, nomeDoGrupo = () => '' }
) => {
  const contexto = { t, idioma, opcoes, informacoes };
  const partes = [
    nomeDoGrupo(grupo),
    busca && t(`${CR}.BUSCA`, { busca }),
    ...dosCampos(filtros, contexto),
    ...dasCondicoes(filtros, contexto),
  ].filter(Boolean);
  return partes.length ? partes.join(' · ') : t(`${CR}.TODO_MUNDO`);
};
