import { folhaNova } from './useFolhaDaLista';
import {
  SOBRE_A_LISTA,
  comoMandada,
  empresaPadraoDaGaveta,
} from '../utils/acharConfiraEstados';

// #2692 — o que vai por cima da lista em cada estado ?demo= (gaveta, folha,
// pronto) e o relógio que anda sozinho na demonstração ("buscando",
// "Mandando…"). Saiu de AcharConfiraPage.vue para a página caber na trava de
// 600 linhas (#677). Fora da demonstração, nenhum estado tem algo por cima.
const ESPERA_DA_DEMO = 9000;
const ENVIO_PARADO_EM = 9;

export function useSobreDaLista({
  demo,
  estado,
  route,
  mudarEstado,
  trocar,
  pessoaNome,
  pessoaId,
  subpainel,
  gaveta,
  folha,
  pronto,
  empresas,
  deFora,
  elegiveis,
  escolhidas,
  entramLista,
  enviar,
}) {
  let relogioDaDemo = null;
  const pararRelogioDaDemo = () => {
    if (relogioDaDemo) clearTimeout(relogioDaDemo);
    relogioDaDemo = null;
  };
  const andarDepois = proximo => {
    pararRelogioDaDemo();
    relogioDaDemo = setTimeout(() => mudarEstado(proximo), ESPERA_DA_DEMO);
  };

  // Só na demonstração: os parâmetros dela (?mandada=, ?empresa=) não valem
  // fora dela, e a tela da API não tem nada por cima ao abrir.
  const aplicarSobre = () => {
    if (!demo.value) return;
    const sobre = SOBRE_A_LISTA[estado.value] || {};
    const mandada = Number(route.query.mandada);
    if (mandada) trocar(mandada, item => comoMandada(item, pessoaNome.value));
    if (sobre.pessoa) pessoaId.value = sobre.pessoa;
    subpainel.value = sobre.subpainel || null;
    pararRelogioDaDemo();
    gaveta.value = null;
    folha.value = null;
    pronto.value = null;
    if (sobre.gaveta) {
      const pedida = Number(route.query.empresa);
      const empresa =
        empresas.value.find(item => item.id === pedida) ||
        empresaPadraoDaGaveta(sobre.empresa, {
          deFora: deFora.value,
          elegiveis: elegiveis.value,
        });
      gaveta.value = empresa ? { id: empresa.id, passo: sobre.gaveta } : null;
    }
    if ('folha' in sobre) {
      folha.value = folhaNova(sobre.folha, Boolean(sobre.mostrarFora));
      if (sobre.enviar) enviar();
      if (sobre.enviandoParado) {
        folha.value = {
          ...folha.value,
          enviando: {
            feitas: Math.min(ENVIO_PARADO_EM, escolhidas.value.length),
            total: escolhidas.value.length,
          },
        };
        andarDepois('pronto');
      }
    }
    if (sobre.pronto === 'funil') {
      const n = sobre.uma
        ? 1
        : escolhidas.value.length - (sobre.jaEstavam || 0);
      pronto.value = {
        tipo: 'funil',
        n,
        jaEstavam: sobre.jaEstavam || 0,
        nome: escolhidas.value[0]?.nome,
      };
    }
    if (sobre.pronto === 'lista') {
      pronto.value = { tipo: 'lista', n: entramLista.value };
    }
  };

  return { aplicarSobre, andarDepois, pararRelogioDaDemo };
}
