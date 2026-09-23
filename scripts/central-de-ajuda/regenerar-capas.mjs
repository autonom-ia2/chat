#!/usr/bin/env node
// Regenera o .jpg (capa/pôster) de todo vídeo já pronto em
// public/central-de-ajuda/videos/, a partir do .mp4 que já existe — não
// grava nada de novo. Usa o fim do primeiro cue do .vtt (a legenda de
// abertura) como o ponto da capa, igual ao motor faz numa gravação nova.
//
// Uso: node scripts/central-de-ajuda/regenerar-capas.mjs
/* eslint-disable no-console -- é uma CLI; o progresso na tela é o produto. */
/* eslint-disable no-await-in-loop -- processa vídeo por vídeo, sem motivo pra paralelizar. */

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gerarPoster } from './lib/video.mjs';

const RAIZ_REPO = new URL('../../', import.meta.url).pathname;
const PASTA_VIDEOS = join(RAIZ_REPO, 'public/central-de-ajuda/videos');

function tempoEmSegundos(vttTimestamp) {
  const [h, m, sMs] = vttTimestamp.split(':');
  const [s, ms] = sMs.split('.');
  return (
    Number(h) * 3600 + Number(m) * 60 + Number(s) + Number(ms || 0) / 1000
  );
}

// Lê o último cue do .vtt (a linha "HH:MM:SS.mmm --> HH:MM:SS.mmm") e pega o tempo de
// FIM: é o fim do vídeo, na cena "Pronto", com o resultado na tela.
function fimDoUltimoCue(vttTexto) {
  const linha = vttTexto
    .split('\n')
    .filter(l => l.includes('-->'))
    .at(-1);
  if (!linha) return null;
  const fim = linha.split('-->')[1].trim();
  return tempoEmSegundos(fim);
}

async function main() {
  const arquivos = readdirSync(PASTA_VIDEOS).filter(f => f.endsWith('.mp4'));
  arquivos.sort();

  console.log(`Regenerando capa de ${arquivos.length} vídeos…`);
  const semVtt = [];
  for (const arquivoMp4 of arquivos) {
    const id = arquivoMp4.slice(0, -'.mp4'.length);
    const mp4 = join(PASTA_VIDEOS, arquivoMp4);
    const vtt = join(PASTA_VIDEOS, `${id}.vtt`);
    const jpg = join(PASTA_VIDEOS, `${id}.jpg`);

    let tempoSegundos = 0;
    try {
      const vttTexto = readFileSync(vtt, 'utf8');
      const fim = fimDoUltimoCue(vttTexto);
      if (fim !== null) tempoSegundos = Math.max(0, fim - 0.2);
      else semVtt.push(id);
    } catch {
      semVtt.push(id);
    }

    await gerarPoster(mp4, jpg, tempoSegundos);
    console.log(`  ${id} — capa em ${tempoSegundos.toFixed(2)}s`);
  }

  if (semVtt.length) {
    console.log(
      `\nSem .vtt (ou sem cue) — capa ficou no quadro 0: ${semVtt.join(', ')}`
    );
  }
  console.log('\nPronto.');
}

main().catch(erro => {
  console.error(erro);
  process.exit(1);
});
