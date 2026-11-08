import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';
import { FRASE_DO_401 } from '../salvarFuncao';

// #2308: os códigos do 401 saem do servidor, numa lista só (rodada 5): UNAUTHORIZED_CODES do controller, que junta os
// CODES do GrantGuard (o Denied recusa qualquer outro) e o FEATURE_OFF. Lidos dos próprios arquivos: se o servidor
// renomear ou ganhar um código, este spec falha, em vez de a tela cair em SEM_ACESSO em silêncio. Só lê as constantes,
// sem regex: corta o texto pelas marcas. Que todo 401 leve um código da lista é provado por pedido, no spec de request.
const ler = caminho => readFileSync(resolve(process.cwd(), caminho), 'utf8');
const guarda = () => ler('enterprise/app/services/custom_roles/grant_guard.rb');
const controller = () =>
  ler('enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb');

// O texto de `NOME = '...'`; undefined quando a constante não existe.
const constante = (fonte, nome) => {
  const marca = `${nome} = '`;
  if (!fonte.includes(marca)) return undefined;
  const resto = fonte.slice(fonte.indexOf(marca) + marca.length);
  return resto.slice(0, resto.indexOf("'"));
};
// Os itens de `NOME = [A, B].freeze`.
const itens = (fonte, nome) => {
  const marca = `${nome} = [`;
  const resto = fonte.slice(fonte.indexOf(marca) + marca.length);
  return resto
    .slice(0, resto.indexOf(']'))
    .split(',')
    .map(item => item.trim());
};

const DA_GUARDA = '*CustomRoles::GrantGuard::CODES';
const codigosDoServidor = () =>
  itens(controller(), 'UNAUTHORIZED_CODES')
    .flatMap(item =>
      item === DA_GUARDA
        ? itens(guarda(), 'CODES').map(nome => constante(guarda(), nome))
        : [constante(controller(), item)]
    )
    .sort();

describe('códigos do 401 de /custom_roles', () => {
  it('cada código que o servidor manda tem frase, e não sobra frase sem código', () => {
    expect(codigosDoServidor()).toEqual([
      'feature_off',
      'out_of_reach',
      'own_role',
    ]);
    expect(Object.keys(FRASE_DO_401).sort()).toEqual(codigosDoServidor());
  });

  // Rodada 4: cada frase do 401 (e SEM_ACESSO e REDE, que não vêm com código) existe no salvar e no apagar, nos dois
  // idiomas: uma chave que falte mostraria a chave crua.
  it('cada frase do 401 existe em SALVAR e em APAGAR.RECUSA, em pt_BR e en', () => {
    const frases = [...Object.values(FRASE_DO_401), 'SEM_ACESSO', 'REDE'];
    [ptBR, en].forEach(idioma => {
      const { SALVAR, APAGAR } = idioma.FUNCOES_EQUIPE;
      frases.forEach(frase => {
        expect(SALVAR[frase], `SALVAR.${frase}`).toBeTruthy();
        expect(APAGAR.RECUSA[frase], `APAGAR.RECUSA.${frase}`).toBeTruthy();
      });
    });
  });
});
