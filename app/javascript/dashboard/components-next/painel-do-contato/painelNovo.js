// #2138 — PROTÓTIPO: liga o painel novo do contato só neste navegador.
// ?painel=novo liga e ?painel=antigo desliga; a escolha fica guardada no
// navegador para sobreviver à navegação. No PR1 isto vira a flag da conta.
import { ref } from 'vue';

const CHAVE = 'proto2138_painel_do_contato';

const lerGuardado = () => {
  try {
    return window.localStorage.getItem(CHAVE) === 'novo';
  } catch {
    return false;
  }
};

const guardar = ligado => {
  try {
    window.localStorage.setItem(CHAVE, ligado ? 'novo' : 'antigo');
  } catch {
    // Sem armazenamento, vale só a URL desta visita.
  }
};

const inicial = () => {
  const pedido = new URLSearchParams(window.location.search).get('painel');
  if (pedido === 'novo' || pedido === 'antigo') {
    guardar(pedido === 'novo');
    return pedido === 'novo';
  }
  return lerGuardado();
};

export const painelNovoLigado = ref(inicial());
