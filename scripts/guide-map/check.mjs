// Confere se o mapa do Guia está em dia com o roteador (issue #534).
//
// Falha quando alguém mexeu em rotas ou nas explicações e esqueceu de rodar
// `pnpm guia:build` — ou quando editou o arquivo gerado à mão.
import fs from 'fs';
import path from 'path';
import { construir } from './build.mjs';

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
].filter(Boolean);

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
