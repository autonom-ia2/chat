import { reactive } from 'vue';

// Protótipo #2931–#2936 — os nomes que a frase de um passo novo diz: quem
// aprova, a agenda de quem e a etapa da lista. A receita guarda só o id; o
// editor guarda aqui as escolhas da conta que já carregou, como faz com as
// listas de e-mail (listaDeEmail.js). Sem o nome ainda, a frase diz "uma pessoa
// da equipe" ou "a etapa escolhida".
const nomes = reactive({ pessoa: {}, time: {}, etapa: {} });

const porId = opcoes =>
  Object.fromEntries((opcoes || []).map(item => [item.value, item.label]));

// `etapas` vem agrupada por funil: [{ label, options: [{ value, label }] }].
export const guardarNomesDosPassosNovos = ({ pessoa, time, etapas }) => {
  nomes.pessoa = porId(pessoa);
  nomes.time = porId(time);
  nomes.etapa = porId((etapas || []).flatMap(grupo => grupo.options || []));
};

export const nomeDaConta = (tipo, id) => nomes[tipo]?.[id];
