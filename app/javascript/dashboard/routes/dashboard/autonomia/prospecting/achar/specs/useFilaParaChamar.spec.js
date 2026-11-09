import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useFilaParaChamar } from '../composables/useFilaParaChamar';

// #2697 — uma ação por vez na fila, pelo composable (sem depender do botão
// desligado na tela): com uma gravação em voo, mandar, "Não serve" e "Depois"
// não gravam nada; a trava solta mesmo quando a gravação falha; o "Desfazer"
// espera; e a tela remontada espera a gravação em voo antes de pedir a fila.
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
    fila: vi
      .fn()
      .mockResolvedValue({ cartoes: [], fim: null, truncada: false }),
    funis: vi.fn().mockResolvedValue([]),
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

it('"Desfazer" com uma gravação em voo não chama voltarNaoServe nem muda a empresa', async () => {
  const { fila, fonte } = montar();
  fonte.descartar.mockResolvedValue({});
  await fila.tirar('closed');
  const avisoDaPrimeira = fila.aviso.value;
  expect(fila.indice.value).toBe(1);

  const voo = emVoo();
  fonte.depois.mockReturnValue(voo.promessa);
  fila.depois();
  expect(fila.aviso.value).toBeNull();
  // A faixa da empresa anterior ainda na tela (o botão desligado é a outra
  // metade): tocar "Desfazer" não faz nada.
  fila.aviso.value = avisoDaPrimeira;
  await fila.desfazer();
  expect(fonte.voltarNaoServe).not.toHaveBeenCalled();
  expect(fila.indice.value).toBe(1);

  voo.terminar({});
  await esperarTudo();
  expect(fila.indice.value).toBe(2);
});

it('envio que falha solta a trava, avisa e deixa as outras ações voltarem', async () => {
  const { fila, fonte } = montar();
  fonte.mandarParaFunil.mockRejectedValue(new Error('rede'));

  await fila.mandar();
  expect(useAlert).toHaveBeenCalled();
  expect(fila.gravando.value).toBe(false);
  expect(fila.fase.value).toBe('cartao');

  fonte.depois.mockResolvedValue({});
  await fila.depois();
  expect(fonte.depois).toHaveBeenCalledTimes(1);
});

it('resposta de envio sem created/existing vira o aviso de falha e fica no cartão', async () => {
  const { fila, fonte } = montar();
  useAlert.mockClear();
  fonte.mandarParaFunil.mockResolvedValue({});

  await fila.mandar();
  expect(useAlert).toHaveBeenCalledWith('PROSPECTING_ACHAR.FOLHA.ERRO_FUNIL');
  expect(fila.gravando.value).toBe(false);
  expect([fila.indice.value, fila.fase.value]).toEqual([0, 'cartao']);
});

it('se a gravação estoura de vez (enviar lança), a trava solta mesmo assim', async () => {
  const { fila, fonte } = montar();
  fonte.mandarParaFunil.mockRejectedValue(new Error('rede'));
  useAlert.mockImplementationOnce(() => {
    throw new Error('quebrou');
  });

  await expect(fila.mandar()).rejects.toThrow('quebrou');
  expect(fila.gravando.value).toBe(false);
});

it('a tela remontada espera a gravação em voo antes de pedir a fila', async () => {
  const primeira = montar();
  const voo = emVoo();
  primeira.fonte.depois.mockReturnValue(voo.promessa);
  primeira.fila.depois();

  const segunda = montar();
  const carregou = segunda.fila.carregar();
  await esperarTudo();
  expect(segunda.fonte.fila).not.toHaveBeenCalled();

  voo.terminar({});
  await carregou;
  expect(segunda.fonte.fila).toHaveBeenCalledTimes(1);
});

it('gravação que nunca responde não prende a tela: passado o teto, a fila é pedida', async () => {
  vi.useFakeTimers();
  try {
    const primeira = montar();
    primeira.fonte.depois.mockReturnValue(new Promise(() => {}));
    primeira.fila.depois();

    const segunda = montar();
    const carregou = segunda.fila.carregar();
    await vi.advanceTimersByTimeAsync(14000);
    expect(segunda.fonte.fila).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1500);
    await carregou;
    expect(segunda.fonte.fila).toHaveBeenCalledTimes(1);
  } finally {
    vi.useRealTimers();
  }
});
