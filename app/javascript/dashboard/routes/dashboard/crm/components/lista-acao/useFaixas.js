import { ref } from 'vue';

// #2283 — a faixa verde que fica no lugar da linha depois de uma ação
// ("Retorno de Ana feito." + "Desfazer"). Ela fica até a pessoa seguir: 10 s
// sem o mouse nem o foco nela. Ao sair, roda `aoSair` (o "Feito" só chama a
// API aqui, decisão 3). "Desfazer" tira a faixa sem chamar nada.
// `sairTodas` é para quando a pessoa deixa a tela: roda o que estava pendente
// na hora, com `{ saindoDaPagina }` para quem precisa de fetch keepalive.
export const TEMPO_DA_FAIXA = 10000;

export const useFaixas = ({ tempo = TEMPO_DA_FAIXA } = {}) => {
  const faixas = ref({});
  const relogios = new Map();

  const pausar = id => {
    clearTimeout(relogios.get(id));
    relogios.delete(id);
  };

  const tirar = id => {
    pausar(id);
    const { [id]: faixa, ...resto } = faixas.value;
    faixas.value = resto;
    return faixa;
  };

  const sair = (id, opcoes = {}) => {
    const faixa = tirar(id);
    return faixa?.aoSair?.(opcoes);
  };

  const seguir = id => {
    if (!faixas.value[id]) return;
    pausar(id);
    relogios.set(
      id,
      setTimeout(() => sair(id), tempo)
    );
  };

  // { texto, desfazivel, aoSair }
  const abrir = (id, faixa) => {
    faixas.value = { ...faixas.value, [id]: faixa };
    seguir(id);
  };

  const desfazer = id => {
    const faixa = faixas.value[id];
    if (!faixa?.desfazivel) return false;
    tirar(id);
    return true;
  };

  const sairTodas = (opcoes = {}) =>
    Object.keys(faixas.value).map(id => sair(id, opcoes));

  return { faixas, abrir, pausar, seguir, desfazer, sair, sairTodas };
};
