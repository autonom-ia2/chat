/* eslint-disable no-console -- script de linha de comando: o log do CI é a saída dele */
// Trava da Central de Ajuda "Plataforma" no Pull Request (#614).
//
// A decisão do Rodrigo, que não se reabre: a Central segue o Guia. A trava roda
// `conferir()` (o mesmo `central:check` que qualquer um roda local) contra o estado do
// PR: se falhar, barra o merge e comenta o que fazer.
//
// Sem dispensa por rótulo (retirada depois da revisão independente: um rótulo sem motivo
// escrito era só um botão de desligar a trava, sem deixar rastro de por quê). A saída para
// tela que não é do produto é declará-la em `mapa.fora`, com o motivo ao lado — o próprio
// `conferir()` já entende isso (`telasCobertas`).
import fs from 'fs';
import path from 'path';
import { lerArtigos, conferir, carregarRegistro } from './conferir.mjs';
import { lerPorques } from '../guide-map/build.mjs';
import { avisarGitHub } from '../guide-map/aprendiz.mjs';

// Identifica o comentário da trava, para atualizar o mesmo em vez de empilhar um novo a
// cada push — mesmo esquema do job do Guia.
export const MARCA_DO_COMENTARIO = '<!-- central-trava -->';

const MAPA = 'docs/central-de-ajuda/mapa-de-artigos.json';
const PORQUES = 'lib/operator_guide/porques.md';

const SAIDAS = [
  '1. **Escrever o artigo** — `lib/central_de_ajuda/<capítulo>/<id>-<slug>.md` e a entrada em `docs/central-de-ajuda/mapa-de-artigos.json`. O kit está em `docs/central-de-ajuda/kit-do-escritor.md`.',
  '2. **Declarar fora do produto** — se a tela não é para o cliente, acrescente em `mapa.fora` uma entrada `{"rota": "<nome_da_tela>", "motivo": "<por quê>"}`.',
];

export const comentarioDaTrava = ({ problemas }) => {
  const partes = [MARCA_DO_COMENTARIO];

  if (!problemas.length) {
    partes.push('✅ **Central em dia:** `central:check` passou.');
    return `${partes.join('\n')}\n`;
  }

  partes.push(
    '🔒 **A Central de Ajuda está fora de dia com o Guia** (`central:check` falhou):',
    '',
    '```',
    ...problemas,
    '```',
    '',
    'Duas saídas:',
    '',
    ...SAIDAS
  );
  return `${partes.join('\n')}\n`;
};

// ---------------------------------------------------------------------------
// Execução

const r = p => path.resolve(process.cwd(), p);

const executar = async () => {
  const raiz = process.cwd();
  const artigos = lerArtigos(raiz);
  const mapa = JSON.parse(fs.readFileSync(r(MAPA), 'utf8'));
  const humanos = lerPorques(fs.readFileSync(r(PORQUES), 'utf8'));
  const registro = await carregarRegistro(raiz);

  const resultado = conferir({ artigos, mapa, registro, humanos, raiz });

  fs.writeFileSync(
    process.env.COMENTARIO,
    comentarioDaTrava({ problemas: resultado.problemas })
  );
  console.log(
    resultado.ok
      ? 'Central em dia.'
      : `Central fora de dia: ${resultado.problemas.length} problema(s).`
  );
  avisarGitHub('bloqueia', String(!resultado.ok));
  // Em dia: só vale comentar se já existia um aviso da trava, para marcar como resolvido
  // (mesmo esquema do job do Guia) — PR que nunca teve problema não ganha comentário.
  return avisarGitHub('comentario', resultado.ok ? 'resolvido' : 'novo');
};

if (process.argv[1] && process.argv[1].endsWith('trava.mjs')) {
  await executar();
}
