// Confere se o mapa do Guia está em dia com o roteador (issue #534).
//
// Falha quando alguém mexeu em rotas ou nas explicações e esqueceu de rodar
// `pnpm guia:build` — ou quando editou o arquivo gerado à mão.
import fs from 'fs';
import path from 'path';
import { construir, PASTA_PACOTES, SAIDA_DO_PACOTE } from './build.mjs';

const r = p => path.resolve(process.cwd(), p);

const resultado = await construir({ escrever: false });

const conferir = (caminho, esperado) => {
  const atual = fs.existsSync(r(caminho))
    ? fs.readFileSync(r(caminho), 'utf8')
    : '';
  return atual === esperado ? null : caminho;
};

const desatualizados = [
  conferir('lib/operator_guide/guia-produto.md', resultado.kb),
  conferir(
    'app/javascript/dashboard/helper/guideRouteRegistry.js',
    resultado.registry
  ),
  // Pacote de tradução (#1802): só existe quando há `pacotes/<camada>/porques.md`.
  ...Object.entries(resultado.pacotes).map(([camada, texto]) =>
    conferir(`${PASTA_PACOTES}/${camada}/${SAIDA_DO_PACOTE}`, texto)
  ),
].filter(Boolean);

// Base de pacote sem o porques.md dela: o Guia leria um texto que ninguém mais gera.
const orfaos = fs.existsSync(r(PASTA_PACOTES))
  ? fs
      .readdirSync(r(PASTA_PACOTES), { recursive: true })
      .filter(arquivo => path.basename(arquivo) === SAIDA_DO_PACOTE)
      .map(arquivo => path.dirname(arquivo).split(path.sep).join('/'))
      .filter(camada => !resultado.pacotes[camada])
      .map(camada => `${PASTA_PACOTES}/${camada}/${SAIDA_DO_PACOTE}`)
  : [];
if (orfaos.length) {
  console.error('Base do Guia de pacote sem o porques.md da camada:');
  orfaos.forEach(caminho => console.error(`  - ${caminho}`));
  console.error('\nApague o arquivo ou devolva o porques.md da camada.');
  process.exit(1);
}

if (desatualizados.length) {
  console.error('O mapa do Guia está desatualizado:');
  desatualizados.forEach(caminho => console.error(`  - ${caminho}`));
  console.error(
    '\nRode `pnpm guia:build` e envie o resultado junto com a sua mudança.'
  );
  process.exit(1);
}

console.log(
  `mapa do Guia em dia — ${resultado.fluxos} fluxos, ${resultado.rotas} telas no roteador, ` +
    `${resultado.semExplicacao.length} ainda sem explicação`
);
