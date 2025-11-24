package br.com.asteria.reskill.dao;

import br.com.asteria.reskill.entity.Recomendacao;
import br.com.asteria.reskill.factory.ConnectionFactory;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class RecomendacaoDAO {

    public void salvar(Recomendacao r) throws SQLException {
        String sql = "INSERT INTO RECOMENDACAO (ID_RECOMENDACAO, ID_USUARIO, ID_CURSO, SCORE, TIPO_RECOMENDACAO) " +
                     "VALUES (SEQ_RECOMENDACAO.NEXTVAL, ?, ?, ?, ?)";
        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setLong(1, r.getIdUsuario());
            ps.setLong(2, r.getIdCurso());
            ps.setObject(3, r.getScore(), Types.DOUBLE);
            ps.setString(4, r.getTipoRecomendacao());
            ps.executeUpdate();
        }
    }

    public List<Recomendacao> listarPorUsuario(Long idUsuario) throws SQLException {
        List<Recomendacao> lista = new ArrayList<>();
        // JOIN para pegar NOME e LINK
        String sql = "SELECT r.ID_RECOMENDACAO, r.ID_USUARIO, r.ID_CURSO, r.SCORE, r.TIPO_RECOMENDACAO, " +
                     "c.NOME, c.CATEGORIA, c.NIVEL, c.CARGA_HORARIA, c.LINK " +
                     "FROM RECOMENDACAO r " +
                     "JOIN CURSO c ON r.ID_CURSO = c.ID_CURSO " +
                     "WHERE r.ID_USUARIO = ? ORDER BY r.SCORE DESC";

        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setLong(1, idUsuario);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Recomendacao r = new Recomendacao();
                    r.setIdRecomendacao(rs.getLong("ID_RECOMENDACAO"));
                    r.setIdUsuario(rs.getLong("ID_USUARIO"));
                    r.setIdCurso(rs.getLong("ID_CURSO"));
                    
                    // Correção BigDecimal
                    java.math.BigDecimal scoreBd = rs.getBigDecimal("SCORE");
                    if (scoreBd != null) r.setScore(scoreBd.doubleValue());
                    
                    r.setTipoRecomendacao(rs.getString("TIPO_RECOMENDACAO"));

                    // Dados do Curso
                    r.setNomeCurso(rs.getString("NOME"));
                    r.setCategoriaCurso(rs.getString("CATEGORIA"));
                    r.setNivelCurso(rs.getString("NIVEL"));
                    
                    java.math.BigDecimal cargaBd = rs.getBigDecimal("CARGA_HORARIA");
                    if (cargaBd != null) r.setCargaHorariaCurso(cargaBd.intValue());
                    
                    r.setLinkCurso(rs.getString("LINK"));
                    lista.add(r);
                }
            }
        }
        return lista;
    }
}