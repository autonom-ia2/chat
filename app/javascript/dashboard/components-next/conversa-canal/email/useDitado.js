// Ditado da resposta de e-mail (#1786): grava pelo microfone do navegador, manda
// para a transcrição da conta e devolve o texto para entrar onde está o cursor.
// Estados: parado → ouvindo (⇄ pausado) → transcrevendo → parado. Cancelar descarta o
// áudio e solta o microfone. `fluxo` é o som do microfone, para desenhar a onda ao vivo.
import { onBeforeUnmount, ref, shallowRef } from 'vue';
import ConversaEmailAPI from 'dashboard/api/conversaEmail';

const UM_SEGUNDO = 1000;
// A transcrição roda na requisição (15 s do servidor): o ditado para sozinho aqui.
export const LIMITE_DO_DITADO = 120;

export const useDitado = () => {
  const estado = ref('parado');
  const segundos = ref(0);
  const erro = ref('');
  const fluxo = shallowRef(null);
  let gravador = null;
  let pedacos = [];
  let relogio = null;
  // Quem espera o texto (o "Pronto"). Sem ninguém esperando, o fim da gravação é cancelar.
  let aoTerminar = null;
  // Enquanto o navegador pede a permissão do microfone: segundo toque não abre outro.
  let pedindo = false;
  let desistiu = false;
  // Cancelar durante a transcrição: o texto que chegar depois é descartado (a resposta
  // pode já ser de outra conversa).
  let rodada = 0;

  const soltarMicrofone = () => {
    clearInterval(relogio);
    gravador?.stream?.getTracks().forEach(trilha => trilha.stop());
    gravador = null;
    fluxo.value = null;
  };
  const contar = () => {
    clearInterval(relogio);
    relogio = setInterval(() => {
      segundos.value += 1;
    }, UM_SEGUNDO);
  };

  const transcrever = async resolver => {
    estado.value = 'transcrevendo';
    const minha = rodada;
    try {
      const audio = new Blob(pedacos, {
        type: pedacos[0]?.type || 'audio/webm',
      });
      const { data } = await ConversaEmailAPI.ditar(audio);
      resolver(minha === rodada ? data.texto || '' : '');
    } catch (falha) {
      if (minha === rodada) {
        erro.value = falha?.response?.data?.error || 'falhou';
      }
      resolver('');
    } finally {
      estado.value = 'parado';
    }
  };

  const aoParar = () => {
    soltarMicrofone();
    const resolver = aoTerminar;
    aoTerminar = null;
    if (!resolver) {
      estado.value = 'parado';
      return;
    }
    transcrever(resolver);
  };

  const iniciar = async () => {
    if (pedindo || gravador) return;
    pedindo = true;
    desistiu = false;
    erro.value = '';
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      erro.value = 'microfone';
      return;
    } finally {
      pedindo = false;
    }
    // Cancelou ou fechou enquanto o navegador pedia a permissão: não grava.
    if (desistiu) {
      stream.getTracks().forEach(trilha => trilha.stop());
      return;
    }
    gravador = new MediaRecorder(stream);
    fluxo.value = stream;
    pedacos = [];
    gravador.ondataavailable = evento => pedacos.push(evento.data);
    gravador.onstop = aoParar;
    gravador.start();
    segundos.value = 0;
    contar();
    estado.value = 'ouvindo';
  };

  const gravando = () => gravador && gravador.state !== 'inactive';

  // Para de ouvir e devolve o texto (ou '' se falhou; o motivo fica em `erro`).
  const parar = () =>
    new Promise(resolve => {
      if (!gravando()) {
        soltarMicrofone();
        estado.value = 'parado';
        resolve('');
        return;
      }
      aoTerminar = resolve;
      gravador.stop();
    });

  // Pausar segura o relógio e o microfone; continuar grava no mesmo áudio.
  const pausarOuContinuar = () => {
    if (!gravador) return;
    if (gravador.state === 'recording') {
      gravador.pause();
      clearInterval(relogio);
      estado.value = 'pausado';
    } else if (gravador.state === 'paused') {
      gravador.resume();
      contar();
      estado.value = 'ouvindo';
    }
  };

  const cancelar = () => {
    aoTerminar = null;
    rodada += 1;
    if (pedindo) desistiu = true;
    if (gravando()) {
      gravador.stop();
      return;
    }
    soltarMicrofone();
    if (estado.value !== 'transcrevendo') estado.value = 'parado';
  };

  onBeforeUnmount(() => {
    aoTerminar = null;
    rodada += 1;
    desistiu = true;
    if (gravando()) gravador.stop();
    soltarMicrofone();
  });

  return {
    estado,
    segundos,
    erro,
    fluxo,
    iniciar,
    parar,
    pausarOuContinuar,
    cancelar,
  };
};
