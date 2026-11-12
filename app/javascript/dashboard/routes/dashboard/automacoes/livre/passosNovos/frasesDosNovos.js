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
  rodadaDaLista,
  valorDeTeste,
} from './adaptadorFalso';

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

export const quemEmFrase = (quem, t) =>
  t(`${P}.QUEM.${(quem?.de || 'responsavel').toUpperCase()}`);

const fonteEmFrase = (fonte, t) =>
  fonte?.de === 'endereco'
    ? t(`${P}.CONSULTAR.ENDERECO_PROPRIO`)
    : nomeDaIntegracao(fonte?.id, t) || t(`${P}.CONSULTAR.SEM_FONTE`);

const listaEmFrase = (lista, t) =>
  lista?.de === 'etiqueta' && lista.etiqueta
    ? t(`${P}.REPETIR.DA_ETIQUETA`, { etiqueta: lista.etiqueta })
    : t(`${P}.REPETIR.DA_ETAPA`);

// A linha do Confira. `nomeDoDado` dá o nome de um dado do texto (fraseDoValor).
const FRASE = {
  pedir_aprovacao: (passo, t, nomeDoDado) =>
    t(`${P}.APROVACAO.FRASE`, {
      quem: quemEmFrase(passo.quem, t),
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
    t(`${P}.REUNIAO.FRASE`, { quem: quemEmFrase(passo.com, t) }),
  pesquisa_nota: (passo, t) =>
    t(`${P}.PESQUISA.FRASE`, { pergunta: curto(passo.pergunta) }),
};

export const fraseDoPassoNovo = (passo, t, nomeDoDado = caminho => caminho) =>
  FRASE[passo.tipo](passo, t, nomeDoDado);

// A linha do ensaio: o destaque (o que faria) e, quando sai mensagem, o balão.
// Nada sai e nada é consultado no ensaio.
const ENSAIO = {
  pedir_aprovacao: (passo, t) => ({
    destaque: t(`${P}.APROVACAO.ENSAIO`, { quem: quemEmFrase(passo.quem, t) }),
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
  }),
  marcar_reuniao: (passo, t) => {
    const horarios = horariosLivres(t);
    return {
      destaque: t(`${P}.REUNIAO.ENSAIO`, { horarios: emLista(horarios, t) }),
      balao: [passo.convite, ...horarios.map((h, i) => `${i + 1}. ${h}`)].join(
        '\n'
      ),
    };
  },
  pesquisa_nota: (passo, t) => ({
    destaque: t(`${P}.PESQUISA.ENSAIO`, { dias: passo.espera?.valor ?? '' }),
    balao: passo.pergunta,
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
