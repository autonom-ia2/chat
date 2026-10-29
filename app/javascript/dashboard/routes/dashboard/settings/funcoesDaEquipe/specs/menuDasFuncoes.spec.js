import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  ALTERAR_NOVA,
  CRIAR_NOVA,
  DUPLICAR_NOVA,
  LISTA_NOVA,
} from '../listaPelaFlag';

// #2308: o activeOn de "Funções da equipe" no menu lateral escreve os nomes das rotas à mão (importar listaPelaFlag
// traria a store para o menu). Lido do próprio Sidebar.vue: se uma rota for renomeada, este spec falha, em vez de o
// menu deixar de marcar a tela em silêncio.
const activeOnDoMenu = () => {
  const fonte = readFileSync(
    resolve(
      process.cwd(),
      'app/javascript/dashboard/components-next/sidebar/Sidebar.vue'
    ),
    'utf8'
  );
  const item = fonte.slice(fonte.indexOf("name: 'Settings Custom Roles'"));
  const lista = item.slice(
    item.indexOf('activeOn: [') + 'activeOn: ['.length,
    item.indexOf(']')
  );
  return lista
    .split(',')
    .map(nome => nome.trim())
    .filter(Boolean)
    .map(nome => nome.slice(1, -1));
};

describe('menu de Funções da equipe', () => {
  it('marca as quatro rotas novas, com os nomes de listaPelaFlag', () => {
    expect(activeOnDoMenu()).toEqual([
      LISTA_NOVA,
      CRIAR_NOVA,
      ALTERAR_NOVA,
      DUPLICAR_NOVA,
    ]);
  });
});
