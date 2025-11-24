package br.com.asteria.reskill.dao;

import br.com.asteria.reskill.entity.Curso;
import br.com.asteria.reskill.factory.ConnectionFactory;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class CursoDAO {

    public Curso inserir(Curso c) throws SQLException {
        String sql = "INSERT INTO CURSO (ID_CURSO, NOME, CATEGORIA, NIVEL, CARGA_HORARIA) " +
                     "VALUES (SEQ_CURSO.NEXTVAL, ?, ?, ?, ?)";

        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, new String[] { "ID_CURSO" })) {
            ps.setString(1, c.getNome());
            ps.setString(2, c.getCategoria());
            ps.setString(3, c.getNivel());
            ps.setObject(4, c.getCargaHoraria(), Types.INTEGER);
            ps.executeUpdate();

            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) {
                    c.setIdCurso(rs.getLong(1));
                }
            }
        }
        return c;
    }

    public List<Curso> listarTodos() throws SQLException {
        List<Curso> lista = new ArrayList<>();
        String sql = "SELECT ID_CURSO, NOME, CATEGORIA, NIVEL, CARGA_HORARIA FROM CURSO";

        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Curso c = new Curso();
                c.setIdCurso(rs.getLong("ID_CURSO"));
                c.setNome(rs.getString("NOME"));
                c.setCategoria(rs.getString("CATEGORIA"));
                c.setNivel(rs.getString("NIVEL"));
                java.math.BigDecimal cargaBd = rs.getBigDecimal("CARGA_HORARIA");
                if (cargaBd != null) {
                c.setCargaHoraria(cargaBd.intValue());
                } else {
                    c.setCargaHoraria(null);
                }
                lista.add(c);
            }
        }
        return lista;
    }
}