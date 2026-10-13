import { CAMPOS } from '../constants';
import { CAMPO_NO_CATALOGO } from './campos';
import { conferirConteudo, juntarTextos } from './conteudo';
import { ordenarBotoes } from './regraEstrutural';

// Ida e volta entre a tela e o redator com IA (#1333). O redator só conhece
// chaves do catálogo único (#1331), escritas {{cliente.primeiro_nome}}; a tela
// guarda pedaços com o campo dela ({ t: 'campo', v: 'nome_cliente' }). Os
// campos da tela que a campanha liga a uma coluna (data, valor…) e as variáveis
// sem nome de modelo feito fora vão como coluna do Público (publico.data).
// Nada aqui usa expressão regular (regra do Rodrigo): o texto é lido com
// indexOf.

const ABRE = '{{';
const FECHA = '}}';
const PUBLICO = 'publico.';
const VARIAVEL = 'variavel_';

const CATALOGO_NA_TELA = Object.fromEntries(
  Object.entries(CAMPO_NO_CATALOGO).map(([campo, chave]) => [chave, campo])
);

const vaiComoColuna = campo =>
  CAMPOS.includes(campo) || campo.startsWith(VARIAVEL);

export const chaveDoCampo = campo => {
  if (CAMPO_NO_CATALOGO[campo]) return CAMPO_NO_CATALOGO[campo];
  return vaiComoColuna(campo) ? `${PUBLICO}${campo}` : campo;
};

export const campoDaChave = chave => {
  if (CATALOGO_NA_TELA[chave]) return CATALOGO_NA_TELA[chave];
  const coluna = chave.startsWith(PUBLICO) ? chave.slice(PUBLICO.length) : '';
  return coluna && vaiComoColuna(coluna) ? coluna : chave;
};

export const pedacosParaTexto = pedacos =>
  pedacos
    .map(pedaco =>
      pedaco.t === 'campo'
        ? `${ABRE}${chaveDoCampo(pedaco.v)}${FECHA}`
        : pedaco.v
    )
    .join('');

// "Oi, {{cliente.primeiro_nome}}!" → pedaços. Chave sem fechar fica como texto
// (a conferência acusa as chaves soltas e a opção é descartada).
export const textoParaPedacos = texto => {
  const pedacos = [];
  let resto = texto || '';
  while (resto.length) {
    const inicio = resto.indexOf(ABRE);
    const fim = inicio === -1 ? -1 : resto.indexOf(FECHA, inicio);
    if (inicio === -1 || fim === -1) {
      pedacos.push({ t: 'texto', v: resto });
      break;
    }
    if (inicio > 0) pedacos.push({ t: 'texto', v: resto.slice(0, inicio) });
    pedacos.push({ t: 'campo', v: campoDaChave(resto.slice(inicio + 2, fim)) });
    resto = resto.slice(fim + 2);
  }
  return juntarTextos(pedacos);
};

const TIPO_DA_CATEGORIA = { servico: 'aviso', divulgacao: 'divulgacao' };

// Link e telefone vão sem endereço: a pessoa põe o dela (a conferência pede).
const BOTAO_DA_IA = {
  resposta_rapida: 'resposta',
  link: 'site',
  telefone: 'ligar',
};

const nomeLegivel = nome => {
  const texto = (nome || '').split('_').join(' ').trim();
  return texto ? texto.charAt(0).toUpperCase() + texto.slice(1) : '';
};

// O que a regra estrutural da tela confere e que a IA decide. Exemplo de campo
// e endereço de botão ficam fora: quem preenche é a pessoa, no editor.
const CONFERIDO_NA_IA = [
  'TEM_TEXTO',
  'SEM_CHAVES',
  'NAO_COMECA_COM_CAMPO',
  'NAO_TERMINA_COM_CAMPO',
  'CAMPOS_SEPARADOS',
  'TAMANHO',
  'RODAPE',
  'BOTOES',
  'BOTOES_TAMANHO',
  'SO_DIVULGACAO',
];

export const passaNaRegra = (conteudo, tipo) =>
  conferirConteudo(conteudo, { tipo })
    .filter(item => CONFERIDO_NA_IA.includes(item.chave))
    .every(item => item.ok);

// Uma opção do "Criar com IA" no formato da tela. `exemplo(campo)` dá o
// exemplo de um campo da tela ('' para os outros: a pessoa preenche).
export const opcaoDaIA = (opcao, indice, exemplo) => {
  const texto = textoParaPedacos(opcao.text);
  const campos = [...new Set(texto.filter(p => p.t === 'campo').map(p => p.v))];
  return {
    id: `ia-${indice + 1}`,
    nome: nomeLegivel(opcao.name),
    tipo: TIPO_DA_CATEGORIA[opcao.category] || 'divulgacao',
    motivo: opcao.reason || '',
    conteudo: {
      formato: 'padrao',
      topo: { tipo: 'nenhum', arquivo: '' },
      texto,
      exemplos: Object.fromEntries(campos.map(c => [c, exemplo(c)])),
      rodape: opcao.footer || '',
      botoes: ordenarBotoes(
        (opcao.buttons || [])
          .filter(botao => BOTAO_DA_IA[botao.tipo])
          .map(botao => ({
            tipo: BOTAO_DA_IA[botao.tipo],
            texto: botao.texto || '',
            valor: '',
          }))
      ),
    },
  };
};

export const tipoDaCategoria = categoria =>
  TIPO_DA_CATEGORIA[categoria] || 'divulgacao';
