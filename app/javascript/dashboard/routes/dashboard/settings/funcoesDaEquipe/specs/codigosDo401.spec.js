import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { FRASE_DO_401 } from '../salvarFuncao';

// #2308: os códigos do 401 saem do servidor (GrantGuard#deny! e o refuse(..., :unauthorized) do controller). Lidos
// dos próprios arquivos: se o servidor renomear ou ganhar um código, este spec falha, em vez de a tela cair em
// SEM_ACESSO em silêncio. Sem regex: corta o texto pelas marcas.
const ler = caminho => readFileSync(resolve(process.cwd(), caminho), 'utf8');

// Cada trecho entre `marca` e a aspa seguinte.
const depoisDe = (fonte, marca) =>
  fonte
    .split(marca)
    .slice(1)
    .map(trecho => trecho.slice(0, trecho.indexOf("'")));

const codigosDoServidor = () => {
  const guarda = ler('enterprise/app/services/custom_roles/grant_guard.rb');
  const controller = ler(
    'enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb'
  );
  const doController = controller
    .split("refuse('")
    .slice(1)
    .map(trecho => trecho.slice(0, trecho.indexOf(')')))
    .filter(chamada => chamada.endsWith(':unauthorized'))
    .map(chamada => chamada.slice(0, chamada.indexOf("'")));
  return [
    ...new Set([
      ...depoisDe(guarda, "deny!('"),
      ...depoisDe(guarda, "def deny!(code = '"),
      ...doController,
    ]),
  ].sort();
};

describe('códigos do 401 de /custom_roles', () => {
  it('cada código que o servidor manda tem frase, e não sobra frase sem código', () => {
    expect(codigosDoServidor()).toEqual([
      'feature_off',
      'out_of_reach',
      'own_role',
    ]);
    expect(Object.keys(FRASE_DO_401).sort()).toEqual(codigosDoServidor());
  });
});
