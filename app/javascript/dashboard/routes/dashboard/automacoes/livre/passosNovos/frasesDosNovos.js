// #2414 — os passos novos (#2931–#2936) em frase: a linha do Confira, a linha
// do ensaio ("o que aconteceria") e a linha do histórico ("o que aconteceu").
// No protótipo o ensaio e o histórico vêm do adaptador falso; a frase do Confira
// é a de verdade.
import { P, chaveDoPasso } from './passosNovos';
import {
  NOMES_DE_EXEMPLO,
  blocoDe,
  contarItens,
  horariosLivres,
  nomeDaIntegracao,
  nomeDoPublico,
  rodadaDaLista,
  valorDeTeste,
} from './adaptadorFalso';
import { nomeDaConta } from './nomesDaConta';

const CABE_NA_LINHA = 60;
const curto = texto => {
  const letras = Array.from((texto || '').trim());
  return letras.length > CABE_NA_LINHA
    ? `${letras.slice(0, CABE_NA_LINHA).join('').trimEnd()}…`
    : letras.join('');
};

// O texto com dados (pedaços) em uma linha, com o nome do dado entre colchetes.
export const textoEmLinha = (partes, nomeDoDado) =>
  (partes || [])
    .map(parte =>
      typeof parte === 'string' ? parte : `[${nomeDoDado(parte.$valor)}]`
    )
    .join('');

const emLista = (nomes, t) =>
  nomes.length > 1
    ? t(`${P}.LISTA`, {
        inicio: nomes.slice(0, -1).join(', '),
        ultimo: nomes[nomes.length - 1],
      })
    : nomes[0] || '';

// Quem aprova ou atende, no meio da frase e já com a preposição (`forma`): A
// ("a quem cuida do card", "ao time Vendas"), DE ("de Maria") ou NOME
// ("quem cuida do card"). A pessoa e o time saem pelo nome; sem o nome ainda,
// "uma pessoa da equipe" ou "um time".
export const quemEmFrase = (quem, t, forma = 'NOME') => {
  const de = quem?.de || 'responsavel';
  const chave = `${P}.QUEM_EM_FRASE.${forma}`;
  if (de === 'responsavel') return t(`${chave}.RESPONSAVEL`);
  const nome = nomeDaConta(de, quem.id);
  return nome
    ? t(`${chave}.${de.toUpperCase()}`, { nome })
    : t(`${chave}.${de.toUpperCase()}_SEM_NOME`);
};

// "1 dia", "5 horas": o número e a unidade, que concorda com ele.
export const duracaoEmFrase = (duracao, t) => {
  const valor = duracao?.valor;
  const unidade = (duracao?.unidade || 'dias').toUpperCase();
  return t('AUTOMACAO_LIVRE.FRASES.DURACAO', {
    valor: valor ?? '',
    unidade: t(
      `AUTOMACAO_LIVRE.UNIDADES.${unidade}`,
      {},
      Number.isInteger(valor) ? valor : 2
    ),
  });
};

export const fonteEmFrase = (fonte, t) =>
  fonte?.de === 'endereco'
    ? t(`${P}.CONSULTAR.ENDERECO_PROPRIO`)
    : nomeDaIntegracao(fonte?.id, t) || t(`${P}.CONSULTAR.SEM_FONTE`);

// A lista em palavras do dia a dia, com o nome: "cada card da etapa Proposta".
// Sem o nome ainda, "a etapa escolhida".
const LISTA_EM_FRASE = {
  etapa: lista => ({
    chave: 'DA_ETAPA',
    valores: { etapa: nomeDaConta('etapa', lista.etapa_id) },
  }),
  etiqueta: lista => ({
    chave: 'DA_ETIQUETA',
    valores: { etiqueta: lista.etiqueta },
  }),
  publico: (lista, t) => ({
    chave: 'DO_PUBLICO',
    valores: { publico: nomeDoPublico(lista.publico_id, t) },
  }),
};
const listaEmFrase = (lista, t) => {
  const emFrase = LISTA_EM_FRASE[lista?.de] || LISTA_EM_FRASE.etapa;
  const { chave, valores } = emFrase(lista || {}, t);
  return Object.values(valores).every(Boolean)
    ? t(`${P}.REPETIR.${chave}`, valores)
    : t(`${P}.REPETIR.${chave}_SEM_NOME`);
};

// #2935/#2936: o que sai se a janela de 24 h do WhatsApp oficial estiver
// fechada: o modelo escolhido, ou nada (a automação para nesta conversa).
const foraDaJanela = (passo, t) =>
  passo.modelo
    ? t('AUTOMACAO_LIVRE.ENSAIO.MODELO_FORA_DA_JANELA', {
        modelo: passo.modelo.nome,
      })
    : t(`${P}.SEM_MODELO_FORA_DA_JANELA`);

// O caminho fixo do passo novo no ensaio ("Se aprovar:"): o nome do galho,
// sem "Se a IA escolher", porque ali não decide IA nenhuma.
export const rotuloDoGalhoFixo = (chave, t) =>
  t(`${P}.CAMINHO_NO_ENSAIO`, {
    caminho: t(`AUTOMACAO_LIVRE.RAMOS.${chave.toUpperCase()}`),
  });

// A linha do Confira. `nomeDoDado` dá o nome de um dado do texto (fraseDoValor).
const FRASE = {
  pedir_aprovacao: (passo, t, nomeDoDado) =>
    t(`${P}.APROVACAO.FRASE`, {
      quem: quemEmFrase(passo.quem, t, 'A'),
      pergunta: curto(textoEmLinha(passo.pergunta, nomeDoDado)),
    }),
  repetir_lista: (passo, t) =>
    t(`${P}.REPETIR.FRASE`, {
      lista: listaEmFrase(passo.lista, t),
      teto: passo.teto ?? '',
    }),
  usar_bloco: (passo, t) => {
    const bloco = blocoDe(passo.bloco_id, t);
    return bloco
      ? t(`${P}.BLOCO.FRASE`, { bloco: bloco.nome })
      : t(`${P}.BLOCO.FRASE_SEM_BLOCO`);
  },
  consultar: (passo, t) => {
    const dados = (passo.guardar || []).map(dado => dado.nome);
    return dados.length
      ? t(`${P}.CONSULTAR.FRASE`, {
          fonte: fonteEmFrase(passo.fonte, t),
          dados: emLista(dados, t),
        })
      : t(`${P}.CONSULTAR.FRASE_SEM_DADO`, {
          fonte: fonteEmFrase(passo.fonte, t),
        });
  },
  marcar_reuniao: (passo, t) =>
    t(`${P}.REUNIAO.FRASE`, { quem: quemEmFrase(passo.com, t, 'DE') }),
  pesquisa_nota: (passo, t) =>
    t(`${P}.PESQUISA.FRASE`, { pergunta: curto(passo.pergunta) }),
};

export const fraseDoPassoNovo = (passo, t, nomeDoDado = caminho => caminho) =>
  FRASE[passo.tipo](passo, t, nomeDoDado);

// A linha do ensaio: o destaque (o que faria) e, quando sai mensagem, o balão
// e o que sai com a janela de 24 h fechada (aviso). Nada sai no ensaio; a busca
// só com o OK de quem ensaia (`consulta`, LivreBuscaNoEnsaio).
const ENSAIO = {
  pedir_aprovacao: (passo, t) => ({
    destaque: t(`${P}.APROVACAO.ENSAIO`, {
      quem: quemEmFrase(passo.quem, t, 'A'),
    }),
  }),
  repetir_lista: (passo, t) => {
    const { total, primeiros } = contarItens(passo.lista);
    return {
      destaque: total
        ? t(`${P}.REPETIR.ENSAIO`, { total, nomes: emLista(primeiros, t) })
        : t(`${P}.REPETIR.ENSAIO_VAZIO`),
    };
  },
  usar_bloco: (passo, t) => {
    const bloco = blocoDe(passo.bloco_id, t);
    return {
      destaque: bloco
        ? t(`${P}.BLOCO.ENSAIO`, { passos: bloco.passos.join('; ') })
        : t(`${P}.BLOCO.FRASE_SEM_BLOCO`),
    };
  },
  consultar: (passo, t) => ({
    destaque: t(`${P}.CONSULTAR.ENSAIO`, {
      fonte: fonteEmFrase(passo.fonte, t),
    }),
    consulta: (passo.guardar || []).length ? passo : null,
  }),
  marcar_reuniao: (passo, t) => {
    const horarios = horariosLivres(t);
    return {
      destaque: t(`${P}.REUNIAO.ENSAIO`, { horarios: emLista(horarios, t) }),
      balao: [passo.convite, ...horarios.map((h, i) => `${i + 1}. ${h}`)].join(
        '\n'
      ),
      aviso: foraDaJanela(passo, t),
    };
  },
  pesquisa_nota: (passo, t) => ({
    destaque: t(`${P}.PESQUISA.ENSAIO`, {
      espera: duracaoEmFrase(passo.espera, t),
    }),
    balao: passo.pergunta,
    aviso: foraDaJanela(passo, t),
  }),
};

export const linhaDoEnsaioNovo = (passo, t) => ENSAIO[passo.tipo](passo, t);

// A linha do histórico: o que aconteceu, um detalhe e, no bloco, os passos de
// dentro (para abrir). Exemplo, até o motor existir.
const HISTORICO = {
  pedir_aprovacao: (passo, t) => ({
    texto: t(`${P}.APROVACAO.HISTORICO`, { quem: NOMES_DE_EXEMPLO[2] }),
    detalhe: t(`${P}.APROVACAO.HISTORICO_MOTIVO`),
  }),
  repetir_lista: (passo, t) => {
    const { total, primeiros } = rodadaDaLista();
    return {
      texto: t(`${P}.REPETIR.HISTORICO`, { feitos: total, total }),
      detalhe: t(`${P}.REPETIR.HISTORICO_NOMES`, {
        nomes: primeiros.join(', '),
        mais: total - primeiros.length,
      }),
    };
  },
  usar_bloco: (passo, t) => {
    const bloco = blocoDe(passo.bloco_id, t);
    return {
      texto: bloco
        ? t(`${P}.BLOCO.HISTORICO`, { bloco: bloco.nome })
        : t(`${P}.BLOCO.FRASE_SEM_BLOCO`),
      dentro: bloco?.passos || [],
    };
  },
  consultar: (passo, t) => {
    const [dado] = passo.guardar || [];
    return {
      texto: dado
        ? t(`${P}.CONSULTAR.HISTORICO`, {
            fonte: fonteEmFrase(passo.fonte, t),
            dado: dado.nome,
            valor: valorDeTeste(passo.fonte, dado.caminho, t) || '',
          })
        : t(`${P}.CONSULTAR.HISTORICO_SEM_DADO`, {
            fonte: fonteEmFrase(passo.fonte, t),
          }),
    };
  },
  marcar_reuniao: (passo, t) => ({
    texto: t(`${P}.REUNIAO.HISTORICO`, { horario: horariosLivres(t)[1] }),
  }),
  pesquisa_nota: (passo, t) => ({
    texto: t(`${P}.PESQUISA.HISTORICO`),
    detalhe: t(`${P}.PESQUISA.HISTORICO_CAMINHO`, {
      caminho: t('AUTOMACAO_LIVRE.RAMOS.NOTA_ALTA'),
    }),
  }),
};

export const linhaDoHistoricoNovo = (passo, t) =>
  HISTORICO[passo.tipo](passo, t);

export const nomeDoPassoNovo = (tipo, t) => t(`${chaveDoPasso(tipo)}.NOME`);
