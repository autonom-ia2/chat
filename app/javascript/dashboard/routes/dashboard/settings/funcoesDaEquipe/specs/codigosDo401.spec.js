import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';
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

const guarda = () => ler('enterprise/app/services/custom_roles/grant_guard.rb');
const controller = () =>
  ler('enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb');
const vezes = (fonte, marca) => fonte.split(marca).length - 1;

const doController = () =>
  controller()
    .split("refuse('")
    .slice(1)
    .map(trecho => trecho.slice(0, trecho.indexOf(')')))
    .filter(chamada => chamada.endsWith(':unauthorized'))
    .map(chamada => chamada.slice(0, chamada.indexOf("'")));

const codigosDoServidor = () =>
  [
    ...new Set([
      ...depoisDe(guarda(), "deny!('"),
      ...depoisDe(guarda(), "def deny!(code = '"),
      ...doController(),
    ]),
  ].sort();

describe('códigos do 401 de /custom_roles', () => {
  it('cada código que o servidor manda tem frase, e não sobra frase sem código', () => {
    expect(codigosDoServidor()).toEqual([
      'feature_off',
      'out_of_reach',
      'own_role',
    ]);
    expect(Object.keys(FRASE_DO_401).sort()).toEqual(codigosDoServidor());
  });

  // Rodada 4: uma chamada numa forma que a leitura acima não reconhece (deny!(:codigo), refuse("x"), refuse(codigo))
  // faria um código passar sem frase. Cada deny!( e refuse( tem de ser de uma forma conhecida; refuse(e.code, …)
  // repassa o código do GrantGuard::Denied, lido do grant_guard.rb.
  it('toda recusa do servidor está numa forma que este spec lê', () => {
    const fonteDaGuarda = guarda();
    expect(vezes(fonteDaGuarda, 'deny!(')).toBe(
      vezes(fonteDaGuarda, "deny!('") +
        vezes(fonteDaGuarda, "def deny!(code = '")
    );
    const fonteDoController = controller();
    expect(vezes(fonteDoController, 'refuse(')).toBe(
      vezes(fonteDoController, "refuse('") +
        vezes(fonteDoController, 'refuse(e.code, ') +
        vezes(fonteDoController, 'def refuse(')
    );
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
