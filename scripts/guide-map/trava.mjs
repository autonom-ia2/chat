/* eslint-disable no-console -- script de linha de comando: o log do CI é a saída dele */
// Trava do Guia da Plataforma no Pull Request (issue #535).
//
// PR que cria tela nova sem explicação escrita não passa. Não por burocracia:
// o Guia responde a partir do porques.md, e tela sem explicação é tela que ele
// não sabe mostrar a ninguém. É o que o fazia envelhecer quando tudo era
// escrito à mão.
//
// Para não travar sem ajudar, a IA escreve o rascunho de cada bloco e ele
// aparece como comentário no próprio PR — enquanto quem fez a tela ainda sabe
// o porquê dela. A trava só libera quando uma PESSOA põe a explicação no
// porques.md: se o rascunho da IA liberasse sozinho, a trava não cobraria
// ninguém.
//
// Três saídas para liberar:
//   1. explicar a tela no porques.md;
//   2. declarar a tela no bloco `_fora_do_guia`, com o motivo (definitivo);
//   3. rótulo `guia-nao-se-aplica` no PR, com o motivo escrito no corpo dele.
import fs from 'fs';
import { construir } from './build.mjs';
import {
  mudancasDoMapa,
  montarBloco,
  pedirRascunho,
  numaLinha,
  lerRegistroDe,
  contextoDaTela,
  exemplosDoPorques,
  avisarGitHub,
} from './aprendiz.mjs';

export const ROTULO_DISPENSA = 'guia-nao-se-aplica';
// A linha que o autor escreve no corpo do PR. É um campo de formulário, não
// linguagem a interpretar: a marca é fixa e o que vem depois dela é o motivo.
export const MARCA_DO_MOTIVO = 'guia não se aplica:';
// Identifica o comentário da trava, para atualizar o mesmo em vez de empilhar
// um comentário novo a cada push.
export const MARCA_DO_COMENTARIO = '<!-- guia-trava -->';

const PORQUES = 'lib/operator_guide/porques.md';

// ---------------------------------------------------------------------------
// Decisão

export const motivoDaDispensa = corpo => {
  const linha = String(corpo || '')
    .split('\n')
    .map(texto => texto.trim())
    .find(texto => texto.toLowerCase().startsWith(MARCA_DO_MOTIVO));
  if (!linha) return null;
  const motivo = linha.slice(MARCA_DO_MOTIVO.length).trim();
  return motivo || null;
};

export const decidir = ({ novas, rotulos, corpo }) => {
  if (!novas.length) return { bloqueia: false, situacao: 'em_dia' };

  if (rotulos.includes(ROTULO_DISPENSA)) {
    const motivo = motivoDaDispensa(corpo);
    // Dispensa sem motivo é só um botão de desligar a trava. O motivo escrito
    // é o que deixa rastro de por que aquela tela ficou fora do Guia.
    if (!motivo) return { bloqueia: true, situacao: 'dispensa_sem_motivo' };
    return { bloqueia: false, situacao: 'dispensada', motivo };
  }

  return { bloqueia: true, situacao: 'sem_explicacao' };
};

// ---------------------------------------------------------------------------
// O comentário no PR

const SAIDAS = [
  '1. **Explicar** — cole o bloco em `lib/operator_guide/porques.md`, corrija o que a IA errou e rode `pnpm guia:build`.',
  '2. **Tirar do Guia de vez** — se a tela não é para o cliente, declare no bloco `_fora_do_guia` do `porques.md`, com o motivo ao lado.',
  `3. **Dispensar só neste PR** — rótulo \`${ROTULO_DISPENSA}\` e, no corpo do PR, uma linha \`Guia não se aplica: <motivo>\`.`,
];

const quemPodeVer = tela =>
  (tela.papeis || []).join(', ') || 'sem restrição declarada';

const secaoDaTela = ({ tela, rascunho, erro }) => {
  const partes = [
    '',
    `### \`${tela.nome}\` — \`${tela.caminho}\``,
    `- Quem pode ver: ${quemPodeVer(tela)}`,
  ];
  if (erro) {
    partes.push(`- **Sem rascunho:** ${erro}`);
    return partes;
  }
  partes.push(
    `- **O que a IA não conseguiu saber:** ${numaLinha(rascunho.duvidas) || 'nada declarado'}`,
    '',
    '```md',
    montarBloco(tela, rascunho),
    '```'
  );
  return partes;
};

export const comentarioDaTrava = ({ decisao, rascunhos }) => {
  const partes = [MARCA_DO_COMENTARIO];

  if (decisao.situacao === 'em_dia') {
    partes.push('✅ **Guia em dia:** toda tela deste PR tem explicação.');
  } else if (decisao.situacao === 'dispensada') {
    partes.push(
      `✅ **Dispensado pelo rótulo \`${ROTULO_DISPENSA}\`.** Motivo: ${decisao.motivo}`
    );
  } else if (decisao.situacao === 'dispensa_sem_motivo') {
    partes.push(
      `🔒 **O rótulo \`${ROTULO_DISPENSA}\` está no PR, mas falta o motivo.**`,
      '',
      'Escreva no corpo do PR uma linha `Guia não se aplica: <motivo>`. Sem o motivo, a dispensa não deixa rastro de por que a tela ficou fora do Guia.'
    );
  } else {
    partes.push(
      `🔒 **Este PR cria ${rascunhos.length} tela(s) que o Guia ainda não sabe explicar.**`,
      '',
      'O rascunho abaixo foi escrito pela IA a partir do código da tela. Ele é ponto de partida — o CI só libera quando a explicação estiver no `porques.md`. Três saídas:',
      '',
      ...SAIDAS
    );
    rascunhos.forEach(item => partes.push(...secaoDaTela(item)));
  }

  return `${partes.join('\n')}\n`;
};

// ---------------------------------------------------------------------------
// Execução

const rascunhar = async (novas, chave) => {
  const exemplos = exemplosDoPorques(fs.readFileSync(PORQUES, 'utf8'));
  const rascunhos = [];
  // Uma tela por vez: são poucas por PR, e o erro de uma não pode sumir no meio
  // de chamadas em paralelo.
  // eslint-disable-next-line no-restricted-syntax
  for (const tela of novas) {
    if (!chave) {
      rascunhos.push({
        tela,
        erro: 'a chave da IA não chegou a este job (PR vindo de fork não recebe segredos). A trava continua valendo: use uma das três saídas acima.',
      });
    } else {
      try {
        // eslint-disable-next-line no-await-in-loop
        const rascunho = await pedirRascunho({
          tela,
          contexto: contextoDaTela(tela.nome),
          exemplos,
          chave,
          modelo: process.env.MODELO,
        });
        rascunhos.push({ tela, rascunho });
      } catch (erro) {
        // O rascunho é ajuda; a trava é o que importa. Falha da IA não libera
        // nem derruba a trava: o motivo vai para o comentário e para o log.
        console.error(erro.message);
        rascunhos.push({ tela, erro: erro.message });
      }
    }
  }
  return rascunhos;
};

const executar = async () => {
  const antes = await lerRegistroDe(process.env.BASE);
  if (!antes) {
    console.log(
      `O mapa do Guia não existia na base (${process.env.BASE}). Nada a conferir.`
    );
    avisarGitHub('bloqueia', 'false');
    return avisarGitHub('comentario', 'nenhum');
  }

  const atual = await construir({ escrever: false });
  const { entraram: novas } = mudancasDoMapa({
    antes,
    depois: atual.telas,
    semExplicacao: atual.semExplicacao,
    humanos: atual.humanos,
  });
  const decisao = decidir({
    novas,
    rotulos: String(process.env.ROTULOS || '').split(','),
    corpo: process.env.PR_BODY,
  });

  const rascunhos =
    decisao.situacao === 'sem_explicacao'
      ? await rascunhar(novas, process.env.OPENAI_API_KEY)
      : [];

  fs.writeFileSync(
    process.env.COMENTARIO,
    comentarioDaTrava({ decisao, rascunhos })
  );
  console.log(
    `Situação: ${decisao.situacao}. Telas novas sem explicação: ${novas.length}.`
  );
  avisarGitHub('bloqueia', String(decisao.bloqueia));
  // Em dia: só vale comentar se já existia um aviso da trava, para marcar como
  // resolvido. PR que nunca teve problema não ganha comentário nenhum.
  return avisarGitHub(
    'comentario',
    decisao.situacao === 'em_dia' ? 'resolvido' : 'novo'
  );
};

if (process.argv[1] && process.argv[1].endsWith('trava.mjs')) {
  await executar();
}
