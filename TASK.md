# RPV Capital — Backlog de Tarefas

## Legenda de Status
- [ ] Pendente
- [~] Em progresso
- [x] Concluído
- [!] Bloqueado

## Legenda de Prioridade
- **P0** — Crítico, bloqueia outras tarefas
- **P1** — Importante, necessário para MVP
- **P2** — Desejável, pode esperar

---

## Sprint 1: Infra + Motor de Dados (Semanas 1-2)

### Setup AWS
- [ ] **P0** | Criar VPC com subnets públicas e privadas
- [ ] **P0** | Provisionar RDS PostgreSQL (db.t4g.micro)
- [ ] **P0** | Configurar Secrets Manager (Meta, OpenRouter, RDS)
- [ ] **P0** | Criar repositório ECR para containers
- [ ] **P0** | Configurar EventBridge Scheduler
- [ ] **P1** | Setup Cognito User Pool com 4 roles
- [ ] **P1** | Configurar CloudWatch Log Groups

### Crawler Prefeitura
- [ ] **P0** | Implementar descoberta de novos PDFs na página da Prefeitura
- [ ] **P0** | Implementar download de PDFs
- [ ] **P0** | Implementar parser pdfplumber
- [ ] **P0** | Normalização de processo 19→20 dígitos
- [ ] **P0** | Salvar em tabela `pagamentos_rpv`
- [ ] **P1** | Deploy Lambda + EventBridge cron 6h

### Enriquecimento ESAJ
- [ ] **P0** | Implementar consulta TJSP com Playwright
- [ ] **P0** | Extrair data de expedição da movimentação
- [ ] **P0** | Extrair partes do processo
- [ ] **P0** | Rate limiting 4s entre requests
- [ ] **P0** | Salvar em tabela `expedicao_rpv`
- [ ] **P1** | Build container Docker com Playwright
- [ ] **P1** | Deploy ECS Task + EventBridge cron 7h

### Scoring
- [ ] **P1** | Implementar cálculo de score de risco
- [ ] **P1** | Criar view `v_rpvs_elegiveis_outbound`

### Database
- [ ] **P0** | Criar migration inicial (todas as tabelas)
- [ ] **P0** | Aplicar migration no RDS
- [ ] **P1** | Criar views (v_portfolio, v_financeiro)

---

## Sprint 2: Bot WhatsApp MVP (Semanas 3-4)

### Setup Meta Cloud API
- [ ] **P0** | Criar Meta Business Account
- [ ] **P0** | Criar WhatsApp Business Account (WABA)
- [ ] **P0** | Vincular número de telefone
- [ ] **P0** | Criar App no Meta for Developers
- [ ] **P0** | Configurar webhook URL

### Webhook FastAPI
- [ ] **P0** | Implementar GET /webhook (verificação Meta)
- [ ] **P0** | Implementar POST /webhook (receber mensagens)
- [ ] **P0** | Validar assinatura X-Hub-Signature-256
- [ ] **P0** | Implementar envio de mensagem (texto)
- [ ] **P0** | Implementar envio de template
- [ ] **P1** | Processar mensagens de imagem (Claude Vision)
- [ ] **P2** | Processar mensagens de áudio (Whisper)

### Integração OpenRouter
- [ ] **P0** | Configurar client OpenRouter (OpenAI-compatible)
- [ ] **P0** | Implementar seleção de modelo por tarefa
- [ ] **P0** | Implementar fallback entre providers
- [ ] **P1** | Monitorar custos por tarefa

### Agent Skills
- [ ] **P0** | Criar estrutura .skills/
- [ ] **P0** | Implementar skill rpv-acolhimento
- [ ] **P0** | Implementar skill rpv-qualificacao
- [ ] **P0** | Implementar skill rpv-proposta
- [ ] **P0** | Implementar skill rpv-objecoes
- [ ] **P1** | Implementar skill rpv-advogado
- [ ] **P1** | Implementar skill rpv-outbound

### Tools do Agente
- [ ] **P0** | Tool buscar_rpv_no_banco
- [ ] **P0** | Tool calcular_proposta
- [ ] **P0** | Tool registrar_lead
- [ ] **P0** | Tool verificar_cessao_anterior
- [ ] **P1** | Tool agendar_contato_humano
- [ ] **P1** | Tool enviar_template_meta
- [ ] **P2** | Tool buscar_faq

### Sessões
- [ ] **P0** | Implementar carregamento de sessão (PostgreSQL)
- [ ] **P0** | Implementar salvamento de sessão
- [ ] **P0** | Gerenciar histórico de mensagens
- [ ] **P1** | Expiração de sessão após 24h inatividade

### Deploy
- [ ] **P0** | Build container Docker do bot
- [ ] **P0** | Push para ECR
- [ ] **P0** | Deploy ECS Fargate Service
- [ ] **P0** | Configurar health check /health
- [ ] **P1** | Configurar auto-scaling (se necessário)

---

## Sprint 3: Outbound + Dashboard + RBAC (Semanas 5-6)

### Templates Meta
- [ ] **P0** | Submeter template rpv_antecipacao_inicial
- [ ] **P0** | Submeter template rpv_followup
- [ ] **P0** | Submeter template rpv_pagamento_detectado
- [ ] **P1** | Submeter template rpv_advogado_parceria
- [ ] **P1** | Implementar tela de gestão de templates

### Outbound Workflow
- [ ] **P0** | Implementar Lambda outbound_scheduler
- [ ] **P0** | Seleção de RPVs elegíveis
- [ ] **P0** | Disparo de templates via Meta API
- [ ] **P0** | Registro em disparos_outbound
- [ ] **P0** | Deploy Lambda + EventBridge cron 9h
- [ ] **P1** | Respeitar opt-out
- [ ] **P1** | Não repetir contato em 30 dias

### RBAC
- [ ] **P0** | Configurar grupos no Cognito (admin, operador, analista, advogado)
- [ ] **P0** | Implementar middleware de autorização FastAPI
- [ ] **P0** | Decorator @require_role
- [ ] **P1** | Mascaramento de CPF por role

### Dashboard
- [ ] **P1** | Setup projeto React + Tailwind + shadcn/ui
- [ ] **P1** | Implementar autenticação Cognito (Amplify Auth)
- [ ] **P1** | Tela Home (cards de métricas + alertas)
- [ ] **P1** | Tela Portfólio (tabela de RPVs em carteira)
- [ ] **P1** | Deploy Amplify
- [ ] **P2** | Tela Leads/CRM (pipeline Kanban)
- [ ] **P2** | Tela Outbound (métricas de campanha)

### Alertas
- [ ] **P0** | Implementar job verificar_pagamentos (APScheduler)
- [ ] **P0** | Alertar operador quando RPV em carteira é paga
- [ ] **P1** | Implementar Lambda relatorio_diario
- [ ] **P1** | Deploy Lambda + EventBridge cron 18h

---

## Sprint 4: Portal Advogado + Refinamentos (Semanas 7-8)

### Portal Advogado
- [ ] **P1** | Setup projeto React separado
- [ ] **P1** | Tela de cadastro (nome, OAB, escritório)
- [ ] **P1** | Tela de indicar RPV
- [ ] **P1** | Tela de acompanhar indicações
- [ ] **P1** | Dashboard de comissões
- [ ] **P1** | Deploy Amplify

### Dashboard Financeiro
- [ ] **P1** | Tela Financeiro (fluxo caixa, ROI)
- [ ] **P1** | Gráficos com Recharts
- [ ] **P1** | Projeções baseadas em carteira

### Follow-up
- [ ] **P2** | Implementar Lambda followup_leads
- [ ] **P2** | Identificar leads sem resposta há 7 dias
- [ ] **P2** | Deploy Lambda + EventBridge cron 10h

### Compliance
- [ ] **P2** | Implementar audit_log
- [ ] **P2** | Log de todas as ações sensíveis
- [ ] **P2** | Implementar mascaramento de CPF para analistas

### Refinamentos
- [ ] **P2** | Suporte a áudio (transcrição Whisper)
- [ ] **P2** | Skill rpv-fallback (quando bot não entende)
- [ ] **P2** | Circuit breaker para OpenRouter e RDS
- [ ] **P2** | Testes de carga

---

## Backlog Futuro (Pós-MVP)

### Fase 2 — Escala
- [ ] **Integração BigData Corp/Neoway** para enriquecimento de telefones
- [ ] Lambda enrich_telefone (batch diário)
- [ ] Tabela leads_enriquecidos
- [ ] LIA (Legitimate Interest Assessment) para LGPD
- [ ] SQS para fila de outbound (quando > 500 msgs/dia)
- [ ] Provisioned concurrency para Lambdas críticas
- [ ] Multi-região para disaster recovery
- [ ] API pública para parceiros

### Fase 3 — Expansão
- [ ] Suporte a outros municípios (além de SP)
- [ ] Suporte a precatórios (além de RPVs)
- [ ] App mobile para credores
- [ ] Integração com bancos para pagamento automático

---

## Blockers Atuais

| ID | Descrição | Responsável | Status |
|----|-----------|-------------|--------|
| ~~B1~~ | ~~Obtenção de telefones para outbound~~ | Wagner | Decidido: BigData Corp/Neoway |
| B2 | Aprovação de templates Meta | Wagner | Aguardando submissão |
| B3 | Validação LGPD para enrichment | Wagner | Pendente (consultar advogado) |

## Decisões Registradas

| Data | Decisão | Contexto |
|------|---------|----------|
| 2026-03-13 | BigData Corp/Neoway para telefones | Integrar após validar unit economics do MVP |

---

## Métricas de Sprint

### Sprint 1
- [ ] Crawler funcionando e populando banco
- [ ] ESAJ batch enriquecendo RPVs
- [ ] >100 RPVs no banco com dados completos

### Sprint 2
- [ ] Bot respondendo mensagens inbound
- [ ] Fluxo completo: acolhimento → qualificação → proposta
- [ ] Primeira conversa real com credor

### Sprint 3
- [ ] Templates aprovados pela Meta
- [ ] Primeiro disparo outbound
- [ ] Dashboard acessível com métricas básicas

### Sprint 4
- [ ] Portal advogado funcional
- [ ] Primeiro advogado cadastrado
- [ ] Primeira cessão realizada via plataforma
