// #2138 — o estado de uma parte do painel que pede dados ao servidor:
// carregando (esqueleto), pronto, vazio (a parte some), escondido (403: a pessoa
// não tem acesso, a parte some sem aviso) e erro ("Não deu para carregar esta
// parte agora." com "Tentar de novo"). Só a resposta do último pedido vale.
import { ref, shallowRef } from 'vue';

export const ESTADO = Object.freeze({
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  VAZIO: 'vazio',
  ESCONDIDO: 'escondido',
  ERRO: 'erro',
});

const SEM_ACESSO = 403;

export const estadoDoErro = erro =>
  erro?.response?.status === SEM_ACESSO ? ESTADO.ESCONDIDO : ESTADO.ERRO;

// `buscar` devolve os dados; `temConteudo(dados)` diz se a parte aparece.
export function useParteDoPainel(buscar, temConteudo) {
  const estado = ref(ESTADO.CARREGANDO);
  const dados = shallowRef(null);
  let pedido = 0;

  const carregar = async (...args) => {
    pedido += 1;
    const meu = pedido;
    estado.value = ESTADO.CARREGANDO;
    try {
      const resposta = await buscar(...args);
      if (meu !== pedido) return;
      dados.value = resposta;
      estado.value = temConteudo(resposta) ? ESTADO.PRONTO : ESTADO.VAZIO;
    } catch (erro) {
      if (meu !== pedido) return;
      dados.value = null;
      estado.value = estadoDoErro(erro);
    }
  };

  // Sem o que buscar (ex.: contato sem id): a parte some, e um pedido em voo
  // deixa de valer.
  const esconder = () => {
    pedido += 1;
    dados.value = null;
    estado.value = ESTADO.VAZIO;
  };

  return { estado, dados, carregar, esconder };
}
