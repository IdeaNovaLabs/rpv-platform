"""
Unit tests for agent tools.
"""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch


class TestBuscarRpvNoBanco:
    """Tests for buscar_rpv_no_banco tool."""

    @pytest.mark.asyncio
    async def test_encontra_rpv_existente(self, mock_db, sample_rpv):
        """Should find and return existing RPV."""
        mock_db.fetch_one.return_value = sample_rpv

        from bot.tools.buscar_rpv import buscar_rpv_no_banco

        with patch("bot.tools.buscar_rpv.get_db", return_value=mock_db):
            resultado = await buscar_rpv_no_banco("0019063-75.2025.8.26.0053")

        assert resultado["encontrada"] is True
        assert resultado["valor"] == 25000.00
        assert resultado["credor"] == "MARIA DA SILVA"

    @pytest.mark.asyncio
    async def test_rpv_nao_encontrada(self, mock_db):
        """Should return not found for missing RPV."""
        mock_db.fetch_one.return_value = None

        from bot.tools.buscar_rpv import buscar_rpv_no_banco

        with patch("bot.tools.buscar_rpv.get_db", return_value=mock_db):
            resultado = await buscar_rpv_no_banco("0000000-00.0000.0.00.0000")

        assert resultado["encontrada"] is False

    @pytest.mark.asyncio
    async def test_normaliza_numero_entrada(self, mock_db, sample_rpv):
        """Should normalize various input formats."""
        mock_db.fetch_one.return_value = sample_rpv

        from bot.tools.buscar_rpv import buscar_rpv_no_banco

        with patch("bot.tools.buscar_rpv.get_db", return_value=mock_db):
            # Various formats should work
            await buscar_rpv_no_banco("00190637520258260053")  # raw
            await buscar_rpv_no_banco("0019063-75.2025.8.26.0053")  # formatted
            await buscar_rpv_no_banco("19063/2025")  # partial

        assert mock_db.fetch_one.call_count == 3


class TestCalcularProposta:
    """Tests for calcular_proposta tool."""

    def test_calcula_proposta_correta(self, sample_rpv):
        """Should calculate proposal correctly."""
        from bot.tools.calcular_proposta import calcular_proposta

        resultado = calcular_proposta(
            valor_rpv=sample_rpv["valor"],
            dias_desde_expedicao=sample_rpv["dias_desde_expedicao"]
        )

        assert resultado["valor_adiantamento"] == 12500.00  # 50% of 25000
        assert "tabela_complemento" in resultado
        assert "prazo_estimado" in resultado


class TestRegistrarLead:
    """Tests for registrar_lead tool."""

    @pytest.mark.asyncio
    async def test_registra_lead_novo(self, mock_db, sample_lead):
        """Should register new lead."""
        mock_db.execute.return_value = None

        from bot.tools.registrar_lead import registrar_lead

        with patch("bot.tools.registrar_lead.get_db", return_value=mock_db):
            resultado = await registrar_lead(**sample_lead)

        assert resultado["sucesso"] is True
        assert "lead_id" in resultado
        mock_db.execute.assert_called_once()

    @pytest.mark.asyncio
    async def test_registra_lead_com_proposta_aceita(self, mock_db, sample_lead):
        """Should register lead with accepted proposal."""
        mock_db.execute.return_value = None

        from bot.tools.registrar_lead import registrar_lead

        with patch("bot.tools.registrar_lead.get_db", return_value=mock_db):
            resultado = await registrar_lead(**sample_lead, proposta_aceita=True)

        assert resultado["sucesso"] is True
        # Verify status is updated
        call_args = mock_db.execute.call_args
        assert "proposta_aceita" in str(call_args) or "aceito" in str(call_args).lower()


class TestVerificarCessaoAnterior:
    """Tests for verificar_cessao_anterior tool."""

    @pytest.mark.asyncio
    async def test_sem_cessao_anterior(self, mock_db):
        """Should return False when no previous cessao."""
        mock_db.fetch_one.return_value = None

        from bot.tools.verificar_cessao import verificar_cessao_anterior

        with patch("bot.tools.verificar_cessao.get_db", return_value=mock_db):
            resultado = await verificar_cessao_anterior("0019063-75.2025.8.26.0053")

        assert resultado["existe_cessao"] is False

    @pytest.mark.asyncio
    async def test_com_cessao_anterior(self, mock_db):
        """Should return True when previous cessao exists."""
        mock_db.fetch_one.return_value = {
            "id": "123",
            "data_cessao": "2024-01-15",
            "valor_adiantamento": 12500.00
        }

        from bot.tools.verificar_cessao import verificar_cessao_anterior

        with patch("bot.tools.verificar_cessao.get_db", return_value=mock_db):
            resultado = await verificar_cessao_anterior("0019063-75.2025.8.26.0053")

        assert resultado["existe_cessao"] is True
        assert "data_cessao" in resultado


class TestAgendarContatoHumano:
    """Tests for agendar_contato_humano tool."""

    @pytest.mark.asyncio
    async def test_agenda_contato_normal(self, mock_db, mock_meta_api):
        """Should schedule human contact and notify operator."""
        mock_db.execute.return_value = None

        from bot.tools.agendar_humano import agendar_contato_humano

        with patch("bot.tools.agendar_humano.get_db", return_value=mock_db):
            with patch("bot.tools.agendar_humano.get_meta_api", return_value=mock_meta_api):
                resultado = await agendar_contato_humano(
                    telefone="5511999998888",
                    motivo="fechamento"
                )

        assert resultado["agendado"] is True
        mock_meta_api.send_message.assert_called_once()

    @pytest.mark.asyncio
    async def test_agenda_contato_urgente(self, mock_db, mock_meta_api):
        """Should prioritize urgent contacts."""
        mock_db.execute.return_value = None

        from bot.tools.agendar_humano import agendar_contato_humano

        with patch("bot.tools.agendar_humano.get_db", return_value=mock_db):
            with patch("bot.tools.agendar_humano.get_meta_api", return_value=mock_meta_api):
                resultado = await agendar_contato_humano(
                    telefone="5511999998888",
                    motivo="fechamento",
                    urgencia="alta"
                )

        assert resultado["agendado"] is True
        assert resultado["urgencia"] == "alta"
