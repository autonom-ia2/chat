import fs from 'fs';
import path from 'path';
import { GUIDE_ROUTE_REGISTRY, isGuideRoute } from '../guideRouteRegistry';

// O mapa do Guia é gerado a partir do roteador (issue #534). Estes testes seguram
// o contrato entre as duas pontas: o que o Guia manda navegar precisa existir na
// lista, e a lista não pode ser mantida à mão.
const kb = fs.readFileSync(
  path.resolve(process.cwd(), 'lib/operator_guide/guia-produto.md'),
  'utf8'
);

const navTargets = [...kb.matchAll(/^- nav_target: `([a-z0-9_]+)`$/gm)].map(
  encontrado => encontrado[1]
);

describe('mapa de navegação do Guia', () => {
  it('leva a base de conhecimento a apontar só para telas conhecidas', () => {
    const desconhecidas = [...new Set(navTargets)].filter(
      nome => !isGuideRoute(nome)
    );

    expect(desconhecidas).toEqual([]);
  });

  it('cobre mais telas do que os fluxos escritos à mão cobriam', () => {
    // Antes do gerador a lista tinha 57 rotas, mantidas à mão e sempre atrás do
    // produto. Se este número cair, alguém voltou a editar o arquivo gerado.
    expect(GUIDE_ROUTE_REGISTRY.size).toBeGreaterThan(100);
  });

  it('não repete nomes de rota', () => {
    const lista = [...GUIDE_ROUTE_REGISTRY];

    expect(lista).toHaveLength(new Set(lista).size);
  });
});
