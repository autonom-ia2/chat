import { onUnmounted, shallowRef, toValue } from 'vue';

// #934 — o que a pessoa tem aberto, selecionado e filtrado, para o Guia saber do
// que ela fala ("move esses para Cotação").
//
// A tela declara em uma linha; o painel do Guia lê na hora de perguntar. Vale a
// última tela montada que declarou, e a declaração some quando ela desmonta.
// O servidor confere a forma e lê cada id com a permissão da pessoa: isto é
// contexto, nunca autorização.
//
// `recurso` é o nome que o Guia usa para ler a conta: 'crm/cards',
// 'conversations' (o id é o número da conversa na tela), 'contacts'.

const MAX_ABERTOS = 3;
// Acima disso o servidor descarta; o total continua indo, para o Guia saber quantos são.
const MAX_SELECIONADOS = 50;

const declarado = shallowRef(null);

const idValido = valor => {
  const numero = Number(valor);
  return Number.isInteger(numero) && numero > 0 ? numero : null;
};

const escalar = valor =>
  (typeof valor === 'string' && valor.trim() !== '') ||
  typeof valor === 'boolean' ||
  (typeof valor === 'number' && Number.isFinite(valor));

// Só valor simples ou lista de valores simples; vazio não é filtro.
const filtrosSimples = filtros =>
  Object.fromEntries(
    Object.entries(filtros || {}).filter(([, valor]) =>
      Array.isArray(valor)
        ? valor.length > 0 && valor.every(escalar)
        : escalar(valor)
    )
  );

const abertosDe = aberto =>
  (aberto || [])
    .map(item => ({ recurso: item?.recurso, id: idValido(item?.id) }))
    .filter(item => item.recurso && item.id)
    .slice(0, MAX_ABERTOS);

const selecaoDe = selecionados => {
  const ids = (selecionados?.ids || []).map(idValido).filter(Boolean);
  if (!selecionados?.recurso || !ids.length) return null;
  return {
    recurso: selecionados.recurso,
    ids: ids.slice(0, MAX_SELECIONADOS),
    total: Math.max(idValido(selecionados.total) || 0, ids.length),
  };
};

// `aberto`, `selecionados` e `filtros` podem ser ref, computed ou função.
export function declararContexto(fontes) {
  declarado.value = fontes;
  onUnmounted(() => {
    if (declarado.value === fontes) declarado.value = null;
  });
}

// O objeto `tela` que vai ao servidor. Sem declaração, só a rota.
export function contextoAtual(route) {
  const tela = { rota: route?.name };
  const fontes = declarado.value;
  if (!fontes) return tela;

  const aberto = abertosDe(toValue(fontes.aberto));
  const selecionados = selecaoDe(toValue(fontes.selecionados));
  const filtros = filtrosSimples(toValue(fontes.filtros));
  if (aberto.length) tela.aberto = aberto;
  if (selecionados) tela.selecionados = selecionados;
  if (Object.keys(filtros).length) tela.filtros = filtros;
  return tela;
}

export function useContextoDaTela() {
  return { declararContexto, contextoAtual };
}
