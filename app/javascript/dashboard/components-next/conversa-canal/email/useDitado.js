// Ditado da resposta de e-mail (#1786): grava pelo microfone do navegador, manda
// para a transcrição da conta e devolve o texto para entrar onde está o cursor.
// Estados: parado → ouvindo (⇄ pausado) → transcrevendo → parado. Cancelar descarta o
// áudio. `fluxo` é o som do microfone, para desenhar a onda ao vivo.
import { onBeforeUnmount, ref, shallowRef } from 'vue';
import ConversaEmailAPI from 'dashboard/api/conversaEmail';

const UM_SEGUNDO = 1000;

export const useDitado = () => {
  const estado = ref('parado');
  const segundos = ref(0);
  const erro = ref('');
  const fluxo = shallowRef(null);
  let gravador = null;
  let pedacos = [];
  let relogio = null;
  let cancelado = false;

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

  const iniciar = async () => {
    erro.value = '';
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      gravador = new MediaRecorder(stream);
      fluxo.value = stream;
    } catch {
      erro.value = 'microfone';
      return;
    }
    pedacos = [];
    cancelado = false;
    gravador.ondataavailable = evento => pedacos.push(evento.data);
    gravador.start();
    segundos.value = 0;
    contar();
    estado.value = 'ouvindo';
  };

  // Para de ouvir e devolve o texto (ou '' se cancelou ou falhou; o motivo fica em `erro`).
  const parar = () =>
    new Promise(resolve => {
      if (!gravador) {
        resolve('');
        return;
      }
      gravador.onstop = async () => {
        soltarMicrofone();
        if (cancelado) {
          estado.value = 'parado';
          resolve('');
          return;
        }
        estado.value = 'transcrevendo';
        try {
          const audio = new Blob(pedacos, {
            type: pedacos[0]?.type || 'audio/webm',
          });
          const { data } = await ConversaEmailAPI.ditar(audio);
          resolve(data.texto || '');
        } catch (falha) {
          erro.value = falha?.response?.data?.error || 'falhou';
          resolve('');
        } finally {
          estado.value = 'parado';
        }
      };
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
    cancelado = true;
    if (gravador) gravador.stop();
    else estado.value = 'parado';
  };

  onBeforeUnmount(() => {
    cancelado = true;
    if (gravador?.state === 'recording') gravador.stop();
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
