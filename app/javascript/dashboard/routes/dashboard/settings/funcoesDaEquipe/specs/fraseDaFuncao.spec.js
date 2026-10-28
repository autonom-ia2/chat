import {
  PRESETS,
  moduleByKey,
  setLevel,
  toggleExtra,
} from '../../customRoles/permissionMatrix';
import {
  cuidadosDaFuncao,
  fraseDaFuncao,
  mesclarPrevia,
  previaDaFuncao,
} from '../fraseDaFuncao';

// #2308, especificação 7.7 e 8: a fonte única do que a função pode.
const ligarAsDuas = permissions => {
  const area = moduleByKey('CAMPAIGNS');
  return toggleExtra(
    area,
    'campaign_send',
    setLevel(area, 'manage', permissions)
  );
};

describe('fraseDaFuncao', () => {
  it('Atendente: próprias e novas, cria e move as vendas, só olha os contatos', () => {
    expect(fraseDaFuncao(PRESETS.AGENT())).toEqual({
      destaque: 'PROPRIAS_E_NOVAS',
      resto: ['VENDAS_MEXE', 'CONTATOS_SO_OLHA'],
    });
  });

  it('Marketing: não atende, só olha as vendas, dispara campanhas, cria e muda os contatos', () => {
    expect(fraseDaFuncao(PRESETS.MARKETING())).toEqual({
      destaque: 'NAO_ATENDE',
      resto: ['VENDAS_SO_OLHA', 'CAMPANHAS_DISPARA', 'CONTATOS_MEXE'],
    });
  });

  it('área sem acesso não entra; crm_admin cuida de tudo nas vendas', () => {
    expect(fraseDaFuncao(['conversation_manage', 'crm_admin'])).toEqual({
      destaque: 'TODAS',
      resto: ['VENDAS_TUDO'],
    });
  });
});

describe('prévia "Como vai ficar"', () => {
  it('Atendente: Pode, Não pode e menu da especificação 8', () => {
    expect(previaDaFuncao(PRESETS.AGENT())).toMatchObject({
      pode: [
        'RESPONDER_ENTREGUES',
        'PEGAR_NOVAS',
        'AJUDAR_PELO_LINK',
        'CRIAR_MOVER_VENDAS',
      ],
      naoPode: ['LER_COLEGAS', 'MUDAR_CONTATOS', 'EXPORTAR_CONTATOS'],
      menu: ['CONVERSAS', 'CONTATOS', 'VENDAS', 'CENTRAL_DE_AJUDA'],
    });
  });

  it('sem sales_value_view, metas não aparece no Pode (decisão 14A)', () => {
    const tudo = toggleExtra(moduleByKey('CRM'), 'crm_admin', PRESETS.AGENT());
    expect(tudo).toContain('crm_metas_manage');
    expect(previaDaFuncao(tudo).pode).not.toContain('METAS_DO_MES');
    expect(previaDaFuncao([...tudo, 'sales_value_view']).pode).toContain(
      'METAS_DO_MES'
    );
  });

  it('"Ligar as duas" grava exatamente campaign_manage e campaign_send', () => {
    const antes = PRESETS.AGENT();
    expect(ligarAsDuas(antes)).toEqual([
      ...antes,
      'campaign_manage',
      'campaign_send',
    ]);
  });

  it('estável: o novo entra no fim do Pode com "novo"; o Não pode não muda', () => {
    const antes = PRESETS.AGENT();
    const previa = mesclarPrevia(
      previaDaFuncao(antes),
      previaDaFuncao(ligarAsDuas(antes))
    );
    expect(previa.pode.slice(-2)).toEqual([
      { id: 'CAMPAIGN_MANAGE', novo: true },
      { id: 'CAMPAIGN_SEND', novo: true },
    ]);
    expect(previa.pode.filter(item => item.novo)).toHaveLength(2);
    expect(previa.naoPode).toEqual(previaDaFuncao(antes).naoPode);
    expect(previa.menu).toContain('CAMPANHAS');
  });

  it('um item do Pode que sai vai para o Não pode, sem marca, se for das que valem lá', () => {
    const sdr = PRESETS.SDR();
    const soOlhaContatos = setLevel(moduleByKey('CONTACTS'), 'view', sdr);
    const previa = mesclarPrevia(
      previaDaFuncao(sdr),
      previaDaFuncao(soOlhaContatos)
    );
    expect(previa.pode.map(item => item.id)).not.toContain('MUDAR_CONTATOS');
    expect(previa.naoPode).toContain('MUDAR_CONTATOS');
  });
});

describe('selo de cuidado', () => {
  it('Vendedor pronto não tem selo', () => {
    expect(cuidadosDaFuncao(PRESETS.SDR())).toEqual([]);
  });

  it('com crm_admin, as seis que ele inclui ficam dentro dele; disparar vem antes da planilha', () => {
    expect(
      cuidadosDaFuncao([
        'crm_admin',
        'crm_export',
        'crm_metas_manage',
        'contact_export',
        'campaign_send',
      ])
    ).toEqual(['crm_admin', 'campaign_send', 'contact_export']);
  });
});
