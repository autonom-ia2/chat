import { ref } from 'vue';
import { useFilaParaChamar } from '../composables/useFilaParaChamar';

// #2697 — uma ação por vez na fila, pelo composable (sem depender do botão
// desligado na tela): com uma gravação em voo, mandar, "Não serve" e "Depois"
// não gravam nada; e a fila só anda se ainda está na empresa que foi gravada.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// Uma promessa que só resolve quando o teste manda.
const emVoo = () => {
  let terminar;
  const promessa = new Promise(resolve => {
    terminar = resolve;
  });
  return { promessa, terminar };
};

const esperarTudo = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

const montar = () => {
  const fonte = {
    mandarParaFunil: vi.fn(),
    descartar: vi.fn(),
    voltarNaoServe: vi.fn().mockResolvedValue({}),
    depois: vi.fn(),
    desfazerDepois: vi.fn().mockResolvedValue({}),
  };
  const fila = useFilaParaChamar({
    demo: ref(null),
    fonte: ref(fonte),
    carregarAjustes: vi.fn(),
    ajustes: ref(null),
    contaId: ref(1),
    usuarioId: ref(7),
    destino: ref({ funil: { id: 3 }, etapa: { id: 4, nome: 'Novo contato' } }),
    donoId: ref(null),
    pessoaNome: ref('Você'),
  });
  fila.cartoes.value = [
    { id: 1, nome: 'Empresa Um' },
    { id: 2, nome: 'Empresa Dois' },
    { id: 3, nome: 'Empresa Três' },
  ];
  return { fila, fonte };
};

it('segundo "Não serve" com o primeiro em voo não grava, e a fila anda uma vez', async () => {
  const { fila, fonte } = montar();
  const voo = emVoo();
  fonte.descartar.mockReturnValue(voo.promessa);

  fila.tirar('closed');
  fila.tirar('closed');
  expect(fonte.descartar).toHaveBeenCalledTimes(1);

  voo.terminar({});
  await esperarTudo();
  expect(fila.indice.value).toBe(1);
  expect(fila.naoServem.value).toBe(1);
});

it('mandar com "Depois" em voo não manda', async () => {
  const { fila, fonte } = montar();
  const voo = emVoo();
  fonte.depois.mockReturnValue(voo.promessa);

  fila.depois();
  await fila.mandar();
  expect(fonte.mandarParaFunil).not.toHaveBeenCalled();

  voo.terminar({});
  await esperarTudo();
  expect(fila.indice.value).toBe(1);
  expect(fila.fase.value).toBe('cartao');
});

it('"Depois" com mandar em voo não grava, e o sucesso fica na empresa mandada', async () => {
  const { fila, fonte } = montar();
  const voo = emVoo();
  fonte.mandarParaFunil.mockReturnValue(voo.promessa);

  fila.mandar();
  await fila.depois();
  await fila.tirar('closed');
  expect(fonte.depois).not.toHaveBeenCalled();
  expect(fonte.descartar).not.toHaveBeenCalled();

  voo.terminar({ created: [{ lead_id: 1 }], existing: [] });
  await esperarTudo();
  expect(fila.fase.value).toBe('sucesso');
  expect(fila.indice.value).toBe(0);
});

it('se a fila voltou para outra empresa durante a gravação, ela não anda', async () => {
  const { fila, fonte } = montar();
  fonte.depois.mockResolvedValue({});
  await fila.depois();
  expect(fila.indice.value).toBe(1);

  const voo = emVoo();
  fonte.descartar.mockReturnValue(voo.promessa);
  fila.tirar('closed');
  await fila.desfazer();
  expect(fila.indice.value).toBe(0);

  voo.terminar({});
  await esperarTudo();
  expect(fila.indice.value).toBe(0);
});
