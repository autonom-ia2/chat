import { coberta, proximoSeparador } from '../separadorDeDia';

// Revisão de 17/10: as etiquetas de dia presas no topo se empilhavam (a mais larga
// aparecia por trás da de cima). Agora a de cima some quando a seguinte a alcança.
const lista = () => {
  const ul = document.createElement('ul');
  ul.innerHTML = `
    <li data-separador-de-dia id="ontem"></li>
    <li id="m1"></li>
    <li id="m2"></li>
    <li data-separador-de-dia id="hoje"></li>
    <li id="m3"></li>`;
  return ul;
};
const comTopo = (elemento, top, altura = 26) => {
  elemento.getBoundingClientRect = () => ({ top, bottom: top + altura });
  return elemento;
};

describe('etiquetas de dia presas no topo (#1702)', () => {
  it('acha a próxima etiqueta pulando as mensagens', () => {
    const ul = lista();
    expect(proximoSeparador(ul.querySelector('#ontem')).id).toBe('hoje');
    expect(proximoSeparador(ul.querySelector('#hoje'))).toBeNull();
  });

  it('com a etiqueta seguinte encostada (ou presa no mesmo topo), a de cima some', () => {
    const ul = lista();
    const ontem = comTopo(ul.querySelector('#ontem'), 8);
    expect(coberta(ontem, comTopo(ul.querySelector('#hoje'), 8))).toBe(true);
    expect(coberta(ontem, comTopo(ul.querySelector('#hoje'), 30))).toBe(true);
  });

  it('com a etiqueta seguinte ainda longe, ou sem ela, continua à mostra', () => {
    const ul = lista();
    const ontem = comTopo(ul.querySelector('#ontem'), 8);
    expect(coberta(ontem, comTopo(ul.querySelector('#hoje'), 400))).toBe(false);
    expect(coberta(ontem, null)).toBe(false);
  });
});
