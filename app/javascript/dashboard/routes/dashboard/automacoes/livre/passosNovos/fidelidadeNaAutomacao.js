// #3100 — os dois passos da fidelidade na Automação livre ("Dar carimbos ou
// pontos" e "Mandar cupom"), o gatilho "Quando completa o cartão", os dados
// novos do "Pôr um dado" e as duas receitas de aviso. "Dar carimbos" já está no
// editor (PASSOS_NOVOS); o "Mandar cupom" chega com o cupom.

export const FA = 'FIDELIDADE.AUTOMACAO';
export const QUANTOS_PARA_DAR = [1, 2, 3, 5, 10];
export const MOTIVO_MAXIMO = 60;

// Os dados do cartão no `catalogo.valores` (mesmo formato dos outros:
// `caminho` e a `frase`, que é a chave do texto). Os três do cartão o servidor
// já manda, na base do contato (Fidelidade::NaAutomacao); os do cupom chegam
// com o cupom.
export const SALDO = 'contato.fidelidade_saldo';
export const FALTAM = 'contato.fidelidade_faltam';
export const PREMIO = 'contato.fidelidade_premio';
export const VALORES_DA_FIDELIDADE = [
  { caminho: SALDO, frase: 'FIDELIDADE.VALORES.SALDO' },
  { caminho: FALTAM, frase: 'FIDELIDADE.VALORES.FALTAM' },
  { caminho: PREMIO, frase: 'FIDELIDADE.VALORES.PREMIO' },
  { caminho: 'cupom.codigo', frase: 'FIDELIDADE.VALORES.CUPOM_CODIGO' },
  { caminho: 'cupom.oferta', frase: 'FIDELIDADE.VALORES.CUPOM_OFERTA' },
  { caminho: 'cupom.vale_ate', frase: 'FIDELIDADE.VALORES.CUPOM_VALE_ATE' },
];

export const novoDarCarimbos = id => ({
  id,
  tipo: 'dar_carimbos',
  quantos: 1,
  motivo: '',
});

// O texto já nasce com o código, o que o cupom dá e até quando vale.
export const novoMandarCupom = (id, t) => ({
  id,
  tipo: 'mandar_cupom',
  cupom_id: null,
  texto: [
    t(`${FA}.CUPOM.TEXTO_PADRAO_1`),
    { $valor: 'cupom.codigo' },
    t(`${FA}.CUPOM.TEXTO_PADRAO_2`),
    { $valor: 'cupom.oferta' },
    t(`${FA}.CUPOM.TEXTO_PADRAO_3`),
    { $valor: 'cupom.vale_ate' },
    t(`${FA}.CUPOM.TEXTO_PADRAO_4`),
  ],
});

export const darCarimbosPronto = passo =>
  Number.isInteger(passo?.quantos) &&
  passo.quantos > 0 &&
  (passo.motivo || '').length <= MOTIVO_MAXIMO;

const temCodigo = partes =>
  (partes || []).some(
    parte => typeof parte !== 'string' && parte.$valor === 'cupom.codigo'
  );

// O "Mandar cupom" só fica pronto com o cupom escolhido e o código no texto:
// sem o código, o cliente recebe a mensagem e não tem o que usar.
export const mandarCupomPronto = passo =>
  passo?.cupom_id != null && temCodigo(passo.texto);

export const faltaOCodigo = passo => !temCodigo(passo?.texto);

// ---------- as duas receitas de aviso (ProgramaPronto) ----------
// "Usar o aviso" abre a automação nova com uma destas, desligada
// (?receita=FIDELIDADE_SALDO&unidade=carimbos): a pessoa confere e liga. Não
// moram nas receitas prontas da porta: só fazem sentido com o cartão criado e
// leem o saldo do contato.
// - Saldo: no card ganho, espera um pouco (o carimbo da compra entra logo
//   depois da venda) e manda o saldo, quantos faltam e o prêmio.
// - Completo: no gatilho "completou o cartão", manda que o prêmio é dele.
export const RECEITA_DO_AVISO = {
  saldo: 'FIDELIDADE_SALDO',
  meta: 'FIDELIDADE_COMPLETO',
};
export const ESPERA_DO_SALDO = { valor: 10, unidade: 'minutos' };
export const GATILHO_COMPLETO = 'contato.completou_cartao_fidelidade';
// As flags que as duas pedem: a mensagem e os gatilhos de card e de contato.
export const REQUER_DOS_AVISOS = ['automacao_mensagens', 'automacao_gatilhos'];

const R = 'FIDELIDADE.RECEITAS';
const dado = $valor => ({ $valor });

const RECEITAS = {
  FIDELIDADE_SALDO: (t, unidade) => ({
    nome: t(`${R}.SALDO_NOME`),
    receita: {
      gatilho: { tipo: 'card.ganho' },
      passos: [
        { id: 'p1', tipo: 'esperar', duracao: { ...ESPERA_DO_SALDO } },
        {
          id: 'p2',
          tipo: 'mensagem',
          texto: [
            t(`${R}.SALDO_TEXTO_1`),
            dado(SALDO),
            t(`${R}.SALDO_TEXTO_2`, { unidade }),
            dado(FALTAM),
            t(`${R}.SALDO_TEXTO_3`),
            dado(PREMIO),
            t(`${R}.SALDO_TEXTO_4`),
          ],
        },
      ],
    },
  }),
  FIDELIDADE_COMPLETO: t => ({
    nome: t(`${R}.COMPLETO_NOME`),
    receita: {
      gatilho: { tipo: GATILHO_COMPLETO },
      passos: [
        {
          id: 'p1',
          tipo: 'mensagem',
          texto: [
            t(`${R}.COMPLETO_TEXTO_1`),
            dado(PREMIO),
            t(`${R}.COMPLETO_TEXTO_2`),
          ],
        },
      ],
    },
  }),
};

export const ehReceitaDaFidelidade = chave => Boolean(RECEITAS[chave]);

// { nome, receita } da receita de aviso, ou null para outra chave. A unidade
// ("carimbos" ou "pontos") vem do cartão; sem ela, carimbos.
export const receitaDaFidelidade = (chave, t, tipo = 'carimbos') => {
  const montar = RECEITAS[chave];
  if (!montar) return null;
  const unidade = t(
    `FIDELIDADE.NOME_DA_UNIDADE.${tipo === 'pontos' ? 'pontos' : 'carimbos'}`
  );
  return montar(t, unidade);
};
