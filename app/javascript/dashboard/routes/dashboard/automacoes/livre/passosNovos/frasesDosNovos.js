// #2414 — os passos novos (#2931–#2936) em frase: a linha do Confira, a linha
// do ensaio ("o que aconteceria") e a linha do histórico ("o que aconteceu").
// Os três com motor (#2932–#2934) leem o que veio do servidor (dadosDaConta):
// a prévia mostra a última contagem e o último teste da tela; o ensaio e o
// histórico de verdade saem do servidor (linhaDoEnsaioComMotor, Historico). Os
// outros três (#2931, #2935, #2936) também: o ensaio de verdade sai de
// linhaDoEnsaioReal e o histórico de detalheDoHistorico; o adaptador falso fica
// só nos exemplos da prévia do painel.
import { P, chaveDoPasso } from './passosNovos';
import { NOMES_DE_EXEMPLO, horariosLivres } from './adaptadorFalso';
import {
  blocoDe,
  consultaPronta,
  contagemDaTela,
  nomeDoPublico,
  valorDoTeste,
} from './dadosDaConta';
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

// Onde busca, já com a preposição: "na consulta “Busca de CEP”" ou "num
// endereço próprio". O endereço em si nunca aparece na frase.
export const fonteEmFrase = (fonte, t) => {
  if (fonte?.de === 'endereco') return t(`${P}.CONSULTAR.ENDERECO_PROPRIO`);
  const consulta = fonte?.de === 'pronta' && consultaPronta(fonte.consulta);
  return consulta
    ? t(`${P}.CONSULTAR.NA_CONSULTA`, { consulta: consulta.nome })
    : t(`${P}.CONSULTAR.SEM_FONTE`);
};

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
  publico: lista => ({
    chave: 'DO_PUBLICO',
    valores: { publico: nomeDoPublico(lista.publico_id) },
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
    const bloco = blocoDe(passo.bloco_id);
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
    const { total, primeiros } = contagemDaTela();
    return {
      destaque: total
        ? t(`${P}.REPETIR.ENSAIO`, { total, nomes: emLista(primeiros, t) })
        : t(`${P}.REPETIR.ENSAIO_VAZIO`),
    };
  },
  usar_bloco: (passo, t) => {
    const bloco = blocoDe(passo.bloco_id);
    return {
      destaque: bloco
        ? t(`${P}.BLOCO.ENSAIO`, { passos: bloco.frases.join('; ') })
        : t(`${P}.BLOCO.FRASE_SEM_BLOCO`),
    };
  },
  // A consulta pronta busca com um dado da conversa: a prévia não tem conversa,
  // então só o ensaio de verdade oferece "Buscar agora" (ENSAIO_COM_MOTOR).
  consultar: (passo, t) => ({
    destaque: t(`${P}.CONSULTAR.ENSAIO`, {
      fonte: fonteEmFrase(passo.fonte, t),
    }),
    consulta:
      passo.fonte?.de !== 'pronta' && (passo.guardar || []).length
        ? passo
        : null,
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
    const { total, primeiros } = contagemDaTela();
    return {
      texto: t(`${P}.REPETIR.HISTORICO`, { feitos: total, total }),
      detalhe: t(`${P}.REPETIR.HISTORICO_NOMES`, {
        nomes: primeiros.join(', '),
        mais: total - primeiros.length,
      }),
    };
  },
  usar_bloco: (passo, t) => {
    const bloco = blocoDe(passo.bloco_id);
    return {
      texto: bloco
        ? t(`${P}.BLOCO.HISTORICO`, { bloco: bloco.nome })
        : t(`${P}.BLOCO.FRASE_SEM_BLOCO`),
      dentro: bloco?.frases || [],
    };
  },
  consultar: (passo, t) => {
    const [dado] = passo.guardar || [];
    return {
      texto: dado
        ? t(`${P}.CONSULTAR.HISTORICO`, {
            fonte: fonteEmFrase(passo.fonte, t),
            dado: dado.nome,
            valor: valorDoTeste(dado.caminho),
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

// #2932–#2934 — o ensaio de verdade dos três com motor, a partir do nó do
// servidor ({ faria, dados, ramos }). Nada sai no ensaio: a busca só com o OK de
// quem ensaia (`consulta`, LivreBuscaNoEnsaio), e nunca com o endereço na tela.
const AVISO_DO_BLOCO = {
  bloco_sumiu: 'BLOCO_SUMIU',
  bloco_de_outro_alvo: 'BLOCO_DE_OUTRO_ALVO',
  bloco_em_laco: 'BLOCO_EM_LACO',
  bloco_fundo_demais: 'BLOCO_FUNDO_DEMAIS',
};
const ENSAIO_COM_MOTOR = {
  // Passou do teto: o total de verdade e quantos ficam para as próximas vezes.
  repetir_lista: (no, t) => {
    const {
      total = 0,
      primeiros = [],
      fora_do_teto: fora = 0,
      mais_alem: maisAlem = false,
    } = no.dados;
    if (!total) return { destaque: t(`${P}.REPETIR.ENSAIO_NINGUEM`) };
    const nomes = emLista(primeiros, t);
    if (!fora) return { destaque: t(`${P}.REPETIR.ENSAIO`, { total, nomes }) };
    const chave = maisAlem ? 'ENSAIO_COM_TETO_MAIS' : 'ENSAIO_COM_TETO';
    return {
      destaque: t(`${P}.REPETIR.${chave}`, {
        total,
        todos: total + fora,
        fora,
        nomes,
      }),
    };
  },
  usar_bloco: (no, t) => ({
    destaque: t(`${P}.BLOCO.ENSAIO_DE_VERDADE`, { bloco: no.dados.nome }),
  }),
  // Na consulta pronta, o servidor diz o que ela usaria desta conversa
  // (`entradas`): com tudo preenchido, "Buscar agora" busca com isso; com algo
  // vazio, a tela diz o que falta e por qual caminho seguiria.
  consultar: (no, t, passo) => {
    const destaque = t(`${P}.CONSULTAR.ENSAIO`, {
      fonte: fonteEmFrase(passo?.fonte, t),
    });
    const entradas = no.dados?.entradas;
    if (!entradas)
      return {
        destaque,
        consulta: (passo?.guardar || []).length ? passo : null,
      };
    const vazias = Object.keys(entradas).filter(nome => !entradas[nome]);
    if (!vazias.length)
      return { destaque, consulta: { ...passo, entradasDoEnsaio: entradas } };
    const rotulos = consultaPronta(passo?.fonte?.consulta)?.entradas || [];
    const nomes = vazias.map(nome => {
      const rotulo = rotulos.find(entrada => entrada.nome === nome)?.rotulo;
      return rotulo ? rotulo.charAt(0).toLowerCase() + rotulo.slice(1) : nome;
    });
    return {
      destaque,
      aviso: t(`${P}.CONSULTAR.ENSAIO_SEM_ENTRADA`, {
        entradas: emLista(nomes, t),
      }),
    };
  },
};

export const linhaDoEnsaioComMotor = (no, t, passo) => {
  if (no.faria === 'passos_novos_desligados')
    return { aviso: t(`${P}.DESLIGADOS_NO_ENSAIO`) };
  if (AVISO_DO_BLOCO[no.faria])
    return { aviso: t(`${P}.BLOCO.${AVISO_DO_BLOCO[no.faria]}`) };
  return ENSAIO_COM_MOTOR[no.tipo]?.(no, t, passo) || {};
};

// #2931, #2935 e #2936 — a linha do ensaio de verdade, do nó que a API devolve
// (EsperaNoEnsaio): quem receberia o pedido, os horários livres de agora, o
// balão como o cliente leria e o que sai com a janela de 24 h fechada. Sem
// passo pronto no nó, nil: o ensaio usa a linha de sempre (o canal, a pausa).
const modeloForaDaJanela = (modelo, t) =>
  modelo
    ? t('AUTOMACAO_LIVRE.ENSAIO.MODELO_FORA_DA_JANELA', { modelo })
    : t(`${P}.SEM_MODELO_FORA_DA_JANELA`);
const comOpcoes = (texto, opcoes, botoes) =>
  [
    texto,
    ...opcoes.map((opcao, i) => (botoes ? opcao : `${i + 1}. ${opcao}`)),
  ].join('\n');

const ENSAIO_REAL = {
  pedir_aprovacao: (dados, t) => ({
    destaque: t(`${P}.APROVACAO.ENSAIO_PARA`, {
      nomes: emLista(dados.para || [], t),
    }),
  }),
  sem_quem_aprove: (dados, t) => ({
    aviso: t(`${P}.APROVACAO.ENSAIO_SEM_QUEM`),
  }),
  marcar_reuniao: (dados, t) => ({
    destaque: t(`${P}.REUNIAO.ENSAIO`, {
      horarios: emLista(dados.horarios || [], t),
    }),
    balao: comOpcoes(dados.convite, dados.horarios || [], dados.botoes),
    aviso: modeloForaDaJanela(dados.modelo, t),
  }),
  reuniao_sem_responsavel: (dados, t) => ({
    aviso: t(`${P}.REUNIAO.ENSAIO_SEM_RESPONSAVEL`),
  }),
  reuniao_sem_pagina: (dados, t) => ({
    aviso: t(`${P}.REUNIAO.ENSAIO_SEM_PAGINA`),
  }),
  sem_horario: (dados, t) => ({ aviso: t(`${P}.REUNIAO.ENSAIO_SEM_HORARIO`) }),
  pesquisa_nota: (dados, t) => ({
    destaque: t(`${P}.PESQUISA.ENSAIO`, {
      espera: duracaoEmFrase(dados.espera, t),
    }),
    balao: dados.pergunta,
    aviso: modeloForaDaJanela(dados.modelo, t),
  }),
  pesquisa_recente: (dados, t) => ({
    aviso: t(`${P}.PESQUISA.ENSAIO_RECENTE`),
  }),
  passos_novos_desligados: (dados, t) => ({
    aviso: t(`${P}.ENSAIO_DESLIGADO`),
  }),
  ia_desligada: (dados, t) => ({ aviso: t(`${P}.ENSAIO_IA_DESLIGADA`) }),
};

export const linhaDoEnsaioReal = (no, t) =>
  ENSAIO_REAL[no.faria]?.(no.dados || {}, t) || null;

// A linha do histórico de verdade: quem respondeu o pedido e o motivo, o
// horário da reunião marcada, a nota (e o comentário, para quem vê a
// conversa). `hora` formata a data no idioma de quem olha.
export const detalheDoHistorico = (dados, t, hora) => {
  const linhas = [];
  if (dados.por_nome)
    linhas.push(
      t(
        `${P}.APROVACAO.${dados.ramo === 'recusado' ? 'HISTORICO_RECUSOU' : 'HISTORICO_APROVOU'}`,
        { quem: dados.por_nome }
      )
    );
  if (dados.motivo_da_recusa)
    linhas.push(
      t(`${P}.APROVACAO.HISTORICO_MOTIVO_DITO`, {
        motivo: dados.motivo_da_recusa,
      })
    );
  if (dados.horario)
    linhas.push(t(`${P}.REUNIAO.HISTORICO`, { horario: hora(dados.horario) }));
  if (Number.isInteger(dados.nota))
    linhas.push(
      dados.comentario
        ? t(`${P}.PESQUISA.HISTORICO_NOTA_COMENTARIO`, {
            nota: dados.nota,
            comentario: dados.comentario,
          })
        : t(`${P}.PESQUISA.HISTORICO_NOTA`, { nota: dados.nota })
    );
  return linhas;
};

// O resumo da pesquisa na lista: "Pesquisa: média 8,6 com 37 respostas".
export const resumoDaPesquisa = (pesquisa, t, locale) => {
  if (!pesquisa) return '';
  if (!pesquisa.respostas) return t(`${P}.PESQUISA.RESUMO_VAZIO`);
  const media = new Intl.NumberFormat(locale.replace('_', '-'), {
    maximumFractionDigits: 1,
  }).format(pesquisa.media);
  return t(
    `${P}.PESQUISA.RESUMO`,
    { media, n: pesquisa.respostas },
    pesquisa.respostas
  );
};
