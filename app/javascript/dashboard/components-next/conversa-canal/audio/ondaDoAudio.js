// A onda do áudio no balão do WhatsApp (#1702): o volume do próprio áudio em
// barras finas, como no app. Cada barra vira um nível de 0 a NIVEIS - 1, que a
// tela desenha com alturas fixas (sem estilo inline); o nível 0 ainda aparece,
// para o silêncio não sumir.
import Decoder from 'wavesurfer.js/dist/decoder.js';

export const BARRAS = 48;
export const NIVEIS = 12;
const TAXA = 8000;
// O chão da onda é o ruído de fundo: o volume abaixo do qual fica 1 em cada 10
// trechos. Nunca passa da metade do maior, senão som constante viraria chão.
const FUNDO = 0.1;

const volumes = (amostras, total) => {
  const tamanho = Math.max(1, Math.floor(amostras.length / total));
  return Array.from({ length: total }, (_, i) => {
    const inicio = i * tamanho;
    const fim = Math.min(amostras.length, inicio + tamanho);
    if (fim <= inicio) return 0;
    let soma = 0;
    for (let j = inicio; j < fim; j += 1) soma += amostras[j] * amostras[j];
    return Math.sqrt(soma / (fim - inicio));
  });
};

// Média com as vizinhas (peso 1-2-1): a onda fica com forma de fala, sem dente.
const suavizar = valores =>
  valores.map(
    (valor, i) =>
      ((valores[i - 1] ?? valor) + 2 * valor + (valores[i + 1] ?? valor)) / 4
  );

// Volume médio (RMS) de cada trecho, suavizado, do ruído de fundo ao maior: a
// fala tem altos e baixos como no app, e o silêncio fica no chão.
export const barrasDoAudio = (amostras, total = BARRAS) => {
  if (!amostras?.length) return Array(total).fill(0);
  const suaves = suavizar(volumes(amostras, total));
  const ordenados = [...suaves].sort((x, y) => x - y);
  const maior = ordenados[ordenados.length - 1];
  if (!maior) return Array(total).fill(0);
  const chao = Math.min(
    ordenados[Math.floor(ordenados.length * FUNDO)],
    maior / 2
  );
  return suaves.map(valor =>
    Math.round(Math.max(0, (valor - chao) / (maior - chao)) * (NIVEIS - 1))
  );
};

// Baixa e decodifica o áudio só para desenhar a onda. Se o navegador não puder
// ler o arquivo (formato, rede, outro domínio sem permissão), devolve null e o
// balão fica com as barras neutras: tocar continua funcionando pelo <audio>.
// A onda de cada endereço fica guardada: o balão que sai e volta à tela (rolagem,
// troca de conversa) não baixa o arquivo de novo. Só as últimas, para não crescer.
const ONDAS_GUARDADAS = 60;
const ondas = new Map();

const guardar = (url, onda) => {
  if (ondas.size >= ONDAS_GUARDADAS) ondas.delete(ondas.keys().next().value);
  ondas.set(url, onda);
};

export const carregarOnda = async (url, { signal } = {}) => {
  if (ondas.has(url)) return ondas.get(url);
  try {
    const resposta = await fetch(url, { signal });
    if (!resposta.ok) return null;
    const dados = await resposta.arrayBuffer();
    const audio = await Decoder.decode(dados, TAXA);
    const onda = {
      barras: barrasDoAudio(audio.getChannelData(0)),
      duracao: audio.duration,
    };
    guardar(url, onda);
    return onda;
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
