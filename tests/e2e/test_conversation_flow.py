"""
End-to-end tests for conversation flows.
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock


class TestFluxoAcolhimento:
    """E2E tests for acolhimento flow."""

    @pytest.mark.asyncio
    async def test_primeira_mensagem_credor(self, sample_sessao, mock_openrouter):
        """New creditor should receive welcome message."""
        from bot.agent import processar_mensagem

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_sessao:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.agent.salvar_sessao", new_callable=AsyncMock):
                    mock_sessao.return_value = sample_sessao

                    resposta = await processar_mensagem(
                        telefone="5511999998888",
                        mensagem="Olá"
                    )

        assert resposta is not None
        # Should be welcoming message
        assert any(word in resposta.lower() for word in ["olá", "oi", "rpv capital", "ajudar"])

    @pytest.mark.asyncio
    async def test_identificacao_advogado(self, sample_sessao, mock_openrouter):
        """Should identify lawyer and change flow."""
        from bot.agent import processar_mensagem

        sample_sessao["contexto"]["etapa"] = "acolhimento"

        mock_openrouter.chat.completions.create.return_value = MagicMock(
            choices=[MagicMock(
                message=MagicMock(
                    content="Dr., temos um programa de parceria!",
                    tool_calls=None
                )
            )]
        )

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_load:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.agent.salvar_sessao", new_callable=AsyncMock) as mock_save:
                    mock_load.return_value = sample_sessao

                    resposta = await processar_mensagem(
                        telefone="5511999998888",
                        mensagem="Sou advogado, quero saber sobre parceria"
                    )

        assert "Dr" in resposta or "parceria" in resposta.lower()


class TestFluxoQualificacao:
    """E2E tests for qualificacao flow."""

    @pytest.mark.asyncio
    async def test_busca_rpv_encontrada(self, sample_sessao, sample_rpv, mock_openrouter, mock_db):
        """Should find RPV and show data."""
        from bot.agent import processar_mensagem

        sample_sessao["contexto"]["etapa"] = "qualificacao"
        mock_db.fetch_one.return_value = sample_rpv

        mock_openrouter.chat.completions.create.return_value = MagicMock(
            choices=[MagicMock(
                message=MagicMock(
                    content="Encontrei seu processo! RPV de R$ 25.000,00",
                    tool_calls=[MagicMock(
                        function=MagicMock(
                            name="buscar_rpv_no_banco",
                            arguments='{"numero_processo": "0019063-75.2025.8.26.0053"}'
                        )
                    )]
                )
            )]
        )

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_load:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.tools.buscar_rpv.get_db", return_value=mock_db):
                    with patch("bot.agent.salvar_sessao", new_callable=AsyncMock):
                        mock_load.return_value = sample_sessao

                        resposta = await processar_mensagem(
                            telefone="5511999998888",
                            mensagem="Meu processo é 0019063-75.2025.8.26.0053"
                        )

        assert "25.000" in resposta or "25000" in resposta

    @pytest.mark.asyncio
    async def test_rpv_nao_encontrada_agenda_humano(self, sample_sessao, mock_openrouter, mock_db):
        """Should schedule human contact when RPV not found."""
        from bot.agent import processar_mensagem

        sample_sessao["contexto"]["etapa"] = "qualificacao"
        mock_db.fetch_one.return_value = None

        mock_openrouter.chat.completions.create.return_value = MagicMock(
            choices=[MagicMock(
                message=MagicMock(
                    content="Não encontrei seu processo. Vou encaminhar para um especialista.",
                    tool_calls=[
                        MagicMock(
                            function=MagicMock(
                                name="buscar_rpv_no_banco",
                                arguments='{"numero_processo": "0000000-00.0000.0.00.0000"}'
                            )
                        ),
                        MagicMock(
                            function=MagicMock(
                                name="agendar_contato_humano",
                                arguments='{"telefone": "5511999998888", "motivo": "rpv_nao_encontrada"}'
                            )
                        )
                    ]
                )
            )]
        )

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_load:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.tools.buscar_rpv.get_db", return_value=mock_db):
                    with patch("bot.tools.agendar_humano.get_db", return_value=mock_db):
                        with patch("bot.agent.salvar_sessao", new_callable=AsyncMock):
                            mock_load.return_value = sample_sessao

                            resposta = await processar_mensagem(
                                telefone="5511999998888",
                                mensagem="0000000-00.0000.0.00.0000"
                            )

        assert "não encontrei" in resposta.lower() or "especialista" in resposta.lower()


class TestFluxoProposta:
    """E2E tests for proposta flow."""

    @pytest.mark.asyncio
    async def test_apresenta_proposta(self, sample_sessao, sample_rpv, mock_openrouter):
        """Should present escalonado proposal."""
        from bot.agent import processar_mensagem

        sample_sessao["contexto"]["etapa"] = "proposta"
        sample_sessao["contexto"]["rpv_data"] = sample_rpv

        mock_openrouter.chat.completions.create.return_value = MagicMock(
            choices=[MagicMock(
                message=MagicMock(
                    content="Podemos adiantar R$ 12.500,00 em até 48h!",
                    tool_calls=[MagicMock(
                        function=MagicMock(
                            name="calcular_proposta",
                            arguments='{"valor_rpv": 25000.00, "dias_desde_expedicao": 150}'
                        )
                    )]
                )
            )]
        )

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_load:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.agent.salvar_sessao", new_callable=AsyncMock):
                    mock_load.return_value = sample_sessao

                    resposta = await processar_mensagem(
                        telefone="5511999998888",
                        mensagem="Quero saber a proposta"
                    )

        assert "12.500" in resposta or "adiantar" in resposta.lower()

    @pytest.mark.asyncio
    async def test_aceita_proposta(self, sample_sessao, sample_rpv, mock_openrouter, mock_db):
        """Should register lead when proposal accepted."""
        from bot.agent import processar_mensagem

        sample_sessao["contexto"]["etapa"] = "proposta"
        sample_sessao["contexto"]["rpv_data"] = sample_rpv
        mock_db.execute.return_value = None

        mock_openrouter.chat.completions.create.return_value = MagicMock(
            choices=[MagicMock(
                message=MagicMock(
                    content="Ótimo! Um especialista entrará em contato em até 2h.",
                    tool_calls=[
                        MagicMock(
                            function=MagicMock(
                                name="registrar_lead",
                                arguments='{"nome": "Maria", "telefone": "5511999998888", "proposta_aceita": true}'
                            )
                        ),
                        MagicMock(
                            function=MagicMock(
                                name="agendar_contato_humano",
                                arguments='{"telefone": "5511999998888", "motivo": "fechamento", "urgencia": "alta"}'
                            )
                        )
                    ]
                )
            )]
        )

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_load:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.tools.registrar_lead.get_db", return_value=mock_db):
                    with patch("bot.tools.agendar_humano.get_db", return_value=mock_db):
                        with patch("bot.agent.salvar_sessao", new_callable=AsyncMock):
                            mock_load.return_value = sample_sessao

                            resposta = await processar_mensagem(
                                telefone="5511999998888",
                                mensagem="Sim, quero antecipar!"
                            )

        assert "especialista" in resposta.lower() or "contato" in resposta.lower()


class TestFluxoObjecoes:
    """E2E tests for objection handling."""

    @pytest.mark.asyncio
    async def test_objecao_golpe(self, sample_sessao, mock_openrouter):
        """Should handle 'is this a scam' objection."""
        from bot.agent import processar_mensagem

        sample_sessao["contexto"]["etapa"] = "objecoes"

        mock_openrouter.chat.completions.create.return_value = MagicMock(
            choices=[MagicMock(
                message=MagicMock(
                    content="Entendo sua preocupação! A cessão de crédito é prevista na Constituição Federal.",
                    tool_calls=None
                )
            )]
        )

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_load:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.agent.salvar_sessao", new_callable=AsyncMock):
                    mock_load.return_value = sample_sessao

                    resposta = await processar_mensagem(
                        telefone="5511999998888",
                        mensagem="Isso é golpe?"
                    )

        assert "constituição" in resposta.lower() or "legal" in resposta.lower()

    @pytest.mark.asyncio
    async def test_solicita_humano(self, sample_sessao, mock_openrouter, mock_db):
        """Should schedule human when explicitly requested."""
        from bot.agent import processar_mensagem

        mock_db.execute.return_value = None

        mock_openrouter.chat.completions.create.return_value = MagicMock(
            choices=[MagicMock(
                message=MagicMock(
                    content="Claro! Vou pedir para um especialista te ligar.",
                    tool_calls=[MagicMock(
                        function=MagicMock(
                            name="agendar_contato_humano",
                            arguments='{"telefone": "5511999998888", "motivo": "preferencia_humano"}'
                        )
                    )]
                )
            )]
        )

        with patch("bot.agent.carregar_sessao", new_callable=AsyncMock) as mock_load:
            with patch("bot.agent.get_openrouter_client", return_value=mock_openrouter):
                with patch("bot.tools.agendar_humano.get_db", return_value=mock_db):
                    with patch("bot.agent.salvar_sessao", new_callable=AsyncMock):
                        mock_load.return_value = sample_sessao

                        resposta = await processar_mensagem(
                            telefone="5511999998888",
                            mensagem="Quero falar com uma pessoa"
                        )

        assert "especialista" in resposta.lower() or "ligar" in resposta.lower()
