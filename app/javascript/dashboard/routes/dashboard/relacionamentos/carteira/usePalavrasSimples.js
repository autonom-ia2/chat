// #2899 (E6.6) — "Seu seguro em palavras simples" de um seguro: o texto
// guardado, por onde ele sai (`envio`: 'conversa', 'fora_da_janela' ou
// 'sem_conversa'), escrever (a plataforma escreve), guardar o que a pessoa
// ajustou e mandar ao cliente. Fala com a fonte e guarda o estado; a peça só
// desenha. Nada sai para o cliente sem o clique de "Enviar".
//
// Cada ação devolve `true` se deu certo; quando falha, a chave da frase fica em
// `erro` (carteira/recusas.js). A resposta de um seguro nunca entra na tela de
// outro (`rodada`, que `carregar` troca).
import { ref } from 'vue';
import { chaveDaRecusa, codigoDaRecusa } from './recusas';

export const ESTADOS_DAS_PALAVRAS = {
  CARREGANDO: 'carregando',
  ERRO: 'erro',
  PRONTO: 'pronto',
};

const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.PALAVRAS.NAO_DEU';
// Recusas cuja frase de sempre fala de outra coisa (do motivo da renovação, da
// leitura de PDF): aqui elas têm a sua.
const FRASES_DAS_PALAVRAS = {
  falta_texto: 'RELACIONAMENTOS_CARTEIRA.PALAVRAS.FALTA_TEXTO',
  texto_longo: 'RELACIONAMENTOS_CARTEIRA.PALAVRAS.TEXTO_LONGO',
  leitura_desligada: 'RELACIONAMENTOS_CARTEIRA.PALAVRAS.DESLIGADA',
};
// A conversa fechou ou sumiu entre abrir e enviar: a tela passa a oferecer
// copiar o texto.
const SEM_ENVIO = ['fora_da_janela', 'sem_conversa'];

export const usePalavrasSimples = (fonte, seguroId) => {
  const estado = ref(ESTADOS_DAS_PALAVRAS.CARREGANDO);
  const palavras = ref(null);
  const ocupado = ref('');
  const erro = ref('');
  let rodada = 0;

  const carregar = async () => {
    rodada += 1;
    const minha = rodada;
    estado.value = ESTADOS_DAS_PALAVRAS.CARREGANDO;
    erro.value = '';
    ocupado.value = '';
    try {
      const lidas = await fonte.palavras(seguroId());
      if (minha !== rodada) return;
      palavras.value = lidas;
      estado.value = ESTADOS_DAS_PALAVRAS.PRONTO;
    } catch {
      if (minha === rodada) estado.value = ESTADOS_DAS_PALAVRAS.ERRO;
    }
  };

  const fazer = async (nome, pedido) => {
    if (ocupado.value) return false;
    const minha = rodada;
    ocupado.value = nome;
    erro.value = '';
    try {
      const novas = await pedido(seguroId());
      if (minha === rodada) palavras.value = novas;
      return minha === rodada;
    } catch (falha) {
      if (minha === rodada) {
        const codigo = codigoDaRecusa(falha);
        erro.value =
          FRASES_DAS_PALAVRAS[codigo] || chaveDaRecusa(codigo, NAO_DEU);
        if (SEM_ENVIO.includes(codigo)) {
          palavras.value = { ...palavras.value, envio: codigo };
        }
      }
      return false;
    } finally {
      if (minha === rodada) ocupado.value = '';
    }
  };

  return {
    estado,
    palavras,
    ocupado,
    erro,
    carregar,
    escrever: () => fazer('escrever', id => fonte.escreverPalavras(id)),
    salvar: texto => fazer('salvar', id => fonte.salvarPalavras(id, texto)),
    enviar: () => fazer('enviar', id => fonte.enviarPalavras(id)),
  };
};
