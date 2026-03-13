-- RPV Capital - Initial Schema
-- Version: 001
-- Date: 2026-03-13

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =====================================================
-- LEADS E CONVERSAS
-- =====================================================

CREATE TABLE leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT,
    telefone TEXT NOT NULL,
    cpf_cnpj TEXT,  -- Encrypted at application level
    tipo TEXT CHECK (tipo IN ('credor_pf', 'credor_pj', 'advogado')),
    origem TEXT,  -- inbound, outbound, parceiro
    advogado_id UUID,
    numero_processo TEXT,
    valor_rpv DECIMAL(12,2),
    score INTEGER,
    status TEXT DEFAULT 'novo',
    -- Status flow: novo → qualificado → proposta → aceito → cessao → finalizado
    proposta_valor DECIMAL(12,2),
    proposta_aceita BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_leads_telefone ON leads(telefone);
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_leads_created_at ON leads(created_at);

CREATE TABLE sessoes_whatsapp (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    telefone TEXT NOT NULL UNIQUE,
    historico_mensagens JSONB DEFAULT '[]',
    contexto JSONB DEFAULT '{}',  -- rpv_data, etapa, origem
    ultima_interacao TIMESTAMPTZ DEFAULT now(),
    status TEXT DEFAULT 'ativo'  -- ativo, encerrado, handoff
);

CREATE INDEX idx_sessoes_telefone ON sessoes_whatsapp(telefone);
CREATE INDEX idx_sessoes_ultima_interacao ON sessoes_whatsapp(ultima_interacao);

CREATE TABLE mensagens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sessao_id UUID REFERENCES sessoes_whatsapp(id),
    direcao TEXT CHECK (direcao IN ('inbound', 'outbound')),
    tipo TEXT,  -- texto, imagem, audio, template
    conteudo TEXT,
    template_nome TEXT,
    meta_message_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_mensagens_sessao ON mensagens(sessao_id);
CREATE INDEX idx_mensagens_created_at ON mensagens(created_at);

-- =====================================================
-- MOTOR DE DADOS
-- =====================================================

CREATE TABLE pagamentos_rpv (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_rpv TEXT,
    ano_rpv INTEGER,
    numero_processo TEXT,
    credor TEXT,
    cpf_cnpj TEXT,
    valor DECIMAL(12,2),
    data_pagamento DATE,
    status TEXT,  -- aceito, rejeitado
    lote_origem TEXT,
    municipio TEXT DEFAULT 'São Paulo',
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(numero_rpv, ano_rpv, cpf_cnpj)
);

CREATE INDEX idx_pagamentos_processo ON pagamentos_rpv(numero_processo);
CREATE INDEX idx_pagamentos_cpf ON pagamentos_rpv(cpf_cnpj);
CREATE INDEX idx_pagamentos_data ON pagamentos_rpv(data_pagamento);

CREATE TABLE expedicao_rpv (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_processo TEXT UNIQUE,
    data_expedicao DATE,
    prazo_dias INTEGER,
    partes JSONB,
    score INTEGER,
    score_detalhes JSONB,
    fonte TEXT DEFAULT 'esaj',
    consultado_em TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_expedicao_processo ON expedicao_rpv(numero_processo);
CREATE INDEX idx_expedicao_data ON expedicao_rpv(data_expedicao);
CREATE INDEX idx_expedicao_score ON expedicao_rpv(score);

-- =====================================================
-- OPERAÇÃO
-- =====================================================

CREATE TABLE cessoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID REFERENCES leads(id),
    numero_rpv TEXT,
    numero_processo TEXT,
    credor_original TEXT,
    cpf_cnpj_credor TEXT,
    valor_face DECIMAL(12,2),
    valor_adiantamento DECIMAL(12,2),
    data_cessao DATE,
    data_registro_judicial DATE,
    status TEXT DEFAULT 'ativa',
    -- Status flow: ativa → paga_prefeitura → complemento_devido → finalizada
    data_recebimento_prefeitura DATE,
    valor_recebido_prefeitura DECIMAL(12,2),
    prazo_real_dias INTEGER,
    complemento_devido DECIMAL(12,2),
    complemento_pago DECIMAL(12,2),
    data_complemento DATE,
    lucro_realizado DECIMAL(12,2),
    margem_realizada DECIMAL(5,4),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_cessoes_processo ON cessoes(numero_processo);
CREATE INDEX idx_cessoes_status ON cessoes(status);
CREATE INDEX idx_cessoes_data ON cessoes(data_cessao);

-- =====================================================
-- PARCEIROS
-- =====================================================

CREATE TABLE advogados (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT NOT NULL,
    oab TEXT NOT NULL,
    escritorio TEXT,
    telefone TEXT NOT NULL,
    email TEXT,
    comissao_pct DECIMAL(5,4) DEFAULT 0.03,
    status TEXT DEFAULT 'ativo',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_advogados_oab ON advogados(oab);

-- Add foreign key to leads
ALTER TABLE leads ADD CONSTRAINT fk_leads_advogado
    FOREIGN KEY (advogado_id) REFERENCES advogados(id);

CREATE TABLE comissoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    advogado_id UUID REFERENCES advogados(id),
    cessao_id UUID REFERENCES cessoes(id),
    valor DECIMAL(12,2),
    status TEXT DEFAULT 'pendente',  -- pendente, paga
    data_pagamento DATE,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_comissoes_advogado ON comissoes(advogado_id);
CREATE INDEX idx_comissoes_status ON comissoes(status);

-- =====================================================
-- OUTBOUND
-- =====================================================

CREATE TABLE campanhas_outbound (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT,
    template_nome TEXT,
    filtro_valor_min DECIMAL(12,2),
    filtro_atraso_min INTEGER,
    status TEXT DEFAULT 'rascunho',
    -- Status flow: rascunho → agendada → em_andamento → concluida
    disparos_total INTEGER DEFAULT 0,
    respostas_total INTEGER DEFAULT 0,
    conversoes_total INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE disparos_outbound (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campanha_id UUID REFERENCES campanhas_outbound(id),
    telefone TEXT,
    numero_processo TEXT,
    template_params JSONB,
    status TEXT DEFAULT 'pendente',
    -- Status flow: pendente → enviado → respondido → convertido → opt_out
    enviado_em TIMESTAMPTZ,
    respondido_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_disparos_campanha ON disparos_outbound(campanha_id);
CREATE INDEX idx_disparos_telefone ON disparos_outbound(telefone);
CREATE INDEX idx_disparos_processo ON disparos_outbound(numero_processo);

-- =====================================================
-- USUÁRIOS E RBAC
-- =====================================================

CREATE TABLE usuarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognito_sub TEXT UNIQUE,
    nome TEXT NOT NULL,
    email TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'operador', 'analista', 'advogado')),
    telefone TEXT,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_usuarios_email ON usuarios(email);
CREATE INDEX idx_usuarios_role ON usuarios(role);

-- =====================================================
-- TEMPLATES META
-- =====================================================

CREATE TABLE templates_meta (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meta_template_id TEXT,
    nome TEXT NOT NULL,
    categoria TEXT NOT NULL,  -- MARKETING, UTILITY
    status TEXT DEFAULT 'pendente',  -- pendente, aprovado, rejeitado
    corpo TEXT NOT NULL,
    botoes JSONB,
    idioma TEXT DEFAULT 'pt_BR',
    disparos_total INTEGER DEFAULT 0,
    respostas_total INTEGER DEFAULT 0,
    taxa_resposta DECIMAL(5,4),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================
-- AUDIT LOG
-- =====================================================

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID REFERENCES usuarios(id),
    acao TEXT NOT NULL,
    recurso TEXT NOT NULL,
    recurso_id UUID,
    detalhes JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_audit_usuario ON audit_log(usuario_id);
CREATE INDEX idx_audit_acao ON audit_log(acao);
CREATE INDEX idx_audit_created ON audit_log(created_at);

-- =====================================================
-- MONITORAMENTO
-- =====================================================

CREATE TABLE monitoramento_crawler (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo TEXT,  -- crawler_prefeitura, esaj_batch
    status TEXT,  -- sucesso, erro
    registros_processados INTEGER,
    detalhes JSONB,
    executado_em TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_monitoramento_tipo ON monitoramento_crawler(tipo);
CREATE INDEX idx_monitoramento_data ON monitoramento_crawler(executado_em);

-- =====================================================
-- VIEWS
-- =====================================================

CREATE VIEW v_rpvs_elegiveis_outbound AS
SELECT
    e.numero_processo,
    p.credor,
    p.cpf_cnpj,
    p.valor,
    e.data_expedicao,
    CURRENT_DATE - e.data_expedicao AS dias_atraso,
    e.score
FROM expedicao_rpv e
JOIN pagamentos_rpv p ON e.numero_processo = p.numero_processo
WHERE p.status = 'aceito'
  AND p.valor >= 15000
  AND (CURRENT_DATE - e.data_expedicao) > 60
  AND (e.score IS NULL OR e.score >= 40)
  AND NOT EXISTS (
      SELECT 1 FROM cessoes c WHERE c.numero_processo = e.numero_processo
  )
  AND NOT EXISTS (
      SELECT 1 FROM disparos_outbound d
      WHERE d.numero_processo = e.numero_processo
      AND d.created_at > CURRENT_DATE - INTERVAL '30 days'
  );

CREATE VIEW v_portfolio AS
SELECT
    c.*,
    e.data_expedicao,
    COALESCE(c.prazo_real_dias, CURRENT_DATE - e.data_expedicao) AS dias_corridos
FROM cessoes c
LEFT JOIN expedicao_rpv e ON c.numero_processo = e.numero_processo;

CREATE VIEW v_financeiro AS
SELECT
    SUM(valor_face) AS carteira_face,
    SUM(valor_adiantamento) AS total_adiantado,
    SUM(CASE WHEN status != 'ativa' THEN valor_recebido_prefeitura ELSE 0 END) AS total_recebido,
    SUM(COALESCE(complemento_pago, 0)) AS total_complementos,
    SUM(COALESCE(lucro_realizado, 0)) AS lucro_total,
    AVG(CASE WHEN status = 'finalizada' THEN margem_realizada END) AS margem_media,
    COUNT(*) FILTER (WHERE status = 'ativa') AS rpvs_ativas,
    COUNT(*) FILTER (WHERE status = 'finalizada') AS rpvs_finalizadas
FROM cessoes;

-- =====================================================
-- FUNCTIONS
-- =====================================================

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER leads_updated_at
    BEFORE UPDATE ON leads
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER cessoes_updated_at
    BEFORE UPDATE ON cessoes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER templates_meta_updated_at
    BEFORE UPDATE ON templates_meta
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
