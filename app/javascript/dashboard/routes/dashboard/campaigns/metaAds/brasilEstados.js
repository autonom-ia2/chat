// Anúncios da Meta (#2198): os estados do Brasil por extenso, para escolher onde o anúncio aparece. A sigla vai para
// o servidor, que acha a região da Meta; a pessoa só vê o nome.
export const ESTADOS = [
  ['AC', 'Acre'],
  ['AL', 'Alagoas'],
  ['AP', 'Amapá'],
  ['AM', 'Amazonas'],
  ['BA', 'Bahia'],
  ['CE', 'Ceará'],
  ['DF', 'Distrito Federal'],
  ['ES', 'Espírito Santo'],
  ['GO', 'Goiás'],
  ['MA', 'Maranhão'],
  ['MT', 'Mato Grosso'],
  ['MS', 'Mato Grosso do Sul'],
  ['MG', 'Minas Gerais'],
  ['PA', 'Pará'],
  ['PB', 'Paraíba'],
  ['PR', 'Paraná'],
  ['PE', 'Pernambuco'],
  ['PI', 'Piauí'],
  ['RJ', 'Rio de Janeiro'],
  ['RN', 'Rio Grande do Norte'],
  ['RS', 'Rio Grande do Sul'],
  ['RO', 'Rondônia'],
  ['RR', 'Roraima'],
  ['SC', 'Santa Catarina'],
  ['SP', 'São Paulo'],
  ['SE', 'Sergipe'],
  ['TO', 'Tocantins'],
].map(([uf, name]) => ({ uf, name }));

// "sao paulo" acha "São Paulo": sem acento e sem diferença de maiúscula.
const COMBINING_START = 0x300;
const COMBINING_END = 0x36f;
export const semAcento = text =>
  [
    ...String(text || '')
      .normalize('NFD')
      .toLowerCase(),
  ]
    .filter(char => {
      const code = char.charCodeAt(0);
      return code < COMBINING_START || code > COMBINING_END;
    })
    .join('');

export const nomeDoEstado = uf =>
  ESTADOS.find(estado => estado.uf === uf)?.name || uf;
