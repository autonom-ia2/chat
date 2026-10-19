// #1426/#1427 — de onde as telas do material (tema 4) e do clipe no Testar (tema 5) leem o que o
// servidor ainda não tem. Hoje: o adaptador falso. Quando os endpoints existirem, trocar só esta
// linha pelo módulo da API, com as mesmas funções (ler, enviar, tirar, resolver, pedirAutoteste,
// testar).
export { criarMaterialFalso as criarFonteDoMaterial } from './materialFalso';
