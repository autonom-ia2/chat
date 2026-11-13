import { effectScope } from 'vue';
import { useTrazerLista } from '../../trazer/useTrazerLista';

// Apoio dos specs do estado de "Trazer minha lista" (trazer/useTrazerLista.js)
// com uma fonte de mentira: cada método é um `vi.fn()` que o spec responde.
export const erroDeNome = (nome, extra = {}) =>
  Object.assign(new Error(nome), { name: nome, ...extra });

export const MARCADOR = { situacao: 'lendo', id: 'l1' };
export const PERGUNTAS = [
  { id: 'clientes' },
  { id: 'telefone', coluna: 'Cel', indice: 1 },
];
export const RESPONDIDAS = { clientes: 'sim_todas', telefone: 'da_pessoa' };

export const problema = (linha, extra = {}) => ({
  linha,
  tipo: 'telefone',
  nome: `Pessoa ${linha}`,
  valor: '(11) 9738-0014',
  estado: 'aberto',
  ...extra,
});

// A leitura no formato da tela (o que a fonte devolve).
export const lida = (extra = {}) => ({
  id: 'l1',
  arquivo: 'a.csv',
  valores: 'inteiros',
  temEmpresa: true,
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Cel', destino: 'telefone' },
    { indice: 6, nome: 'Situação', destino: 'informacao' },
  ],
  perguntas: [],
  respostas: {},
  resumo: { total: 200, novas: 180, completadas: 15, juntadas: 0, entram: 195 },
  exemplos: [],
  problemas: [problema(14)],
  problemasTotal: 1,
  ...extra,
});

export const fonteDeMentira = (extra = {}) => ({
  ler: vi.fn().mockResolvedValue(lida()),
  retomar: vi.fn(),
  maisProblemas: vi.fn(),
  responder: vi.fn(),
  consertar: vi.fn(),
  deixarDeFora: vi.fn(),
  reabrir: vi.fn(),
  trocarDestino: vi.fn(),
  trazer: vi.fn().mockResolvedValue({ trazidaId: 't1' }),
  andamento: vi.fn().mockResolvedValue({
    porcentagem: 100,
    situacao: 'pronto',
    novas: 180,
    completadas: 15,
  }),
  ...extra,
});

export const montarTela = (fonte = fonteDeMentira()) => {
  const escopo = effectScope();
  const avisar = vi.fn();
  const aoFalhar = vi.fn();
  const tela = escopo.run(() => useTrazerLista({ fonte, avisar, aoFalhar }));
  return { tela, fonte, avisar, aoFalhar, parar: () => escopo.stop() };
};

// A tela já no Conferir, com a leitura `leitura`.
export const noConferir = async (leitura = lida(), extra = {}) => {
  const fonte = fonteDeMentira({
    ler: vi.fn().mockResolvedValue(leitura),
    ...extra,
  });
  const montada = montarTela(fonte);
  await montada.tela.escolherArquivo({ name: 'a.csv' });
  return montada;
};

// Uma promessa que o spec resolve quando quiser (a escrita "em voo").
export const emVoo = () => {
  let resolver;
  let rejeitar;
  const promessa = new Promise((resolve, reject) => {
    resolver = resolve;
    rejeitar = reject;
  });
  return { promessa, resolver, rejeitar };
};
