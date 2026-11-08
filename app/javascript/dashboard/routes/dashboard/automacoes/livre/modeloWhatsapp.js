// #2468 F4b — o modelo aprovado da Meta do passo "mensagem", para quando a
// janela de 24 h do número oficial estiver fechada. A régua é a do servidor
// (Autonomia::Automacao::ModeloWhatsapp): aprovado, de utilidade, com o corpo
// pedindo {{1}}..{{n}} e nada além do corpo para preencher.

// Só utilidade, por ora (a mesma constante do servidor).
export const CATEGORIAS = ['UTILITY'];
const CANAL = 'Channel::Whatsapp';
const TOPO_COM_MIDIA = ['IMAGE', 'VIDEO', 'DOCUMENT', 'LOCATION'];

export const corpoDoModelo = modelo =>
  (modelo?.components || []).find(
    parte => String(parte.type).toUpperCase() === 'BODY'
  )?.text || '';

// O que vem entre {{ e }}, por split (sem regex), sem repetir.
export const variaveisDoCorpo = corpo => [
  ...new Set(
    corpo
      .split('{{')
      .slice(1)
      .map(parte => parte.split('}}')[0].trim())
  ),
];

export const pedeMais = parte => {
  const tipo = String(parte.type).toUpperCase();
  if (tipo === 'HEADER')
    return (
      TOPO_COM_MIDIA.includes(String(parte.format).toUpperCase()) ||
      String(parte.text || '').includes('{{')
    );
  if (tipo === 'BUTTONS')
    return (parte.buttons || []).some(botao =>
      String(botao.url || '').includes('{{')
    );
  return false;
};

export const numeradas = nomes =>
  [...nomes].sort((a, b) => Number(a) - Number(b)).join() ===
  nomes.map((_, indice) => String(indice + 1)).join();

export const serve = modelo =>
  String(modelo.status).toLowerCase() === 'approved' &&
  CATEGORIAS.includes(String(modelo.category).toUpperCase()) &&
  numeradas(variaveisDoCorpo(corpoDoModelo(modelo))) &&
  !(modelo.components || []).some(pedeMais);

// Os modelos que servem, das caixas WhatsApp oficiais que a pessoa vê, um por
// nome e idioma (a automação procura na caixa da conversa). Mesmo nome e idioma
// com corpo diferente em outra caixa fica `divergente`: cada conversa recebe o
// da própria caixa.
export const modelosDasCaixas = caixas => {
  const vistos = new Map();
  (caixas || [])
    .filter(caixa => caixa.channel_type === CANAL)
    .flatMap(caixa => caixa.message_templates || [])
    .filter(serve)
    .forEach(modelo => {
      const chave = `${modelo.name}|${modelo.language}`;
      const visto = vistos.get(chave);
      if (!visto) vistos.set(chave, modelo);
      else if (corpoDoModelo(visto) !== corpoDoModelo(modelo))
        vistos.set(chave, { ...visto, divergente: true });
    });
  return [...vistos.values()];
};

export const chaveDoModelo = modelo =>
  modelo
    ? `${modelo.nome || modelo.name}|${modelo.idioma || modelo.language}`
    : '';
