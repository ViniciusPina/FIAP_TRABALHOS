package br.com.asteria.reskill.dao;

import br.com.asteria.reskill.entity.Inscricao;
import br.com.asteria.reskill.factory.ConnectionFactory;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class InscricaoDAO {

    public Inscricao inserir(Inscricao i) throws SQLException {
        String sql = "INSERT INTO INSCRICAO (ID_INSCRICAO, ID_USUARIO, ID_CURSO, PROGRESSO, AVALIACAO) " +
                     "VALUES (SEQ_INSCRICAO.NEXTVAL, ?, ?, ?, ?)";

        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, new String[] { "ID_INSCRICAO" })) {
            ps.setLong(1, i.getIdUsuario());
            ps.setLong(2, i.getIdCurso());
            ps.setObject(3, i.getProgresso(), Types.INTEGER);
            ps.setObject(4, i.getAvaliacao(), Types.INTEGER);
            ps.executeUpdate();

            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) {
                    i.setIdInscricao(rs.getLong(1));
                }
            }
        }
        return i;
    }

    public List<Inscricao> listarPorUsuario(Long idUsuario) throws SQLException {
        List<Inscricao> lista = new ArrayList<>();
        String sql = "SELECT ID_INSCRICAO, ID_USUARIO, ID_CURSO, PROGRESSO, AVALIACAO " +
                     "FROM INSCRICAO WHERE ID_USUARIO = ?";

        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setLong(1, idUsuario);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Inscricao i = new Inscricao();
    i.setIdInscricao(rs.getLong("ID_INSCRICAO"));
    i.setIdUsuario(rs.getLong("ID_USUARIO"));
    i.setIdCurso(rs.getLong("ID_CURSO"));

    // --- CORREÇÃO PROGRESSO ---
    java.math.BigDecimal progressoBd = rs.getBigDecimal("PROGRESSO");
    if (progressoBd != null) {
        i.setProgresso(progressoBd.intValue());
    } else {
        i.setProgresso(null);
    }

    // --- CORREÇÃO AVALIACAO ---
    java.math.BigDecimal avaliacaoBd = rs.getBigDecimal("AVALIACAO");
    if (avaliacaoBd != null) {
        i.setAvaliacao(avaliacaoBd.intValue());
    } else {
        i.setAvaliacao(null);
    }

    lista.add(i);
                }
            }
        }
        return lista;
    }
}