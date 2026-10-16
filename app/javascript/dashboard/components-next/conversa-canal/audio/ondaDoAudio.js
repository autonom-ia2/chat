// A onda do áudio no balão do WhatsApp (#1702): o volume do próprio áudio em
// poucas barras, como no app. Cada barra vira um nível de 0 a NIVEIS - 1, que a
// tela desenha com alturas fixas (sem estilo inline).
import Decoder from 'wavesurfer.js/dist/decoder.js';

export const BARRAS = 36;
export const NIVEIS = 8;
const TAXA = 8000;

// Volume médio (RMS) de cada trecho, normalizado pelo maior: a fala tem altos e
// baixos como no app (o pico deixaria quase todas as barras no teto).
export const barrasDoAudio = (amostras, total = BARRAS) => {
  if (!amostras?.length) return Array(total).fill(0);
  const tamanho = Math.max(1, Math.floor(amostras.length / total));
  const picos = Array.from({ length: total }, (_, i) => {
    const inicio = i * tamanho;
    const fim = Math.min(amostras.length, inicio + tamanho);
    if (fim <= inicio) return 0;
    let soma = 0;
    for (let j = inicio; j < fim; j += 1) soma += amostras[j] * amostras[j];
    return Math.sqrt(soma / (fim - inicio));
  });
  const maior = Math.max(...picos);
  if (!maior) return Array(total).fill(0);
  return picos.map(pico =>
    Math.min(NIVEIS - 1, Math.round((pico / maior) * (NIVEIS - 1)))
  );
};

// Baixa e decodifica o áudio só para desenhar a onda. Se o navegador não puder
// ler o arquivo (formato, rede, outro domínio sem permissão), devolve null e o
// balão fica com as barras neutras: tocar continua funcionando pelo <audio>.
export const carregarOnda = async (url, { signal } = {}) => {
  try {
    const resposta = await fetch(url, { signal });
    if (!resposta.ok) return null;
    const dados = await resposta.arrayBuffer();
    const audio = await Decoder.decode(dados, TAXA);
    return {
      barras: barrasDoAudio(audio.getChannelData(0)),
      duracao: audio.duration,
    };
  } catch {
    return null;
  }
};

// "0:07", "1:23", como o app.
export const tempoDoAudio = segundos => {
  if (!Number.isFinite(segundos) || segundos < 0) return '0:00';
  const inteiro = Math.floor(segundos);
  return `${Math.floor(inteiro / 60)}:${String(inteiro % 60).padStart(2, '0')}`;
};
